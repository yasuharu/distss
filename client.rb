
require "socket"
require "network"

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

		while line = STDIN.gets
			if @client.lost?
				puts " * shutdown client"
				break
			end

			@client.send(line)

			puts "  * [input] " + line

			while(!@client.recv?)
			end

			msg = @client.recv
			puts msg

			# pingで接続確認が来た場合
			if msg =~ /ping/
#				@client.send("pong")
			end
		end
	end
end

Thread.abort_on_exception = true
client = DistssClient.new
client.run()

