
require "socket"
require "network.rb"

SERVER_PORT = 20000
SERVER_HOST = "127.0.0.1"
BUFFER_SIZE = 1024

class ExecuterStatus
	attr_accessor :status

	def initialize()
	end
end

class DistssExecuter
	def initialize()
	end

	def run()
		puts " * connect server begin"

		server_ip = IPSocket.getaddress(SERVER_HOST)

		puts " * connecting to " + SERVER_HOST + "(" + server_ip + ")"
		@socket = TCPSocket.open(server_ip, SERVER_PORT)
		@info   = NetworkThreadInfo.new(@socket)

		puts " * connect success"

		while line = STDIN.gets
			# * getでジョブを取ってくる
			#  * OKの場合：そのまま実行
			#  * NGの場合：ジョブがたまるまで待つ
			# * 定期的なpingに応答する
			packet = Packet.new
			packet.message = line

			puts "  * [input] " + packet.message
		end

		while true
			while Recv?
				packet = RecvPacket()
				msg    = Unpack(packet)

				# * メッセージの解析
				if msg =~ /exec (.*)/
				end
			end
		end
	end

	def Recv?
		return @info.recv_queue.empty?
	end

	def RecvPacket
		@info.recv_queue_mutex.synchronize do
			packet = @info.recv_queue.pop()
		end

		return packet
	end

	def SendPacket(packet)
		@info.send_queue_mutex.synchronize do
			@info.send_queue.push(packet)
		end
	end

	def Pack(msg)
		packet = Packet.new
		packet.message = msg
		return packet
	end

	def Unpack(packet)
		return packet.message
	end
end

Thread.abort_on_exception = true
executer = DistssExecuter.new
executer.run()

