package.path = package.path..";../lualib/?.lua"
package.cpath = package.cpath..";../?.so"

local socket = require "clientsocket"

local ok, net = pcall(function() return socket.login {
	host = "127.0.0.1",
	port = 8000,
	user = "pixel",
	pass = "password",
	server = "sample",
} end)

if not ok then
	print(net)
end

net:connect("127.0.0.1", 8001)

net:request("handshake", nil, function(ret)
	print("handshake", ret.msg)
	for i, v in pairs(ret.data) do
		print(i, v)
		if type(v) == "table" then
			for k, j in pairs(v) do
				print("\t", k, j)
			end
		end
	end
end)

net:request("set", {key="name", value="pixel"}, function(ret)
	print("set ret", ret.old)
end)

net:request("get", {key="name"}, function(ret)
	print("get ret", ret.value)
end)


local i = 1
net:handle("heartbeat", function(ret)
	print("heartbeat", ret.time)
	if i > 10 then
		net:request("quit")
	end
	i = i + 1
end)

while i <= 10 do
	net:dispatch()
end
