
require "socket"
require "thread"

BUFFER_SIZE = 1024

# @brief 送受信単位のデータを格納する
class Packet
	attr_accessor :message
end

class NetworkClient
	def initialize(host, port)
		@host = host
		@port = port
	end

	# @brief 接続を開始する
	# @ret true  成功
	# @ret false 失敗
	def connect
		begin
			puts " * connect server begin"
			server_ip = IPSocket.getaddress(@host)

			puts " * connecting to " + @host + "(" + server_ip + ")"
			@socket = TCPSocket.open(server_ip, @port)
		rescue => e
			p e
			return false
		end

		@info = NetworkThreadInfo.new(@socket)

		puts " * connect success"

		return true
	end

	def send(msg)
		packet         = Packet.new
		packet.message = msg

		@info.send_queue_mutex.synchronize do
			@info.send_queue.push(packet)
		end
	end

	# @ret true 受信可能
	def recv?
		return !@info.recv_queue.empty?
	end

	def recv
		packet = nil
		@info.recv_queue_mutex.synchronize do
			packet = @info.recv_queue.pop()
		end
		return packet.message
	end

	def close
		# @brief スレッドを止める
		@info.shutdown = true
		@info.socket.close
		@info.send_thread.join
		@info.recv_thread.join
	end

	# @FIXME 名前は変えたほうが良いかも．．．
	def lost?
		return @info.shutdown
	end
end

class NetworkServer
	attr_accessor :nlist

	# @brief 接続時のコールバック関数
	attr_accessor :onConnect

	def initialize(port)
		@nlist     = Array.new
		@port      = port
		@onConnect = nil
	end

	def close
		# @brief スレッドを止める
		@nlist.each do |info|
			info.shutdown = true
			info.socket.close

			info.send_thread.join
			info.recv_thread.join
		end
	end

	def disconnect(info)
		info.shutdown = true
		info.socket.close

		info.send_thread.join
		info.recv_thread.join

		@nlist.delete(info)
	end

	def send(node, msg)
		packet         = Packet.new
		packet.message = msg

		node.send_queue_mutex.synchronize do
			node.send_queue.push(packet)
		end
	end

	def recv?(node)
		return !node.recv_queue.empty?
	end

	def recv(node)
		packet = nil

		node.recv_queue_mutex.synchronize do
			packet = node.recv_queue.pop()
		end

		return packet.message
	end

	def run()
		puts " * starting server"

		@server = TCPServer.open(@port)

		while true
			# クライアントの接続を待ち受け
			puts " * waiting server"
			socket = @server.accept

			puts " * connecting client"

			# 接続したクライアントのスレッドを生成
			tinfo = NetworkThreadInfo.new(socket)
			if(@onConnect)
				@onConnect.call(tinfo)
			end

			@nlist.push(tinfo)

#			end
		end

		puts " * end server"
	end
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

	# @brief 終了時のフラグ
	attr_accessor :shutdown

	# @brief スレッドに付随する情報を保持する
	attr_accessor :private

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
			# サーバの終了チェック
			if @info.shutdown
				break
			end

			# メッセージの到着チェック
			recved = false
			begin
				ret = IO::select([@info.socket])
				if(ret[0].length != 0)
					recved = true
				end
			rescue => e
				p e
				break
			end

			# メッセージがない場合は繰り返し
			if !recved
				next
			end

			begin
				buf = @info.socket.recv(BUFFER_SIZE)
			rescue => e
				p e
				break
			end

			# メッセージの長さが0の場合も終了
			if buf.size == 0
				break
			end

			packet = Packet.new
			packet.message = buf

			puts "  * [recv] " + packet.message

			@info.recv_queue_mutex.synchronize do
				@info.recv_queue.push(packet)
			end
		end

		@info.shutdown = true

		puts " * destroy RecvThread"
	end
end
