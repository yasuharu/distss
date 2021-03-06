
$:.unshift(File.dirname(File.expand_path(__FILE__)))

# @brief コンソールでのログ表示やファイル出力などの高機能ロガー
class FLogger
	def initialize()
		@file   = STDOUT
		@level  = LEVEL_INFO
		@tag    = nil
		@mirror = false
	end

	COLOR_DEFAULT = "\033[39m"
	COLOR_RED     = "\033[31m"
	COLOR_GREEN   = "\033[32m"
	COLOR_YELLOW  = "\033[33m"
	COLOR_BLUE    = "\033[34m"
	TEXT_BOLD     = "\033[1m"

	LEVEL_DEBUG = 1
	LEVEL_INFO  = 2
	LEVEL_WARN  = 3
	LEVEL_ERROR = 4

	attr_accessor :level
	attr_accessor :tag
	attr_accessor :file

	def SetOutput(file)
		@file = open(file, "a")
	end

	# @brief 表示を標準出力にミラーする
	def SetMirrorMode(value)
		@mirror = value
	end

	def DEBUG(msg)
		if LEVEL_DEBUG < @level
			return
		end

		console_output TEXT_BOLD
		console_output COLOR_GREEN
		output(msg, "DEBUG")
		console_output COLOR_DEFAULT
	end

	def INFO(msg)
		if LEVEL_INFO < @level
			return
		end

		console_output TEXT_BOLD
		output(msg, "INFO")
	end

	def WARN(msg)
		if LEVEL_WARN < @level
			return
		end

		console_output TEXT_BOLD
		console_output COLOR_YELLOW
		output(msg, "WARN")
		console_output COLOR_DEFAULT
	end

	def ERROR(msg)
		if LEVEL_ERROR < @level
			return
		end

		console_output TEXT_BOLD
		console_output COLOR_RED
		output(msg, "ERROR")
		console_output COLOR_DEFAULT
	end

	def PASS()
		if LEVEL_DEBUG < @level
			return
		end

		console_output TEXT_BOLD
		console_output COLOR_GREEN
		msg = caller.join(", ")
		output(msg, "PASS")
		console_output COLOR_DEFAULT
	end

	# @brief STDOUT, STDERRが出力先の場合のみ表示をする
	def console_output(msg)
		if STDOUT == @file || STDERR == @file
			print msg
		end

		# ミラー出力の場合
		if STDOUT != @file && @mirror
			STDOUT.write(msg)
		end
	end

	def output(msg, level)
		output = ""

		if @tag
			output = "[%s] [%s] [%s] %s\n" % [level, Time.now.to_s, @tag, msg]
		else
			output = "[%s] [%s] %s\n" % [level, Time.now.to_s, msg]
		end

		@file.write(output)

		# ミラー出力の場合
		if STDOUT != @file && @mirror
			STDOUT.write(output)
			STDOUT.flush
		end

		@file.flush
	end
end

$logger = FLogger.new

