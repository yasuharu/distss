
require "thread"
require "network"

SERVER_PORT = 20000
CLIENT_CHECK_TIME = 3
CLIENT_CHECK_RETRY_TIME = 1
CLIENT_TIMEOUT    = 5

class NodeInfo
	attr_accessor :tinfo

	# @brief 認証済みかどうか
	attr_accessor :authed

	# @brief 最終応答確認時刻
	attr_accessor :last_alive

	# @brief 
	attr_accessor :ping_check_time
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
		tinfo.private            = NodeInfo.new
		tinfo.private.authed     = false
		tinfo.private.last_alive = Time.now
		tinfo.private.ping_check_time = Time.now
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
					# 最終応答時間を修正
					node.private.last_alive = Time.now

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

				# クライアントが一定時間通信のない場合 ping を送信
				if (Time.now - node.private.last_alive) > CLIENT_CHECK_TIME
					# 最後に ping を送った時から一定時間後に再送信
					if (Time.now - node.private.ping_check_time) > CLIENT_CHECK_RETRY_TIME
						node.private.ping_check_time = Time.now
						@server.send(node, "ping")
					end
				end

				# クライアントの接続がタイムアウトした場合
				if (Time.now - node.private.last_alive) > CLIENT_TIMEOUT
					@server.close(node)
				end
			end
		end

		puts " * end ServerControllerThread"
	end
end

Thread.abort_on_exception = true

server = DistssServer.new()
server.run()

