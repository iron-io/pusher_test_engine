require './test_engine'

te = TestEngine.new

# Test multicast queues
te.load_and_run_test_file('test_multi.json')

# take a break before next test
sleep 2

# Test unicast queues
te.load_and_run_test_file('test_uni.json')
