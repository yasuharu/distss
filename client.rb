
require "socket"
require "network"
require "flogger"
require 'optparse'
require "setting"

class DistssClient
	def initialize()
		@command_file = nil
	end

	# @brief コマンドファイルを指定．nilだった場合は，標準入力を使用する
	attr_accessor :command_file

	# @brief コマンドの実行結果を表示
	def viewret(ret)
		if ret.retcode != 0
			# 実際のシェルの戻り値は16ビット中の上位8ビットに格納されている
			puts "[error] retcode = %d(command = %s)" % [(ret.retcode >> 8), ret.command]
		end

		r = ret.msg.gsub("<br>", "\n")
		print r
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

		@client = NetworkClient.new($setting.global.host, $setting.global.port)
		if(!@client.connect)
			$logger.ERROR("failed to connect server")
			return
		end
		$logger.PASS

		# プロトコルを解析するレイヤーを初期化
		@player = DistssProtocolLayer.new(@client)
		@player.run()

		$logger.PASS
		while(1)
			if !@batch_mode
				print "> "
				$stdout.flush
			end

			if ((line = @file.gets) == nil)
				break
			end

			if @client.lost?
				$logger.INFO("shutdown client")
				break
			end

			$logger.PASS

			msg = "add " + line
			@player.send(msg)

			$logger.PASS
			# バッチモードじゃない場合は，処理待ちをする
			if !@batch_mode
				while 1
					finished = false
					if (result = @player.get()) != nil
						viewret(result)
						finished = true
					end

					if finished
						break
					end

					sleep 0.01
				end
			end
		end

		# バッチモードの場合は最後に待つ
		if @batch_mode
			finished = false
			while true
				if (result = @player.get()) != nil
					viewret(result)
				end

				if !finished && @player.finished?
					# もう一度@player.getを実行させるために，finishedフラグを使用する
					finished = true
					next
				end

				if finished
					break
				end

				sleep 0.01
			end
		end
	end
end

# @brief コマンドの実行状態を保持する
class CommandStatus
	def initialize(command)
		@command  = command
		@finished = false
	end

	attr_accessor :id
	attr_accessor :command
	attr_accessor :finished
end

# @brief コマンドの実行結果を保持する
class CommandResult
	attr_accessor :id
	attr_accessor :msg
	attr_accessor :command
	attr_accessor :retcode
end

# @brief Distssの低レイヤーの部分を処理する
#        上のレイヤーでは，コマンドの実行やその結果の表示のみを行うようにする
class DistssProtocolLayer
	def initialize(client)
		@client       = client
		@recved_mutex = Mutex.new
		@result_queue = Queue.new

		# IDが未確定のCommandStatusを格納する
		@unknown_id_queue = Queue.new

		# コマンドを実行結果のリスト
		# idからCommandStatusを取得する
		@command_list  = Hash.new
	end

	def run()
		@thread = Thread.new { run_thread }
	end

	# @brief 受信した内容を取得する
	# @ret nil 受信バッファが空の場合
	def get()
		ret = nil
		@recved_mutex.synchronize do
			if !@result_queue.empty?
				ret = @result_queue.pop()
			end
		end
		return ret
	end

	def send(command)
		@client.send(command)

		st = CommandStatus.new(command)
		@unknown_id_queue.push(st)
	end

	def finished?
		if !@unknown_id_queue.empty?
			return false
		end

		@command_list.each do |k,v|
			if !v.finished
				return false
			end
		end

		return true
	end

	# @brief command_listの中身をダンプする
	def dump()
		puts "===== dump ====="
		@command_list.each do |k,v|
			puts "id = %d, status = %s, command = %s" % [v.id, v.finished.to_s, v.command]
		end
		puts "====="
	end

	def run_thread()
		while true
			if @client.lost?
				break
			end

			if @client.recv?
				msg = @client.recv
				$logger.DEBUG(msg)

				# addの返事が返ってきた場合
				if msg =~ /^addr (\d*)$/
					# IDが決定したのでcommand_listへ格納する
					id = $1.to_i

					st = @unknown_id_queue.pop()
					st.id = id

					@command_list[id] = st
				end

				# pingで接続確認が来た場合
				if msg =~ /^ping$/
					@client.send("pong")
				end

				# コマンドの結果を見る
				if msg =~ /^finr (\d*) (.*)$/
					# メインのスレッドに結果を渡す
					@recved_mutex.synchronize do
						id      = $1.to_i
						command = "<unknown>"

						if @command_list.key?(id)
							command = @command_list[id].command
							@command_list[id].finished = true
						else
							$logger.ERROR("command_list is not found")
						end

						ret = CommandResult.new
						ret.id      = id
						ret.msg     = $2
						ret.retcode = 0
						ret.command = command
						@result_queue.push(ret)
					end
				end

				if msg =~ /^errr (\d*) (\d*) (.*)$/
					# メインのスレッドに結果を渡す
					@recved_mutex.synchronize do
						id      = $1.to_i
						command = "<unknown>"

						if @command_list.key?(id)
							command = @command_list[id].command
							@command_list[id].finished = true
						else
							$logger.ERROR("command_list is not found")
						end

						ret = CommandResult.new
						ret.id      = id
						ret.retcode = $2.to_i
						ret.msg     = $3
						ret.command = command
						@result_queue.push(ret)
					end
				end
			end

			sleep 0.01

		end
	end
end

if __FILE__ == $PROGRAM_NAME
	$logger.level = $setting.client.loglevel
	$logger.tag   = "client"

	# デバッグ用に必ずスレッド内での例外を補足する
	Thread.abort_on_exception = true
	client = DistssClient.new

	# 引数の解析
	opt = OptionParser.new
	opt.on("-c CommandFile") { |v| client.command_file = v }
	opt.parse(ARGV)

	client.run()
end

