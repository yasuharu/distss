
require "thread"
require 'test/unit'
require 'network'
require "flogger"
require "server"

SERVER_PORT = 20001

CLIENT_CHECK_TIME       = 1
CLIENT_CHECK_RETRY_TIME = 1
CLIENT_TIMEOUT          = 2

class NetworkTest < Test::Unit::TestCase
	def setup
		Thread.abort_on_exception = true

		@server = DistssServer.new()
		@server_thread = Thread.new { @server.run }

		$logger.level = FLogger::LEVEL_DEBUG

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

	# @brief メッセージのエコーテスト
	def test_send_recv_message
		client = connect()

		send(client, "echo hoge")
		send(client, "echo hoge")
		send(client, "echo hoge")
		ret = recv(client)
		assert_equal("hoge", ret)
	end

	def test_protocol_add
		client = connect()

		# add
		client.send("add hoge")
		ret = recv(client)
		assert_equal("1", ret)

		client.send("add fuga")
		ret = recv(client)
		assert_equal("2", ret)

		client.send("add piyo")
		ret = recv(client)
		assert_equal("3", ret)

		client.send("add")
		ret = recv(client)
		assert_equal("none", ret)
	end
	def test_protocol_add2
		client = connect()
	end

	def test_protocol_get
		client = connect()

		client.send("get")
		assert_equal("getr -1 none", recv(client))

		client.send("add hoge")
		assert_equal("1", recv(client))

		client.send("get")
		assert_equal("getr 1 hoge", recv(client))
	end

	def test_protocol_fin
		client = connect()

		client.send("add hoge")
		assert_equal("1", recv(client))

		client.send("get")
		assert_equal("getr 1 hoge", recv(client))

		client.send("fin 1 fuga")

		# 自分自身がリクエストを出したので，結果の文字列も帰ってくる
		# その文字列はfinrより先に帰ってくる
		assert_equal("finr fuga", recv(client))
		assert_equal("finr 1", recv(client))

		client.send("get")
		assert_equal("getr -1 none", recv(client))
	end

	def test_protocol_err
		client = connect()

		client.send("add hoge")
		assert_equal("1", recv(client))

		client.send("get")
		assert_equal("getr 1 hoge", recv(client))
	end

	def test_protocol_ping
		client = connect()

		total = 0

		while total < CLIENT_TIMEOUT + 1
			sleep CLIENT_CHECK_TIME
			total += CLIENT_CHECK_TIME

			assert_equal("ping", recv(client))

			# すぐに返事を返して，タイムアウトしないか？
			client.send("pong")
			assert_equal("none", recv(client))
		end
	end

	def test_protocol_status
		client = connect()
	end

	def test_item_timeout
	end

	def test_client_timeout
	end

	def teardown
		puts " * server close"
		@server.close
		@server_thread.join
	end
end

