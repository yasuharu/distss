
$:.unshift(File.dirname(File.expand_path(__FILE__)))

require "yaml"
require "flogger"

# @brief 設定ファイルをロードして保持するクラス
class Setting
	def initialize(file)
		@global   = Global.new
		@server   = Server.new
		@client   = Client.new
		@executer = Executer.new

		read(file)
	end

	def read(file)
		setting = nil
		begin
			setting = YAML.load File.read file
		rescue => e
			p e
			exit 1
		end

		if setting.key? "global"
			if setting["global"].key? "server"
				if setting["global"]["server"].key? "host"
					@global.host = setting["global"]["server"]["host"]
				end

				if setting["global"]["server"].key? "port"
					@global.port = setting["global"]["server"]["port"]
				end
			end
		end

		if setting.key? "server"
			if setting["server"].key? "timeout"
				if setting["server"]["timeout"].key? "client_timeout"

					if setting["server"]["timeout"]["client_timeout"].key? "check_time"
						@server.client_check_time = setting["server"]["timeout"]["client_timeout"]["check_time"]
					end
					if setting["server"]["timeout"]["client_timeout"].key? "retry_count"
						@server.client_check_retry = setting["server"]["timeout"]["client_timeout"]["retry_count"]
					end

				end

				if setting["server"]["timeout"].key? "command_timeout"

					if setting["server"]["timeout"]["command_timeout"].key? "check_time"
						@server.item_check_time = setting["server"]["timeout"]["command_timeout"]["check_time"]
					end
					if setting["server"]["timeout"]["command_timeout"].key? "retry_count"
						@server.item_check_retry = setting["server"]["timeout"]["command_timeout"]["retry_count"]
					end

				end
			end

			if setting["server"].key? "debug_dump_time"
				@server.debug_dump_time = setting["server"]["debug_dump_time"]
			end

			if setting["server"].key? "loglevel"
				@server.loglevel = setting["server"]["loglevel"]
			end
		end

		if setting.key? "client"
			if setting["client"].key? "loglevel"
				@client.loglevel = setting["client"]["loglevel"]
			end
		end

		if setting.key? "executer"
			if setting["executer"].key? "loglevel"
				@executer.loglevel = setting["executer"]["loglevel"]
			end
		end
	end

	attr_reader :global
	class Global
		def initialize()
			@host = "127.0.0.1"
			@port = 55678
		end

		attr_accessor :host, :port
	end

	attr_reader :client
	class Client
		def initialize()
			@loglevel = FLogger::LEVEL_INFO
		end

		attr_accessor :loglevel
	end

	attr_reader :server
	class Server
		def initialize()
			@client_check_time  = 5
			@client_check_retry = 10
			@item_check_time    = 3
			@item_check_retry   = 5
			@debug_dump_time    = 1
			@loglevel           = FLogger::LEVEL_INFO
		end

		attr_accessor :client_check_time
		attr_accessor :client_check_retry
		attr_accessor :item_check_time
		attr_accessor :item_check_retry
		attr_accessor :debug_dump_time
		attr_accessor :loglevel
	end

	attr_reader :executer
	class Executer
		def initialize()
			@loglevel = FLogger::LEVEL_INFO
		end

		attr_accessor :loglevel
	end
end

SETTING_FILENAME = "setting.yaml"
$setting = Setting.new(SETTING_FILENAME)

