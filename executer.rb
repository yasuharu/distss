
$:.unshift(File.dirname(File.expand_path(__FILE__)))

require "socket"
require "network"
require "flogger"
require "setting"
require 'optparse'
require "daemon"

EXECUTER_ST_NONE     = 1
EXECUTER_ST_GET_WAIT = 2
EXECUTER_ST_RUNNING  = 3

PID_FILE = "executer.pid"

class ExecuterStatus
	attr_accessor :status

	attr_accessor :id

	attr_accessor :command

	attr_accessor :run_thread

	attr_accessor :retmsg

	attr_accessor :retcode

	def initialize()
		@status = EXECUTER_ST_NONE
		@id     = -1
	end
end

class DistssExecuter
	def initialize()
	end

	def run()
		$logger.INFO("connect server begin")

		@client = NetworkClient.new($setting.global.host, $setting.global.port)

		@status        = ExecuterStatus.new
		@status.status = EXECUTER_ST_NONE

		if(!@client.connect)
			return
		end

		while true
			if @client.lost?
				$logger.INFO("shutdown client")
				break
			end

			if @status.status == EXECUTER_ST_NONE
				@client.send("get")
				@status.status = EXECUTER_ST_GET_WAIT
			end

			if @client.recv?
				msg = @client.recv
				$logger.DEBUG(msg)

				# pingで接続確認が来た場合
				if msg =~ /^ping$/
					@client.send("pong")
				end

				if msg =~ /^status (.*)/
					# finのタイミングと入れちがうことがあるため，スレッドの状態をチェックする
					# もし，終了している場合には無視しても問題ない
#					if @status.run_thread.alive?
						@client.send("statusr " + @status.id.to_s + " 100")
#					end
				end

				# getの返事が返ってきた？
				if msg =~ /^getr (-?\d*) (.*)$/
					$logger.DEBUG($1)
					id      = $1.to_i
					command = $2

					if @status.status != EXECUTER_ST_GET_WAIT
						$logger.ERROR(" [BUG] status is wrong")
					end

					# ジョブがあるか？
					if id != -1
						$logger.INFO("start %d job(command = %s)" % [id, command])
						@status.status  = EXECUTER_ST_RUNNING
						@status.id      = id
						@status.command = command

						# コマンドを実行する
						@status.run_thread = Thread.new {
							ret = ""

							begin
								ret = `#{command}`
							rescue => e
								ret = e
							end

							@status.retcode = $?
							@status.retmsg  = ret.to_s
						}
					else
						$logger.DEBUG("no job")
						@status.status = EXECUTER_ST_NONE

						sleep 1
					end
				end
			end

			if EXECUTER_ST_RUNNING == @status.status
				# 終了していれば，finを返す
				if !@status.run_thread.alive?
					# デリミタが\nなので実際の改行コードは\rにする
					msg = @status.retmsg.gsub(/(\r\n|\r|\n)/, '<br>')

					if @status.retcode == 0
						@client.send("fin " + @status.id.to_s + " " + msg)
					else
						@client.send("err %d %d %s" % [@status.id, @status.retcode, msg])
					end

					@status.status = EXECUTER_ST_NONE
				end
			end

			sleep 0.01
		end
	end
end

if __FILE__ == $PROGRAM_NAME
	$logger.level = $setting.executer.loglevel
	$logger.tag   = "executer"

	# デバッグ用に必ずスレッド内での例外を補足する
	Thread.abort_on_exception = true

	# 引数の解析
	daemon_opt = ""
	opt = OptionParser.new
	opt.on("--start") { |v| daemon_opt = "start" }
	opt.on("--stop")  { |v| daemon_opt = "stop"  }
	opt.parse(ARGV)

	# サーバの制御
	daemon = Daemon.new(PID_FILE)
	if daemon_opt == "start"
		if daemon.start == -2
			puts "[ERROR] executer already running."
			exit 1
		else
			puts "[INFO] running as daemon."
		end
	elsif daemon_opt == "stop"
		if daemon.stop == -2
			puts "[ERROR] executer not running."
			exit 1
		else
			puts "[INFO] executer stop."
		end

		exit 0
	end

	executer = DistssExecuter.new
	executer.run()
end

