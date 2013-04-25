
require "socket"
require "network.rb"

SERVER_PORT = 20000
SERVER_HOST = "127.0.0.1"

EXECUTER_ST_NONE = 1
EXECUTER_ST_GET_WAIT = 2
EXECUTER_ST_RUNNING = 3

class ExecuterStatus
	attr_accessor :status

	attr_accessor :id

	attr_accessor :command

	attr_accessor :run_thread

	attr_accessor :retmsg

	def initialize()
		@status = EXECUTER_ST_NONE
		@id     = -1
	end
end

class DistssExecuter
	def initialize()
	end

	def run()
		puts " * connect server begin"

		@client = NetworkClient.new(SERVER_HOST, SERVER_PORT)

		@status        = ExecuterStatus.new
		@status.status = EXECUTER_ST_NONE

		if(!@client.connect)
			return
		end

		while true
			if @client.lost?
				puts " * shutdown client"
				break
			end

			if @status.status == EXECUTER_ST_NONE
				@client.send("get")
				@status.status = EXECUTER_ST_GET_WAIT
			end

			if @client.recv?
				msg = @client.recv
				puts msg

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
					puts $1
					id      = $1.to_i
					command = $2

					if @status.status != EXECUTER_ST_GET_WAIT
						puts "[BUG] status is wrong."
					end

					# ジョブがあるか？
					if id != -1
						printf("[info] start %d job(command = %s).\n", id, command)
						@status.status  = EXECUTER_ST_RUNNING
						@status.id      = id
						@status.command = command

						# コマンドを実行する
						@status.run_thread = Thread.new {
							ret = `#{command}`
							@status.retmsg = ret
						}
					else
						puts "[info] no job."
						@status.status = EXECUTER_ST_NONE

						sleep 1
					end
				end
			end

			if EXECUTER_ST_RUNNING == @status.status
				# 終了していれば，finを返す
				if !@status.run_thread.alive?
					# デリミタが\nなので実際の改行コードは\rにする
					msg = @status.retmsg.gsub("\r\n", "")
					msg = msg.gsub("\n", "")

#					p msg

					@client.send("fin " + @status.id.to_s + " " + msg)
					@status.status = EXECUTER_ST_NONE
				end
			end
		end
	end
end

Thread.abort_on_exception = true
executer = DistssExecuter.new
executer.run()

