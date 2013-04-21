
require "network"

SERVER_PORT = 20001
server = NetworkServer.new(SERVER_PORT)
Thread.new { server.run }

client = NetworkClient.new("127.0.0.1", SERVER_PORT)
ret = client.connect
client.send("hoge")
client.send("fuga")
client.send("piyo")

sleep 10
