Pusher v.3 Test Engine
----------------

### Files

* `Gemfile` - Bundler's file for Ruby gems installation

* `iron.json` - standard Iron.io configuration file for IronMQ

* `test_engine.rb` - contains code of Pusher's Test Engine

* `test_engine.json` - configuration file for Pusher's Test Engine

* `server.rb` - Sinatra HTTP application, powered by Puma HTTP server (multithreaded)

* `run_tests.rb` - file to run tests ( :

* `test_multi.json` - contains tests for multicast push queues

### Installation and Configuration

1\. Clone the repository.

2\. For now we are not released IronMQ v.3 Ruby gem, so, open `Gemfile`
and edit path of `iron_mq` gem like that:

```ruby
gem 'iron_mq', path: '/path/to/iron_mq/v3/repository'
```

Now, run `bundle install`.

3\. Edit `iron.json` and fill right credentials, server address, etc.

4\. Edit `test_engine.json`. Set proper base URL to test server.
Note: base URL is required to build proper subscribers URLs, so, make sure
IronMQ has access to test server through base URL.

### Run tests

Launch test server:

```sh
$ ruby server.rb
```

Run tests:

```sh
$ ruby run_tests.rb
```
