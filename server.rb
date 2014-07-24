require 'net/http'
require 'uri'
require 'json'

require 'puma'
require 'sinatra'

require 'data_mapper'

require 'rufus-scheduler'

DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/server.db")

class Task
  include DataMapper::Resource

  property :id,     Serial
  property :url,    Text,    required: true
  property :body,   Text,    required: true
  property :run_at, Integer, required: true, index: true
end

# Contains request count for unique pairs of [message_id, subscriber_name]
class PushRecord
  include DataMapper::Resource

  property :id,              Serial
  property :message_id,      String,  required: true, index: true
  property :subscriber_name, String,  required: true, index: true
  property :request_count,   Integer, required: true, default: 0
end

DataMapper.finalize.auto_upgrade!

configure {
  set :server, :puma
  set :bind, '0.0.0.0'
}

# enable :logging

scheduler = Rufus::Scheduler.new
scheduler.every '1s' do
  tasks = Task.all(:run_at.lte => Time.now.to_i)
  tasks.each do |t|
    run_acknowledge(t.url, t.body)

    puts 'Cannot remove task!' unless t.destroy
  end
end

KNOWN_PATH_ARGS = [
  'code',
  'delay',
  'on_try',
  'fail_code',
  'acknowledge',
  'acknowledge_delay'
]

DEFAULT_FAIL_CODE = 503

def parse_path(path)
  path = path[1..-1] if path[0] == '/'
  args = path.split('/')
  args.pop if args.size % 2 != 0

  Hash[ *args ].keep_if { |k, v| KNOWN_PATH_ARGS.include?(k) && !v.empty? }
end

def with_code(code)
  content_type request.env['CONTENT_TYPE']
  status code.to_i if code.to_i > 0
end

def run_acknowledge(url, body)
  return if url.nil? || url.empty?

  Thread.start {
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Delete.new(uri.path,
                                    { 'Content-Type' => 'application/json' })
    begin
      response = http.request(request, body)
    rescue Exception => e
      puts "Cannot acknowledge! URL: '#{url}', Error: '#{e}'."
    end
  }
end

def get_push_url_and_body(req)
  url = req.env['HTTP_IRON_SUBSCRIBER_MESSAGE_URL']
  body = {
    id: req.env['HTTP_IRON_MESSAGE_ID'],
    subscriber_name: req.env['HTTP_IRON_SUBSCRIBER_NAME'],
    reservation_id: req.env['HTTP_IRON_RESERVATION_ID']
  }

  [url, body]
end

post '/*' do
  # puts request.env
  pargs = parse_path(request.path)
  push_url, push_body = get_push_url_and_body(request)

  on_try = pargs['on_try'].to_i # nil.to_i == 0
  return_fail = false
  if on_try > 1
    push = PushRecord.first_or_new(message_id: push_body[:id],
                                   subscriber_name: push_body[:subscriber_name])
    push.request_count += 1

    if push.request_count >= on_try
      with_code(pargs['code'])
    else
      return_fail = true
      with_code(pargs['fail_code'] || DEFAULT_FAIL_CODE)
    end

    puts 'Cannot save PushRecord!' unless push.save
  else
    with_code(pargs['code'])
  end

  delay = pargs['delay'].to_i
  sleep delay if delay > 0

  # Do not run acknowledgement if server must return fail code this try
  if pargs['acknowledge'].to_i > 0 && !return_fail
    ack_delay = pargs['acknowledge_delay'].to_i
    if ack_delay > 0
      t = Task.create(url: push_url,
                      body: push_body.to_json,
                      run_at: Time.now.to_i + ack_delay)
      unless t.saved?
        puts 'Cannot save task!'
        t.errors.each { |e| puts e }
      end
    else
      run_acknowledge(push_url, push_body.to_json)
    end
  end

  '' # return empty response body
end
