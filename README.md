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

* `test_uni.json` - contains tests for unicast push queues

### Installation and Configuration

1\. Clone the repository.

2\. Run `bundle install` (or `bundle update` if you have updated to newer version).

3\. Edit `iron.json` and fill right credentials, server address, etc.

4\. Edit `test_engine.json`. Set proper base URL to test server.
Note: base URL is required to build proper subscribers URLs, so, make sure
IronMQ has access to test server through base URL.

### Run tests

Launch test server:

```sh
$ bundle exec ruby server.rb
```

Run tests:

```sh
$ bundle exec ruby run_tests.rb
```

### Architectural documentation

See on [Google Drive](https://docs.google.com/a/iron.io/document/d/1EZnvm-dJQlid9vv7QaDp6Ajo29sQyYnsI6bqEToOnY8).

### Troubleshooting

If you see errors while running tests:

* Test engine or/and server crash (Ruby exceptions or so) -- contact me.

* Some existing test cases are randomly failed: open file `test_engine.rb`, go to line 315.
(See it on GitHub)[https://github.com/iron-io/pusher_test_engine/blob/master/test_engine.rb#L315].
Set higher sleep interval (see comment in the code for more information).

* Subscribers with `HTTP 202` response code are consistently failed. Check your IronMQ configuration.
Make sure `host` configuration option is set properly
and test server is able access IronMQ instance with this address / host name.
