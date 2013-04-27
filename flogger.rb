
# @brief „Éï„Ç©„Éº„Éû„ÉÉ„Éà‰ªò„Åç„ÅÆ„É≠„Ç¨„Éº
class FLogger
	def initialize()
		@file  = STDOUT
		@level = LEVEL_INFO
		@tag   = nil
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

	def SetOutput(file)
		@file = open(file, "a")
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

	# @brief STDOUT, STDERRÇ™èoóÕêÊÇÃèÍçáÇÃÇ›ï\é¶ÇÇ∑ÇÈ
	def console_output(msg)
		if STDOUT == @file || STDERR == @file
			print msg
		end
	end

	def output(msg, level)
		if @tag
			@file.write("[%s] [%s] %s\n" % [level, @tag, msg])
		else
			@file.write("[%s] %s\n" % [level, msg])
		end
	end
end

$logger = FLogger.new

