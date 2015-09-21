local pixel = require "pixel"
local socket = require "socket"

local harbor_name = {}
local harbor_addr = {}

function _master()
	socket.start(master_id)
	while true do
		local line = socket.readline(master_id)
		local name, handle, address = string.match(line, "([^ ]+) ([^ ]+) ([^ ]+)$")
		pixel.log("harbor update name:%s handle:%d address:%s\n", name, handle, address)
		harbor_name[name] = {handle = handle, address = address}
		harbor_addr[handle] = address
	end
end

function _harbor(id)
	socket.start(id)
	while true do
		local line = socket.readline(id)
		print("_harbor", line)
	end
end

pixel.protocol {
	name = "harbor",
	id = pixel.PIXEL_HARBOR,
	unpack = pixel.unpack
}

function init()
	pixel.name "harbor"
	address = pixel.getenv "address"
	local master = pixel.getenv "master"
	master_id = socket.open(master)
	pixel.fork(_master)

	id = socket.listen(address)
	socket.start(id, function(newid, addr)
		pixel.fork(_harbor, newid)
	end)
	pixel.dispatch("harbor", function(session, dest, msg, sz)
		local address = harbor_addr[tostring(dest)]
		print("address:", address)

	end)
	pixel.start_harbor()
end

function request:query(name)
	return harbor_name[name].handle
end

function post:regist(name, handle)
	socket.write(master_id, name.." "..handle.." "..address.."\n")
end