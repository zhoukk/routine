local pixel = require "pixel"
local socket = require "socket"
local sc = require "socketchannel"

local harbor_name = {}
local harbor_addr = {}
local harbor_sess = {}

local function read_response(sock)
	local header = sock:read(6)
	local sz, session = string.unpack("<I2I4", header)
	local cont = sock:read(sz)
	local msg = string.unpack("s2", cont)
	return session, true, msg, false
end

function _master()
	socket.start(master_id)
	while true do
		local line = socket.readline(master_id)
		if not line then
			break
		end
		local name, handle, address = string.match(line, "([^ ]+) ([^ ]+) ([^ ]+)$")
		pixel.log("harbor update name:%s handle:%d address:%s\n", name, handle, address)
		harbor_name[name] = handle

		local host, port = string.match(address, "([^:]+):([^.]+)$")
		local c = sc.channel {
			host = host,
			port = tonumber(port),
			response = read_response,
			nodelay = true,
		}
		assert(c:connect(true))
		harbor_addr[tonumber(handle)] = c
	end
end

function _harbor(id)
	socket.start(id)
	while true do
		local header = socket.read(id, 14)
		if not header then
			break
		end
		local sz, dest, session = string.unpack("<I2I8I4", header)
		local cont = socket.read(id, sz)
		if not cont then
			break
		end
		local data = string.unpack("s2", cont)
		local retdata, retsz = pixel.rawcall(tonumber(dest), 0, "lua", 0, data)
		local retmsg = pixel.tostring(retdata, retsz)
		pixel.drop(retdata, retsz)
		sz = string.len(retmsg)
		print("_harbor", sz)
		local resp = string.pack("<I2I4s2", sz+2, session, retmsg)
		socket.write(id, resp)
	end
end

pixel.protocol {
	name = "harbor",
	id = pixel.PIXEL_HARBOR,
	unpack = function(msg, sz)
		local data = pixel.tostring(msg, sz)
		pixel.drop(msg, sz)
		return data
	end
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
	pixel.dispatch("harbor", function(_, dest, msg)
		local session = harbor_sess[dest] or 1
		local c = harbor_addr[dest]
		sz = string.len(msg)
		local request = string.pack("<I2I8I4s2", sz+2, dest, session, msg)
		local retmsg = c:request(request, session)
		harbor_sess[dest] = session + 1
		print("ret ", retmsg)
		pixel.ret(retmsg)
	end)
	pixel.start_harbor()
end

function request:query(name)
	return harbor_name[name]
end

function post:regist(name, handle)
	if master_id then
		socket.write(master_id, name.." "..handle.." "..address.."\n")
	end
end