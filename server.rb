
require "thread"
require "network"

SERVER_PORT = 20000

class NodeInfo
	attr_accessor :tinfo

	# @brief 認証済みかどうか
	attr_accessor :authed
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

class DistssServer
	def initialize()
		@server = NetworkServer.new(SERVER_PORT)
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

	def onConnect(tinfo)
	end

	def run()
		puts " * create ServerControllerThread"

		# サーバのスレッドを開始する
		@server.onConnect = self.method(:onConnect)
		@server_thread = Thread.new { @server.run }
		@node_list     = @server.nlist

		@item_list  = Array.new
		@wait_queue = Queue.new
		@id_count   = 1

		while true
			@node_list.each do |node|
				while @server.recv?(node)
					request = @server.recv(node)
					reply   = "none"

					# 動画の追加
					# request : add <コマンド文字列>
					# reply   : <id>
					if request =~ /add (.*)/
						i = ItemInfo.new($1, @id_count)
						@id_count += 1

						@item_list.push(i)
						@wait_queue.push(i)

						reply = i.id.to_s
					end

					# 動画の取得
					# request : get
					# reply   : <id> <コマンド文字列>
					if request =~ /get/
						if !@wait_queue.empty?
							# waitキューから要素を取得
							item = @wait_queue.pop()

							# 対応するコマンドを送信
							reply = item.id.to_s + " " + item.command

							# 必要な情報をセット
							item.proceed   = true
							item.processer = node
						end
					end

					# 動画の完了
					# request : fin <id>
					# reply   : ok
					if request =~ /fin (.*)/
						id   = $1.to_i
						item = FindItemById(id)

						# 終了したので削除
						@item_list.delete(item)
					end

					# 動画のエラー
					# request : err <id>
					# reply   : ok
					if request =~ /err (.*)/
						# エラーの場合は状態を差し戻し
						id   = $1.to_i
						item = FindItemById(id)

						item.proceed = false
						@wait_queue.push(item)
					end

					@server.send(node, reply)
				end
			end
		end

		puts " * end ServerControllerThread"
	end
end

Thread.abort_on_exception = true

server = DistssServer.new()
server.run()

