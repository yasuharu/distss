
require "socket"
require "network"
require "flogger"
require 'optparse'

SERVER_PORT = 20000
SERVER_HOST = "127.0.0.1"

class DistssClient
	def initialize()
		@command_file = nil
	end

	def run()
		# バッチモードの判定
		@batch_mode = false
		@file       = STDIN
		if @command_file != nil
			@batch_mode = true
			begin
				@file = open(@command_file, "r")
			rescue
				$logger.ERROR("can't open command file(file = %s)." % @command_file)
				return
			end
		end

		@client = NetworkClient.new(SERVER_HOST, SERVER_PORT)
		if(!@client.connect)
			$logger.ERROR("failed to connect server")
			return
		end

		@thread       = Thread.new{ recv_thread() }
		@recved_mutex = Mutex.new
		@result_queue = Queue.new

		# 送信した回数と受信する回数は一致することが保証される
		# ただし，pingとかは除く
		@send_count = 0

		while (line = @file.gets)
			if @client.lost?
				$logger.INFO("shutdown client")
				break
			end

			@client.send(line)
			@send_count += 1

			# バッチモードじゃない場合は，処理待ちをする
			if !@batch_mode
				while 1
					finished = false
					@recved_mutex.synchronize do
						if !@result_queue.empty?
							result = @result_queue.pop()
							r = result.gsub("<br>", "\n")
							print r
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

		# バッチモードの場合は最後に待つ
		@recved_count = 0
		if @batch_mode
			while @send_count > @recved_count
				while 1
					@recved_mutex.synchronize do
						if !@result_queue.empty?
							result = @result_queue.pop()
							r = result.gsub("<br>", "\n")
							print r
							@recved_count += 1
						end
					end

					sleep 0.01
				end
			end
		end
	end

	attr_accessor :recved_mutex

	# @brief コマンドファイルを指定．nilだった場合は，標準入力を使用する
	attr_accessor :command_file

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
					@result_queue.push($1)
				end
			end
		end
	end
end

$logger.level = FLogger::LEVEL_ERROR
$logger.tag   = "client"

Thread.abort_on_exception = true

client = DistssClient.new

# 引数の解析
opt = OptionParser.new
opt.on("-c CommandFile") { |v| client.command_file = v }
opt.parse(ARGV)

client.run()

