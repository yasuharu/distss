
require "thread"

# @brief 送受信単位のデータを格納する
class Packet
	attr_accessor :message
end

class NetworkThreadInfo
	attr_accessor :socket

	attr_accessor :send_thread

	# @brief Packet型の変数を入れる
	attr_accessor :send_queue
	attr_accessor :send_queue_mutex

	attr_accessor :recv_thread
	attr_accessor :recv_queue
	attr_accessor :recv_queue_mutex

	# 終了時のフラグ
	attr_accessor :shutdown

	def initialize(socket)
		@socket     = socket

		@send_queue = Queue.new
		@recv_queue = Queue.new
		@shutdown   = false

		@send_queue_mutex = Mutex.new
		@recv_queue_mutex = Mutex.new

		@send_thread = Thread.new { SendThread.new(self).run }
		@recv_thread = Thread.new { RecvThread.new(self).run }
	end

	def GetName()
		return "server"
	end
end

class SendThread
	def initialize(info)
		@info = info
	end

	def run()
		puts " * create SendThread"

		while true
			# メッセージの送信チェック
			while !@info.send_queue.empty?
				packet = nil
				@info.send_queue_mutex.synchronize do
					packet = @info.send_queue.pop()
				end

				puts "  * [send] " + packet.message

				begin
					@info.socket.write(packet.message)
				rescue => e
					p e
					break
				end
			end

			if @info.shutdown
				break
			end
		end

		@info.shutdown = true

		puts " * destroy SendThread"
	end
end

class RecvThread
	def initialize(info)
		@info = info
	end

	def run()
		puts " * create RecvThread"

		while true
			# メッセージの到着チェック
			# select(info.socket).each do |socket|
				begin
					buf = @info.socket.recv(BUFFER_SIZE)
				rescue => e
					p e
					break
				end

				packet = Packet.new
				packet.message = buf

				puts "  * [recv] " + packet.message

				@info.recv_queue_mutex.synchronize do
					@info.recv_queue.push(packet)
				end
			# end

			# サーバの終了チェック
			if @info.shutdown
				break
			end
		end

		@info.shutdown = true

		puts " * destroy RecvThread"
	end
end
