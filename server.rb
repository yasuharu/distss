
require "thread"
require "network"

SERVER_PORT = 20000

CLIENT_CHECK_TIME       = 5
CLIENT_CHECK_RETRY_TIME = 1
CLIENT_TIMEOUT          = 30

ITEM_CHECK_TIME       = 1
ITEM_CHECK_RETRY_TIME = 1
ITEM_TIMEOUT          = 30

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
	attr_accessor :percentage

	# @brief 実行要求を出したノード
	attr_accessor :requester

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

		return ret
	end

	def DumpItem()
		$logger.DEBUG("----- dump -----")
		@item_list.each do |item|
			$logger.DEBUG("id = %d, command = %s, st = %s, percentage = %d" %
				[item.id.to_s, item.command, item.proceed.to_s, item.percentage])
		end
		$logger.DEBUG("-----")
	end

	def DumpNode()
		id = 0
		$logger.DEBUG("----- node -----")
		@node_list.each do |node|
			$logger.DEBUG("id = %d, last_alive_time = %s" % [id, node.private.last_alive_time.to_s])
			id += 1
		end
		$logger.DEBUG("-----")
	end

	def onConnect(tinfo)
		# @FIXME ノード情報をprivateにしないといけないのはどうにかしたい
		tinfo.private                  = NodeInfo.new
		tinfo.private.authed           = false
		tinfo.private.last_alive_time  = Time.now
		tinfo.private.alive_check_time = Time.now
	end

	def run()
		$logger.INFO("create ServerControllerThread")

		# サーバのスレッドを開始する
		@server.onConnect = self.method(:onConnect)
		@server.run

		# @FIXME nlistをロックせずに読み書きしており，確率がかなり低いものの厄介な不具合を起こす可能性が高い
		@node_list  = @server.nlist

		@item_list  = Array.new
		@wait_queue = Queue.new
		@id_count   = 1

		@last_dump_time = Time.now
		while true
			@node_list.each do |node|
				while @server.recv?(node)
					# 最終応答時間を修正
					node.private.last_alive_time = Time.now

					request = @server.recv(node)
					reply   = nil

					$logger.DEBUG(" [request] " + request.slice(0, 20))

					# 動画の追加
					# request : add <コマンド文字列>
					# reply   : addr <id>
					if request =~ /^add (.*)$/
						i           = ItemInfo.new($1, @id_count)
						i.requester = node

						@id_count += 1

						@item_list.push(i)
						@wait_queue.push(i)

						reply = i.id.to_s
					end

					# 動画の取得
					# request : get
					# reply(コマンドがある場合) : getr <id> <コマンド文字列>
					# reply(コマンドがない場合) : getr -1 none
					if request =~ /^get/
						reply = "getr "
						if !@wait_queue.empty?
							# waitキューから要素を取得
							item = @wait_queue.pop()

							# 対応するコマンドを送信
							reply += item.id.to_s + " " + item.command

							# 必要な情報をセット
							item.proceed          = true
							item.processer        = node
							item.last_status_time = Time.now
						else
							reply += "-1 none"
						end
					end

					# 動画の完了
					# request : fin <id> <出力メッセージ>
					# reply   : finr
					if request =~ /^fin (\d*) (.*)$/m
						id     = $1.to_i
						item   = FindItemById(id)
						result = $2

						reply = ""

						if nil == item
							$logger.ERROR("wrong job id")
							next
						end

						if item.processer != node
							$logger.ERROR("another node send finished")
							reply = "finr -1"
						else
							# item.processer == node でかつ，item.proceed == false の場合は，
							# タイムアウトしてしまったけど，処理結果を返してきている
							if item.proceed == false
								$logger.ERROR("already timeout")
								reply = "finr -1"
							else
								# 終了したので削除
								@item_list.delete(item)
								$logger.INFO("%d job is finished" % id)
								reply = "finr " + id.to_s

								# 要求を出したノードに返事を返す
								@server.send(item.requester, "finr " + result)
							end
						end

						# DumpItem()
					end

					# 動画のエラー
					# request : err <id>
					# reply   : errr
					if request =~ /^err (.*)/
						# エラーの場合は状態を差し戻し
						id    = $1.to_i
						item  = FindItemById(id)
						reply = "errr"

						# @FIXME これ忘れていたらアウト？
						#        ケアレスミスを減らすためのロジックを考える
						if nil == item
							$logger.ERROR("wrong job id")
							next
						end

						item.proceed = false
						@wait_queue.push(item)
					end

					# ***** クライアントからの返事関係のメッセージ *****

					if request =~ /pong/
						# すでに last_alive_time は更新されているので特に何もしない
					end

					# ステータス確認
					# request : status <id>
					# reply   : statusr <id> <percentage>
					if request =~ /^statusr (.*) (.*)/
						id         = $1.to_i
						percentage = $2.to_i
						item       = FindItemById(id)

						if item == nil
							$logger.WARN("invalid statusr")
						else
							item.last_status_time = Time.now
							item.percentage       = percentage
						end
					end

					if reply != nil
						@server.send(node, reply)
					end
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
					$logger.WARN(" ****** connection timeout *****")
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
					if (Time.now - item.status_check_time) > ITEM_CHECK_RETRY_TIME
						msg = "status " + item.id.to_s
						item.status_check_time = Time.now

						@server.send(item.processer, msg)
					end
				end

				# 一定時間以上返事を返していない場合，アプリケーションが落ちたと判断する
				# （ただし，ノード自体が落ちたとは判断をしない．ノードはpingの時間から判定をする）
				if (Time.now - item.last_status_time) > ITEM_TIMEOUT
					item.proceed = false
					@wait_queue.push(item)

					$logger.WARN("item timeout " + item.id)
				end
			end

			if (Time.now - @last_dump_time) > 1
				@last_dump_time = Time.now
				DumpItem()
				DumpNode()
			end
		end

		$logger.INFO("end ServerControllerThread")
	end
end

$logger.level = FLogger::LEVEL_DEBUG
Thread.abort_on_exception = true

server = DistssServer.new()
server.run()

