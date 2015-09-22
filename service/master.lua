local pixel = require "pixel"
local socket = require "socket"


local harbor_name = {}
local harbor_addr = {}

function _master(id, addr)
	pixel.log("master accept harbor from addr :%s\n", addr)
	socket.start(id)
	for i, v in pairs(harbor_addr) do
		socket.write(id, "A "..i.." "..v.address.."\n")
	end
	for i, v in pairs(harbor_name) do
		socket.write(id, "N "..i.." "..v.."\n")
	end
	while true do
		local line = socket.readline(id)
		if not line then
			break
		end
		local cmd, p1, p2 = string.match(line, "([^ ]+) ([^ ]+) ([^ ]+)$")
		if cmd == "A" then
			harbor_addr[p1] = {address=p2, fd=id}
		elseif cmd == "N" then
			harbor_name[p1] = p2
		end
		pixel.log("master regist global cmd:%s %s %s\n", cmd, p1, p2)
		for i, v in pairs(harbor_addr) do
			if v.fd ~= id then
				socket.write(v.fd, line.."\n")
			end
		end
	end
	pixel.log("master disconnect harbor from addr :%s\n", addr)
	for i, v in pairs(harbor_addr) do
		if v.fd == id then
			harbor_addr[i] = nil
		end
	end
end

function init()
	local standalone = pixel.getenv "standalone"
	local id = socket.listen(standalone)
	socket.start(id, function(newid, addr)
		pixel.fork(_master, newid, addr)
	end)
end

