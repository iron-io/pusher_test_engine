require 'puma'
require 'sinatra'

require 'net/http'
require 'uri'

configure {
  set :server, :puma
  set :bind, '0.0.0.0'
}

# enable :logging

KNOWN_PATH_ARGS = [
  'code',
  'delay',
  'on_try',
  'fail_code',
  'acknowledge',
  'acknowledge_delay'
]

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

def run_acknowledge_in(delay, url, body = nil, headers = {})
  return if url.nil? || url.empty?

  sleep delay.to_i

  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Delete.new(uri.path, headers)
  response = http.request(request, body.to_json) # nil.to_json => "null"
  # puts response.body
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
  with_code(pargs['code'])
  sleep pargs['delay'].to_i if pargs['delay'].to_i > 0

  if pargs['acknowledge']
    push_url, push_body = get_push_url_and_body(request)
    Thread.new {
      run_acknowledge_in(pargs['acknowledge_delay'],
                         push_url, push_body,
                         { 'Content-Type' => 'application/json' })
    }
  end

  ''
end
