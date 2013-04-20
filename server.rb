
require "thread"
require "network"

SERVER_PORT = 20000
CLIENT_CHECK_TIME = 3
CLIENT_CHECK_RETRY_TIME = 1
CLIENT_TIMEOUT    = 5

ITEM_CHECK_TIME = 1
ITEM_CHECK_RETRY_TIME = 1

class NodeInfo
	attr_accessor :tinfo

	# @brief 認証済みかどうか
	attr_accessor :authed

	# @brief 最終応答確認時刻
	attr_accessor :last_alive_time

	# @brief 最後にpingを実行した時間
	#        (あくまでも，実行した時間なので，返事が返ってきた時間ではない)
	attr_accessor :alive_check_time
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

	# 最後にステータスをチェックした時間
	attr_accessor :last_status_time

	# 最後にステータスチェックのリクエストを送った時間
	attr_accessor :status_check_time

	# 現在の状況(0 - 100のパーセント値)
	attr_accessor :status

	def initialize(command, id)
		@command = command
		@proceed = false
		@id      = id
		@last_status_time = Time.now
		@status_check_time = Time.now
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

	def DumpItem()
		puts "----- dump -----"
		@item_list.each do |item|
			printf("id = %d, command = %s, st = %d\n",
				item.id, item.command, item.proceed)
		end
		puts "-----"
	end

	def onConnect(tinfo)
		tinfo.private            = NodeInfo.new
		tinfo.private.authed     = false
		tinfo.private.last_alive_time = Time.now
		tinfo.private.alive_check_time = Time.now
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
					node.private.last_alive_time = Time.now

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

						if item.processer != node
							puts "[error] another node send finished."
						else
							# 終了したので削除
							@item_list.delete(item)
						end
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
				if (Time.now - node.private.last_alive_time) > CLIENT_CHECK_TIME
					# 最後に ping を送った時から一定時間後に再送信
					if (Time.now - node.private.alive_check_time) > CLIENT_CHECK_RETRY_TIME
						node.private.alive_check_time = Time.now
						@server.send(node, "ping")
					end
				end

				# クライアントの接続がタイムアウトした場合
				if (Time.now - node.private.last_alive_time) > CLIENT_TIMEOUT
					@server.disconnect(node)
				end
			end

			# アイテムの状態をチェックする
			@item_list.each do |item|
				# 実行中か？
				if item.proceed == false
					next
				end

				# 実行中の場合は一定期間ごとにステータスを求める
				if (Time.now - item.last_status_time) > ITEM_CHECK_TIME
					if (Time.now - item.last_status_time) > ITEM_CHECK_RETRY_TIME
						msg = "status " + item.id.to_s
						item.last_status_time = Time.now

						@server.send(item.processer, msg)
					end
				end

				# 一定時間以上返事を返していない場合，アプリケーションが落ちたと判断する
				# （ただし，ノード自体が落ちたとは判断をしない．ノードはpingの時間から判定をする）
				if (Time.now - item.last_status_time) > ITEM_TIMEOUT
					item.proceed = false
					@wait_queue.push(item)
				end
			end
		end

		puts " * end ServerControllerThread"
	end
end

Thread.abort_on_exception = true

server = DistssServer.new()
server.run()

