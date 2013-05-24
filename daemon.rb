
class Daemon
	attr_accessor :log_file

	def initialize(pid_file)
		@pid_file = pid_file
		@log_file = "daemon.log"
	end

	# @brief デーモンのプロセスが生きているか確認をする
	# @ret true 生きている
	def alive?
		pid = read_pid
		if pid == -1
			return false
		end
		return alive_pid?(pid)
	end

	# @brief PIDファイルからpidを取得する
	# @ret -1 ファイルが存在しないなどの理由でpidが取れなかった
	def read_pid()
		pid = -1
		begin
			open(@pid_file, 'r') do |f|
				pid = f.read.to_i
			end
		rescue
		end

		return pid
	end

	# @breif PIDファイルにpidを書き込む
	def write_pid(pid)
		begin
			open(@pid_file, 'w') do |f|
				f.write Process.pid
			end
		rescue
		end
	end

	# @brief pidのプロセスが存在するか確認をする
	# @ret true プロセスは存在する
	def alive_pid?(pid)
		ret = 0
		begin
			ret = Process.kill(0, pid)
		rescue
		end

		if ret == 1
			return true
		end

		return false
	end

	# @brief デーモンを開始する
	# @note  すでにデーモンが起動している場合には，新たに実行しない
	# @ret -2 すでに別のデーモンが起動している
	# @ret 0  成功
	def start
		# すでにデーモンが起動しているかどうかのチェック
		if alive?
			return -2
		end

		# 親プロセスを終了してinitプロセスの子プロセスになる
		pid = fork.to_i
		if(pid > 0)
			exit
		elsif(pid < 0)
			puts "can't fork process"
			exit
		end

		# setsidでセッショングループを変更
		Process.setsid

		# 親プロセスを終了して，セッションリーダをなくし，端末のヒモ付をできないようにする
		pid = fork.to_i
		if(pid > 0)
			exit
		elsif(pid < 0)
			puts "can't fork process"
			exit
		end

		# pidファイルを作成
		write_pid(Process.pid)

		# ファイルのマスク値を変更
		File.umask(0)

		@log = File.new(@log_file, "a")

		# デーモンがフォルダのハンドルを保持したままにしないように，/へ移動する
		Dir.chdir("/")

		STDIN.reopen  "/dev/null"
		STDOUT.reopen @log
		STDERR.reopen @log
	end

	def SetLogFd(fd)
		STDIN.reopen  "/dev/null"
		STDOUT.reopen fd
		STDERR.reopen fd
	end

	# @brief デーモンプロセスを終了する
	# @ret -2 終了するデーモンがなかった
	def stop
		if !alive?
			return -2
		end

		pid = read_pid
		Process.kill(9, pid)
	end
end

