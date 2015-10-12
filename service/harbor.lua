local pixel = require "pixel"
local socket = require "socket"
local sc = require "socketchannel"

local harbor_name = {}
local harbor_addr = {}
local harbor_sess = {}

local function read_response(sock)
	local header = sock:read(9)
	if not header then
		print("read_response failed")
	end
	local sz, session, ret = string.unpack("<I4I4b", header)
	local cont = sock:read(sz)
	local msg = string.unpack("s2", cont)
	return session, ret==1, msg, false
end

function _master()
	socket.start(master_id)
	local harbor_id = pixel.getenv "harbor"
	socket.write(master_id, "A "..harbor_id.." "..address.."\n")
	while true do
		local line = socket.readline(master_id)
		if not line then
			break
		end
		local cmd, p1, p2 = string.match(line, "([^ ]+) ([^ ]+) ([^ ]+)$")
		if cmd == "A" then
			local host, port = string.match(p2, "([^:]+):([^.]+)$")
			local c = sc.channel {
				host = host,
				port = tonumber(port),
				response = read_response,
				nodelay = true,
			}
			assert(c:connect(true))
			harbor_addr[tonumber(p1)] = c
		elseif cmd == "N" then
			harbor_name[p1] = p2
		end
		pixel.log("harbor update cmd:%s %s %s\n", cmd, p1, p2)
	end
end

function _harbor(id)
	socket.start(id)
	while true do
		local header = socket.read(id, 20)
		if not header then
			break
		end
		local sz, dest, session, t = string.unpack("<I4I8I4I4", header)
		local cont = socket.read(id, sz)
		if not cont then
			break
		end
		local data = string.unpack("s2", cont)
		pixel.timeout(0, function()
			-- function post:request(id, dest, session, t, data)
				local ok, retdata, retsz = pcall(pixel.rawcall, tonumber(dest), 0, t, session, data)
				if ok then
					local msg = pixel.tostring(retdata, retsz)
					local resp = string.pack("<I4I4bs2", retsz+2, session, 1, msg)
					socket.write(id, resp)
				else
					pixel.err("call failed")
					local resp = string.pack("<I4I4bs2", retsz+2, session, 0, retdata)
					socket.write(id, resp)
				end
			-- end
		end)
	end
end

pixel.protocol {
	name = "harbor",
	id = pixel.PIXEL_HARBOR,
	unpack = pixel.harbor_unpack,
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
	pixel.dispatch("harbor", function(_, dest, t, ret_session, ret_source, data, sz)
		local session = harbor_sess[dest] or 1
		harbor_sess[dest] = session + 1
		local harbor_id = pixel.harbor(dest)
		local c = harbor_addr[harbor_id]
		local msg = pixel.tostring(data, sz)
		sz = string.len(msg)
		local request = string.pack("<I4I8I4I4s2", sz+2, dest, session, t, msg)
		local ok, retmsg = pcall(function()
			return c:request(request, session)
		end)
		if not ok then
			pixel.rawsend(ret_source, 0, pixel.PIXEL_ERROR, ret_session, "")
		else
			pixel.rawsend(ret_source, 0, pixel.PIXEL_RESPONSE, ret_session, retmsg)
		end
	end)
	pixel.start_harbor()
end

function request:query(name)
	return harbor_name[name]
end

function post:regist(name, handle)
	if master_id then
		socket.write(master_id, "N "..name.." "..handle.."\n")
	end
end