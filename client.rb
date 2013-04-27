
require "socket"
require "network"
require "flogger"

SERVER_PORT = 20000
SERVER_HOST = "127.0.0.1"

class DistssClient
	def initialize()
	end

	def run()
		@client = NetworkClient.new(SERVER_HOST, SERVER_PORT)
		if(!@client.connect)
			$logger.ERROR("failed to connect server")
			return
		end

		@thread = Thread.new{ recv_thread() }
		@recved_mutex = Mutex.new

		while (line = STDIN.gets)
			if @client.lost?
				$logger.INFO("shutdown client")
				break
			end

			@client.send(line)

			while 1
				finished = false
				@recved_mutex.synchronize do
					if @recved
						r = @result.gsub("<br>", "\n")
						print r
						@recved = false
						finished = true
					end
				end

				if finished
					break
				end

				sleep 0.01
			end
		end
	end

	attr_accessor :recved, :result
	attr_accessor :recved_mutex

	def recv_thread()
		while true
			if @client.lost?
				break
			end

			while(!@client.recv?)
			end

			msg = @client.recv
			$logger.INFO(msg)

			# pingで接続確認が来た場合
			if msg =~ /^ping$/
				@client.send("pong")
			end

			# コマンドの結果を見る
			if msg =~ /^finr (.*)$/
				# メインのスレッドに結果を渡す
				@recved_mutex.synchronize do
					@recved = true
					@result = $1
				end
			end
		end
	end
end

$logger.level = FLogger::LEVEL_ERROR
$logger.tag   = "client"
Thread.abort_on_exception = true

client = DistssClient.new
client.run()

