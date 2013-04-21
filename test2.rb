require "rubygems"
require "systemu"
require "thread"

EXECUTER_NUM = 30

Thread.abort_on_exception = true

Thread.new { system "ruby server.rb" }

Thread.new { systemu "cat task.txt | ruby client.rb" }

sleep 60

for i in 0..EXECUTER_NUM do
	Thread.new { systemu "ruby executer.rb" }
end

sleep 60000

