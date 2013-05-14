
require "thread"
require "network"
require "yaml"
require "setting"
require "daemon"
require 'optparse'

PID_FILE = "server.pid"

class NodeInfo
	attr_accessor :tinfo

	# @brief 認証済みかどうか
	attr_accessor :authed

	# @brief 生存チェックのタイムアウトを管理
	attr_accessor :alive_check_timeout
end

class CommandInfo
	# 現在処理中？
	attr_accessor :proceed

	# 実行しているノード
	attr_accessor :processer

	# 実行するコマンド
	attr_accessor :command

	# 実行中のコマンドを判断するためのID
	attr_accessor :id

	# ステータスチェックのタイムアウトを管理
	attr_accessor :status_check_timeout

	# 現在の状況(0 - 100のパーセント値)
	attr_accessor :percentage

	# @brief 実行要求を出したノード
	attr_accessor :requester

	def initialize(command, id)
		@command = command
		@proceed = false
		@id      = id
		@status_check_timeout = TimeoutHelper.new($setting.server.item_check_time, $setting.server.item_check_retry)
	end
end

class CommandManager
end

class CommandEntry
end

# @brief タイムアウトを管理するクラス
class TimeoutHelper
	def initialize(timeout, retrymax = 0)
		@timeout  = timeout
		@retrymax = retrymax
		@lasttime = Time.now
		@retry_count = 0
	end

	def update
		@lasttime    = Time.now
		@retry_count = 0
	end

	def retry
		@lasttime     = Time.now
		@retry_count += 1
	end

	def expired?
		return (Time.now - @lasttime) > @timeout
	end

	# @brief リトライカウントを振り切った場合
	def cant_help?
		return (@retry_count >= @retrymax)
	end

	attr_reader :lasttime
end

