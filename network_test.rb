
require "thread"
require 'test/unit'
require 'network'

SERVER_PORT = 20001

class NetworkTest < Test::Unit::TestCase
	def setup
		@server = NetworkServer.new(SERVER_PORT)
		Thread.new { @server.run }

	end

	def test_connect()
		@client = NetworkClient.new("127.0.0.1", SERVER_PORT)
		ret = @client.connect

		assert_equal(ret, true)
	end

	# @brief localhsotで接続する
	def test_connect_host()
	end

	def teardown
	end
end

