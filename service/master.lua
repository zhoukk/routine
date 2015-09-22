local pixel = require "pixel"
local socket = require "socket"


local harbor_name = {}
local harbor_addr = {}

function _master(id, addr)
	pixel.log("master accept harbor from addr :%s\n", addr)
	socket.start(id)
	harbor_addr[id] = addr
	for i, v in pairs(harbor_name) do
		socket.write(id, i.." "..v.handle.." "..v.address.."\n")
	end
	while true do
		local line = socket.readline(id)
		if not line then
			break
		end
		local name, handle, address = string.match(line, "([^ ]+) ([^ ]+) ([^ ]+)$")
		harbor_name[name] = {handle = handle, address = address, fd = id}
		pixel.log("master regist global name:%s handle:%s address:%s\n", name, handle, address)
		for i, v in pairs(harbor_addr) do
			if i ~= id then
				socket.write(i, line.."\n")
			end
		end
	end
	pixel.log("master disconnect harbor from addr :%s\n", addr)
	for i, v in pairs(harbor_name) do
		if v.fd == id then
			harbor_name[i] = nil
		end
	end
	harbor_addr[id] = nil
end

function init()
	local standalone = pixel.getenv "standalone"
	local id = socket.listen(standalone)
	socket.start(id, function(newid, addr)
		pixel.fork(_master, newid, addr)
	end)
end