class DistssServer
	def initialize()
		@server   = NetworkServer.new($setting.global.port)
		@shutdown = false
	end

	# @brief サーバーを修了する
	# @note  デバッグ用の機能なので，通常は使用しない
	#        別スレッドでrunを実行して，closeすることを想定している
	def close
		@shutdown = true
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
			$logger.DEBUG("id = %d, last_alive_time = %s" % [id, node.private.alive_check_timeout.lasttime.to_s])
			id += 1
		end
		$logger.DEBUG("-----")
	end


	def onConnect(tinfo)
		# @FIXME ノード情報をprivateにしないといけないのはどうにかしたい
		tinfo.private                     = NodeInfo.new
		tinfo.private.authed              = false
		tinfo.private.alive_check_timeout = TimeoutHelper.new($setting.server.client_check_time, $setting.server.client_check_retry)
	end

	def run()
		$logger.DEBUG("create ServerControllerThread")

		# サーバのスレッドを開始する
		@server.onConnect = self.method(:onConnect)
		@server.run

		# @FIXME nlistをロックせずに読み書きしており，確率がかなり低いものの厄介な不具合を起こす可能性が高い
		@node_list  = @server.nlist

		@item_list  = Array.new
		@wait_queue = Queue.new
		@id_count   = 1

		@dump_timeout = TimeoutHelper.new($setting.server.debug_dump_time)
		while true
			if @shutdown
				break
			end

			@node_list.each do |node|
				while @server.recv?(node)
					# 最終応答時間を修正
					node.private.alive_check_timeout.update

					request = @server.recv(node)
					reply   = nil

					$logger.DEBUG(" [request] " + request.slice(0, 20))

					# メッセージエコー
					if request =~ /^echo (.*)$/
						reply = $1
					end

					# 動画の追加
					# request : add <コマンド文字列>
					# reply   : addr <id>
					if request =~ /^add (.*)$/
						i           = CommandInfo.new($1, @id_count)
						i.requester = node

						@id_count += 1

						@item_list.push(i)
						@wait_queue.push(i)

						reply = "addr " + i.id.to_s
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
							item.status_check_timeout.update
						else
							reply += "-1 none"
						end
					end

					# 動画の完了
					# request : fin <id> <出力メッセージ>
					# reply(for executer) : finr <id>
					# reply(for client) : finr <id> <出力メッセージ>
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
								@server.send(item.requester, "finr %d %s" % [id, result])
							end
						end

						# DumpItem()
					end

					# コマンドのエラー
					# request : err <id> <retcode> <msg>
					# reply(for executer) : errr <id>
					# reply(for client) : errr <id> <retcode> <msg>
					if request =~ /^err (\d*) (\d*) (.*)/
						# @TODO 将来的には，エラーの場合は状態を差し戻し
						#       現在の実装は，そのまま要求を出したノードにエラーを通知する

						id      = $1.to_i
						retcode = $2.to_i
						msg     = $3
						item    = FindItemById(id)
						reply   = "errr " + id.to_s

						# @FIXME これ忘れていたらアウト？
						#        ケアレスミスを減らすためのロジックを考える
						if nil == item
							$logger.ERROR("wrong job id")
							next
						end

						# 要求を出したノードに返事を返す
						@server.send(item.requester, "errr %d %d %s" % [id, retcode, result])

						# 終了したので削除
						@item_list.delete(item)

						# @TODO 将来的に使用する差し戻しのコード
						# item.proceed = false
						# @wait_queue.push(item)
					end

					# ***** クライアントからの返事関係のメッセージ *****

					if request =~ /pong/
						node.private.alive_check_timeout.update
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
							item.status_check_timeout.update
							item.percentage = percentage
						end
					end

					if reply == nil
						reply = "none"
					end
					@server.send(node, reply)

				end

				# クライアントが一定時間通信のない場合 ping を送信
				if node.private.alive_check_timeout.expired?
					if node.private.alive_check_timeout.cant_help?
						# クライアントの接続がタイムアウトした場合
						$logger.WARN(" ****** connection timeout *****")
						@server.disconnect(node)
					else
						# リトライ
						@server.send(node, "ping")
					end
				end
			end

			# アイテムの状態をチェックする
			@item_list.each do |item|
				# 実行中か？
				if item.proceed == false
					next
				end

				# 実行中の場合は一定期間ごとにステータスを求める
				if item.status_check_timeout.expired?
					# 一定時間以上返事を返していない場合，アプリケーションが落ちたと判断する
					# （ただし，ノード自体が落ちたとは判断をしない．ノードはpingの時間から判定をする）
					if item.status_check_timeout.cant_help?
						item.proceed = false
						@wait_queue.push(item)

						$logger.WARN("item timeout " + item.id.to_s)
					else
						msg = "status " + item.id.to_s
						item.status_check_timeout.retry
						@server.send(item.processer, msg)
					end
				end
			end

			if @dump_timeout.expired?
				@dump_timeout.update
				DumpItem()
				DumpNode()
			end

			sleep 0.01
		end

		@server.close

		$logger.DEBUG("end ServerControllerThread")
	end
end

if __FILE__ == $PROGRAM_NAME
	$logger.level = $setting.server.loglevel
	$logger.tag   = "server"

	# デバッグ用に必ずスレッド内での例外を補足する
	Thread.abort_on_exception = true

	# 引数の解析
	daemon_opt = ""
	opt = OptionParser.new
	opt.on("--start") { |v| daemon_opt = "start" }
	opt.on("--stop")  { |v| daemon_opt = "stop"  }
	opt.parse(ARGV)

	# サーバの制御
	daemon = Daemon.new(PID_FILE)
	if daemon_opt == "start"
		if daemon.start == -2
			puts "[ERROR] server already running."
			exit 1
		else
			puts "[INFO] running as daemon."
		end
	elsif daemon_opt == "stop"
		if daemon.stop == -2
			puts "[ERROR] server not running."
			exit 1
		else
			puts "[INFO] server stop."
		end

		exit 0
	end

	server = DistssServer.new()
	server.run()
end


