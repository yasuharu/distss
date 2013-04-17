
require "socket"
require "network.rb"

SERVER_PORT = 20000
SERVER_HOST = "127.0.0.1"
BUFFER_SIZE = 1024

class DistssClient
	attr_accessor :node_list

	def initialize()
	end

	def run()
		puts " * connect server begin"

		@socket = TCPSocket.open(SERVER_HOST, SERVER_PORT)
		@info   = NetworkThreadInfo.new(@socket)

		puts " * connect success"

		while line = STDIN.gets
			packet = Packet.new
			packet.message = line

			puts "  * [input] " + packet.message

			@info.send_queue_mutex.synchronize do
				@info.send_queue.push(packet)
			end

			while @info.recv_queue.empty?
			end

			@info.recv_queue_mutex.synchronize do
				packet = @info.recv_queue.pop()
				puts packet.message
			end
		end
	end
end

Thread.abort_on_exception = true
client = DistssClient.new
client.run()

