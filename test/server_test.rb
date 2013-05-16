
$:.unshift(File.dirname(File.expand_path(__FILE__)))
$:.unshift(File.dirname(File.expand_path(__FILE__)) + "/../")

require "thread"
require 'test/unit'
require 'network'
require "flogger"
require "server"
require "setting"

class ServerTest < Test::Unit::TestCase
	def setup
		Thread.abort_on_exception = true
		$logger.level = FLogger::LEVEL_DEBUG

		system "ruby server.rb --start"
		sleep 0.1

		# 意図的にconnectしておいて，サーバ側には複数のノードがあるように振る舞う
		connect()
		connect()
		connect()
	end

	# 補助用の関数

	def connect
		client = NetworkClient.new($setting.global.host, $setting.global.port)
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
		assert_not_equal(client, nil)

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
		assert_equal("addr 1", ret)

		client.send("add fuga")
		ret = recv(client)
		assert_equal("addr 2", ret)

		client.send("add piyo")
		ret = recv(client)
		assert_equal("addr 3", ret)

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
		assert_equal("addr 1", recv(client))

		client.send("get")
		assert_equal("getr 1 hoge", recv(client))
	end

	def test_protocol_fin
		client = connect()

		client.send("add hoge")
		assert_equal("addr 1", recv(client))

		client.send("get")

		# @FIXME 受信タイミングによって結果がおかしくなる
		assert_equal("getr 1 hoge", recv(client))

		client.send("fin 1 fuga")

		# 自分自身がリクエストを出したので，結果の文字列も帰ってくる
		# その文字列はfinrより先に帰ってくる
		assert_equal("finr 1 fuga", recv(client))
		assert_equal("finr 1", recv(client))

		client.send("get")
		assert_equal("getr -1 none", recv(client))
	end

	def test_protocol_err
		client = connect()

		client.send("add hoge")
		assert_equal("addr 1", recv(client))

		client.send("get")
		assert_equal("getr 1 hoge", recv(client))
	end

	def test_protocol_ping
		client = connect()

		total = 0

		sleep $setting.server.client_check_time
		assert_equal("ping", recv(client))

		# すぐに返事を返して，タイムアウトしないか？
		client.send("pong")
		while client.recv?
			msg = client.recv
			if !(msg == "ping" || msg == "none")
				assert(false)
			end
		end

		sleep ($setting.server.client_check_time * $setting.server.client_check_retry + 1)

		# もし「add」の返事が返ってきていれば，タイムアウトしていないことになる
		client.send("add hoge")

		while client.recv?
			if client.recv() == "addr 1"
				assert(false)
			end
		end
	end

	def teardown
		puts " * server close"

		system "ruby server.rb --stop"
	end
end

