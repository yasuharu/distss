
require "socket"
require "thread"
require "network.rb"

SERVER_PORT = 20000
BUFFER_SIZE = 1024

class NodeInfo
	attr_accessor :tinfo

	# @brief 認証済みかどうか
	attr_accessor :authed
end

class DistssServer
	attr_accessor :node_list

	def initialize()
		@node_list = Array.new
	end

	def run()
		puts " * starting server"

		@server     = TCPServer.open(SERVER_PORT)
		@controller = Thread.new { ServerControllerThread.new(@node_list).run }

		while true
			# クライアントの接続を待ち受け
			puts " * waiting server"
			socket = @server.accept

			puts " * connecting client"

			# 接続したクライアントのスレッドを生成
			tinfo = NetworkThreadInfo.new(socket)
			ninfo = NodeInfo.new()
			ninfo.tinfo = tinfo

			@node_list.push(ninfo)

#			end
		end

		puts " * end server"
	end
end

class ItemInfo
	# 現在処理中？
	attr_accessor :proceed

	# 実行しているノード
	attr_accessor :processer

	# 実行するコマンド
	attr_accessor :command

	# 実行中のコマンドを判断するためのID
	attr_accessor :id

	def initialize(command, id)
		@command = command
		@proceed = false
		@id      = id
	end
end

class ServerControllerThread
	def initialize(node_list)
		@node_list = node_list
	end

	# @brief IDからitemのインスタンスを探す
	def FindItemById(id)
		ret = nil

		@item_list.each do |item|
			if item.id == id
				return item
			end
		end
	end

	# @brief リクエストの処理
	def reply()
	end

	def run()
		puts " * create ServerControllerThread"

		@item_list  = Array.new
		@wait_queue = Queue.new
		@id_count   = 1

		while true
			@node_list.each do |node|
				while !node.tinfo.recv_queue.empty?
					request = nil
					node.tinfo.recv_queue_mutex.synchronize do
						request = node.tinfo.recv_queue.pop()
					end

					reply = Packet.new
					reply.message = ""

					# 動画の追加
					# request : add <コマンド文字列>
					# reply   : <id>
					if request.message =~ /add (.*)/
						i = ItemInfo.new($1, @id_count)
						@id_count += 1

						@item_list.push(i)
						@wait_queue.push(i)

						reply.message = i.id.to_s
					end

					# 動画の取得
					# request : get
					# reply   : <id> <コマンド文字列>
					if request.message =~ /get/
						if !@wait_queue.empty?
							# waitキューから要素を取得
							item = @wait_queue.pop()

							# 対応するコマンドを送信
							reply.message = item.id.to_s + " " + item.command

							# 必要な情報をセット
							item.proceed   = true
							item.processer = node.tinfo
						end
					end

					# 動画の完了
					# request : fin <id>
					# reply   : ok
					if request.message =~ /fin (.*)/
						id   = $1.to_i
						item = FindItemById(id)

						# 終了したので削除
						@item_list.delete(item)
					end

					# 動画のエラー
					# request : err <id>
					# reply   : ok
					if request.message =~ /err (.*)/
						# エラーの場合は状態を差し戻し
						id   = $1.to_i
						item = FindItemById(id)

						item.proceed = false
						@wait_queue.push(item)
					end

					node.tinfo.send_queue_mutex.synchronize do
						node.tinfo.send_queue.push(reply)
					end
				end
			end
		end

		puts " * end ServerControllerThread"
	end
end

Thread.abort_on_exception = true
server = DistssServer.new()
server.run()

