
require "socket"
require "thread"
require "resolv"
require "flogger"

BUFFER_SIZE = 10240
DELIMITER   = "\n"

NETWORK_ST_STOP    = 1
NETWORK_ST_RUNNING = 2
NETWORK_ST_CLOSED  = 3

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
			$logger.INFO("connect to server begin")
			server_ip = Resolv.getaddress(@host)

			$logger.DEBUG("connecting to " + @host + ":" + @port.to_s + "(" + server_ip + ")")
			@socket = TCPSocket.open(server_ip, @port)
		rescue => e
			$logger.ERROR(e)
			return false
		end

		@info = NetworkThreadInfo.new(@socket)

		$logger.INFO("connect success")

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
		ret = true
		@info.recv_queue_mutex.synchronize do
			ret = !@info.recv_queue.empty?
		end
		return ret
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
		@shutdown  = false
		@status    = NETWORK_ST_STOP
	end

	def close
		if @status != NETWORK_ST_RUNNING
			$logger.ERROR("server already closed")
			return
		end

		# @FIXME シャットダウンフラグに任せないといけないのは，ケアレスミスのもとだと思う
		@shutdown = true

		# @brief スレッドを止める
		@nlist.each do |info|
			info.shutdown = true
			info.socket.close

			info.send_thread.join
			info.recv_thread.join
		end

		@accept_thread.join
		@server.close

		@status = NETWORK_ST_CLOSED
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

	def accept_thread
		$logger.INFO("starting server")

		@server = TCPServer.open(@port)

		# クライアントの接続を待ち受け
		$logger.INFO("waiting client")

		while true
			# サーバの終了チェック
			if @shutdown
				break
			end

			connected = false

			ret = IO::select([@server], nil, nil, 1)
			if(ret != nil && ret[0].length != 0)
				connected = true
			end

			if !connected
				sleep 0.01
				next
			end

			socket = @server.accept

			$logger.INFO("connecting client")

			# 接続したクライアントのスレッドを生成
			tinfo = NetworkThreadInfo.new(socket)
			if(@onConnect)
				@onConnect.call(tinfo)
			end

			@nlist.push(tinfo)
		end

		$logger.INFO("end server")
	end

	def run()
		@accept_thread = Thread.new { accept_thread }
		@status        = NETWORK_ST_RUNNING
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
		$logger.DEBUG("create SendThread")

		while true
			# メッセージの送信チェック
			while !@info.send_queue.empty?
				packet = nil
				@info.send_queue_mutex.synchronize do
					packet = @info.send_queue.pop()
				end

				$logger.DEBUG(" [send] " + packet.message.slice(0, 20))
				$logger.DEBUG(" [send] size = " + packet.message.length.to_s)

				# デリミタを挿入
				packet.message += DELIMITER

				begin
					ret = @info.socket.write(packet.message)
					$logger.DEBUG(" [send] send size = " + ret.to_s)
				rescue => e
					p e
					break
				end
			end

			sleep 0.01

			if @info.shutdown
				break
			end
		end

		@info.shutdown = true

		$logger.DEBUG("destroy SendThread")
	end
end

class RecvThread
	def initialize(info)
		@info = info
	end

	def run()
		$logger.DEBUG("create RecvThread")

		# 最後に受信してデリミタに達しなかった文字列
		last_message = ""

		while true
			# サーバの終了チェック
			if @info.shutdown
				break
			end

			# メッセージの到着チェック
			recved = false
			begin
				ret = IO::select([@info.socket], nil, nil, 1)
				if(ret != nil && ret[0].length != 0)
					recved = true
				end
			rescue => e
				$logger.ERROR(e)
				break
			end

			# メッセージがない場合は繰り返し
			if !recved
				sleep 0.01
				next
			end

			begin
				buf = @info.socket.recv(BUFFER_SIZE)
			rescue => e
				$logger.ERROR(e)
				break
			end

			# メッセージの長さが0の場合も終了
			if buf.size == 0
				break
			end

			# メッセージを分割する
			message = last_message

			for i in 0..buf.length-1 do
				if buf[i].chr == DELIMITER
					packet = Packet.new
					packet.message = message

					$logger.DEBUG(" [recv] " + packet.message.slice(0, 20))
					$logger.DEBUG(" [recv] size = " + packet.message.length.to_s)

					@info.recv_queue_mutex.synchronize do
						@info.recv_queue.push(packet)
					end

					message = ""
				else
					message += buf[i].chr
				end
			end

			# デリミタに達せずに残った文字列は一旦保存する
			last_message = message
		end

		@info.shutdown = true

		$logger.DEBUG("destroy RecvThread")
	end
end
