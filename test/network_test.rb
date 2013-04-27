
require "thread"
require 'test/unit'
require 'network'
require "flogger"

SERVER_PORT = 20001

class NetworkTest < Test::Unit::TestCase
	def setup
		Thread.abort_on_exception = true

		@server = NetworkServer.new(SERVER_PORT)
		$logger.level = FLogger::LEVEL_DEBUG
		Thread.new { @server.run }
	end

	# 補助用の関数

	def connect
		client = NetworkClient.new("127.0.0.1", SERVER_PORT)
		ret = client.connect

		if true == ret
			return client
		else
			return nil
		end
	end

	def send(client, msg)
		client.send(msg)
	end

	def recv(client)
		while(!client.recv?)
			sleep 0.01
		end
		return client.recv()
	end

	# テスト

	# @brief 通常の接続テスト
	def test_connect()
		client = NetworkClient.new("127.0.0.1", SERVER_PORT)
		ret = client.connect

		assert_equal(ret, true)
	end

#	# @brief localhsotで接続する
#	def test_connect_host()
#		client = NetworkClient.new("localhost", SERVER_PORT)
#		ret = client.connect
#
#		assert_equal(ret, true)
#	end

	# @brief ダメなホスト名で接続する
#	def test_wrong_server()
#		client = NetworkClient.new("www3.yasuharu.net", SERVER_PORT)
#		ret = client.connect
#
#		assert_equal(ret, false)
#
#		client = NetworkClient.new("www100.yasuharu.net", SERVER_PORT)
#		ret = client.connect
#
#		assert_equal(ret, false)
#	end

	# @brief 通常通り接続して，接続を解除する
	def test_disconnect
		@client = connect
		@client.close
	end

	# @brief 1セッションでサーバ側を落とす
	def test_server_disconnect
		client = connect
		assert_not_equal(client, nil)

		@server.close

		client.close
	end

	# @brief 複数のセッションを接続する
	def test_alot_connect
		clients = Array.new
		num     = 10

		for i in 0..num do
			ret = connect
			assert_not_equal(ret, nil)

			clients.push(ret)
		end

		for i in 0..num do
			client = clients[i]
			if client != nil
				client.close
			end
		end
	end

	# @brief 複数のセッションを接続して，サーバ側を落とす
	def test_alot_server_disconnect
		clients = Array.new
		num     = 10

		for i in 0..num do
			ret = connect
			assert_not_equal(ret, nil)

			clients.push(ret)
		end

		@server.close

		for i in 0..num do
			client = clients[i]
			if client != nil
				client.close
			end
		end
	end

	# @brief 連続でメッセージを送ってみる
	def test_send_message
		clients = Array.new
		num     = 3

		for i in 0..num do
			ret = connect
			assert_not_equal(ret, nil)

			clients.push(ret)
		end

		for j in 0..200 do
			for i in 0..num do
				client = clients[i]
				if client != nil
					client.send("hogehoge")
				end
			end
		end

		sleep 3
	end

	def teardown
		puts " * server close"
		@server.close
	end
end

