require 'iron_mq'
require 'colorize'

class TestEngine
  def initialize(config_file = 'test_engine.json')
    raise 'Configuration file is not provided.' if nil_or_empty?(config_file)

    conf = load_json_file(config_file)
    @base_url = conf['base_url']
    raise 'Base URL is not set.' if nil_or_empty?(@base_url)

    # removes terminal `/` sign(s)
    while @base_url[-1] == '/' do
      @base_url = @base_url[0..-2]
    end

    # IronMQ configuration must be placed in
    # iron.json file in the same directory
    @imq = IronMQ::Client.new
    @test_queue = nil
  end

  def test(params = {})
    if nil_or_empty?(params)
      puts 'ERROR: Not implemented.'.red
      return
    end

    if nil_or_empty?(params['configuration'])
      puts 'ERROR: Configuration for the test is not provided.'.red
    end
    @test_conf = params['configuration']

    make_push_queue(params['queue'], params['subscribers'])

    res = run_test(params['subscribers'])
    res ? 'TEST PASSED'.green.bold : 'TEST FAILED'.red.bold

    res
  end

  def load_and_run_test_file(name)
    test_data = load_json_file(name)
    print_comment_from(test_data, true)

    test_data.each_pair do |test_name, data|
      puts "Test '#{test_name}':"
      print_comment_from(data)

      test(data)
    end
  end

  private

  def nil_or_empty?(value)
    value.nil? || value.empty?
  end

  def load_json_file(name)
    JSON.parse(File.read(name))
  end

  # It also removes comment from `hash`
  def print_comment_from(hash, insert_line = false)
    comment = hash.delete('comment')

    unless nil_or_empty?(comment)
      puts('-' * comment.length) if insert_line
      puts(comment)
      puts('-' * comment.length) if insert_line
    end
  end

  def make_subscriber_url(params)
    # Output format is "BASE_URL/KEY_1/VALUE_1.../KEY_N/VALUE_N"
    params.each_with_object(String.new(@base_url)) do |(k, v), memo|
      memo << "/#{k}/#{v}"
    end
  end

  def make_subscribers(params_list)
    params_list.each_with_object([]) do |(sub_name, params), memo|
      next if nil_or_empty?(sub_name) || params['code'].to_i == 0
      memo << { name: sub_name, url: make_subscriber_url(params) }
    end
  end

  def make_push_queue(params = {}, subscribers = {})
    raise 'Queue parameters absent.' if nil_or_empty?(params)

    queue_name = params.delete('name')
    raise 'Queue name is not set.' if nil_or_empty?(queue_name)

    raise 'Queue type is not set.' if nil_or_empty?(params['type'])

    params['push'] ||= {} # IronMQ has default params for all except subscribers
    raise 'Queue subscribers config is absent.' if nil_or_empty?(subscribers)
    params['push']['subscribers'] = make_subscribers(subscribers)

    @test_queue = @imq.queue(queue_name)
    @test_queue.delete_queue # clear queue, its configuration, etc.
    resp = @test_queue.update_queue({ queue: params })

    @test_queue
  end

  def post_n_samples(n, msg = {})
    raise 'Sample message is not provided.' if nil_or_empty?(msg)
    raise 'Sample message body is not set.' if nil_or_empty?(msg['body'])

    resp = @test_queue.post Array.new(n, msg)

    resp['ids']
  end

  def calculate_waits_for(subscribers)
    subscribers.each_with_object({}) do |(name, params), memo|
      memo[name] = { 'code' => params['code'].to_i,
                     'wait' => calculate_wait(params) }
    end
  end

  def calculate_wait(params)
    wait = 0
    # get retries delay from queue info
    retries_delay = @test_queue.push_info['retries_delay'].to_i
    # delay is 0 if it is not set
    delay = params['delay'].to_i
    # return requested code on first try by default
    on_try = (params['on_try'] || 1).to_i
    fail_code = (params['fail_code'] || 503).to_i

    case params['code'].to_i
    when 200
      delay # must be acknowledged after first subscriber response
    when 202
      raise 'NOT IMPLEMENTED.'
    else
      delay * on_try + retries_delay * (on_try - 1)
    end
  end

  def wait_next(waits)
    subscriber_names = find_min_wait_keys(waits)

    wait = 0; subs_codes = {}
    subscriber_names.each do |sname|
      data = waits.delete(sname)
      wait = data['wait']
      subs_codes[sname] = data['code']
    end
    if waits.size > 0
      subsctract_wait(wait, waits)
    end

    sleep wait

    subs_codes
  end

  def find_min_wait_keys(waits)
    subscribers = []
    min_wait = nil
    waits.each do |name, data|
      if min_wait.nil? || min_wait == data['wait']
        subscribers << name
        min_wait = data['wait']
      elsif min_wait > data['wait']
        subscribers = [ name ]
        min_wait = data['wait']
      end
    end

    subscribers
  end

  def subsctract_wait(wt, waits)
    waits.each { |k, v| waits[k]['wait'] = v['wait'] - wt }
  end

  def check_push_statuses(msg_id, push_statuses, subscribers_codes)
    subscribers_codes.each do |sname, scode|
      info = "Message ID: #{msg_id}, subscriber: #{sname}"
      code_found = false
      push_statuses.each do |ps|
        next unless ps['subscriber_name'] == sname
        code_found = true

        if scode == ps['status_code'].to_i
          puts "#{info} -- PASSED".green
        else
          if ![200, 202].include?(scode) && @test_queue.type == 'unicast'
            puts "#{info} -- PASSED".green + ' (no push status on unicast subscriber)'.yellow
          else
            puts "#{info} -- FAILED".red
          end
        end
      end

      unless code_found
        puts "#{info} -- FAILED".red + ' (push status not found)'.yellow
      end
    end
  end

  def run_test(subscribers)
    if @test_queue.nil?
      puts 'ERROR: Test queue is not configured.'.red
      return
    end

    waits = calculate_waits_for(subscribers)
    ids = post_n_samples(@test_conf['messages_count'],
                         @test_conf['sample_message'])
    if nil_or_empty?(ids)
      puts 'ERROR: Cannot post messages to IronMQ'.red
      return
    end
    # NOTE: increase this delay in the case internet connection
    #       between IronMQ and test server is slow, or
    #       you run at least one of them on weak, maybe single core, system.
    sleep 1

    until waits.empty?
      subs_codes = wait_next(waits)

      ids.each do |id|
        push_statuses = get_push_statuses(id)
        # The last try
        if nil_or_empty?(push_statuses)
          puts "No push statuses for message ID #{id} -- FAILED.".red
        else
          check_push_statuses(id, push_statuses, subs_codes)
        end
      end
    end
  end

  def get_push_statuses(message_id)
    push_statuses = []
    retries = 3
    while retries > 0 do
      msg = @test_queue.get_message(message_id)
      push_statuses = msg.push_statuses
      break unless nil_or_empty?(push_statuses)

      retries -= 1
      sleep 0.5
    end

    push_statuses
  end

end
