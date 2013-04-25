
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
			return
		end

		@thread = Thread.new{ recv_thread() }

		while line = STDIN.gets
			if @client.lost?
				puts " * shutdown client"
				break
			end

			@client.send(line)
		end
	end

	def recv_thread()
		while true
			if @client.lost?
				break
			end

			while(!@client.recv?)
			end

			msg = @client.recv
			puts msg

			# pingで接続確認が来た場合
			if msg =~ /^ping$/
				@client.send("pong")
			end
		end
	end
end

$logger = FLogger.new
$logger.level = FLogger::LEVEL_ERROR
# $logger.SetOutput("client.rb")
$logger.INFO("info")
$logger.ERROR("error")
$logger.WARN("warn")
$logger.DEBUG("debug")
Thread.abort_on_exception = true
client = DistssClient.new
client.run()

