local pixel = require "pixel"
local socket = require "socket"
local sprotoloader = require "sprotoloader"
local sharemap = require "sharemap"

local host = sprotoloader.load(1):host "package"
local sender = host:attach(sprotoloader.load(2))

U = {}

local function send(s)
	if U.fd then
		socket.write(U.fd, string.pack(">s2", s))
	end
end

function send_package(proto, args)
	send(sender(proto, args))
end

REQUEST = {}

local function client_request(name, args, response)
	pixel.log("%d client:%s\n", pixel.time(), name)
	local f = assert(REQUEST[name], "not support client request:"..name)
	local r = f(args)
	if response then
		return response(r)
	end
end

pixel.protocol {
	name = "client",
	id = pixel.PIXEL_CLIENT,
	unpack = function(msg, sz)
		return host:dispatch(msg, sz)
	end,
	dispatch = function(_,_,type,...)
		if type == "REQUEST" then
			local ok, result = pcall(client_request, ...)
			if ok then
				if result then
					send(result)
				end
			else
				pixel.err("error:%s\n", result)
			end
		end
	end
}


function init()
	database = pixel.bind("SIMPLEDB")
end

function exit()
	U = {}
end

--rpc request

function request:login(uid, sid, secret)
	pixel.log("%s is login\n", uid)
	gated = pixel.bind(self.source)
	U.uid = uid
	U.sid = sid
	U.secret = secret

	pixel.fork(function()
		while true do
			send_package("heartbeat", {time=pixel.now()})
			pixel.sleep(500)
		end
	end)
end

function request:logout()
	gated.req.logout(U.uid, U.sid)
	pixel.log("%s is logout\n", U.uid)
	pixel.exit()
end

function request:auth(fd)
	U.fd = fd
end

function request:afk()
	U.fd = nil
	pixel.log("AFK\n")
end

function request:send(...)
	send_package(...)
end


--client request

function REQUEST.handshake()
	local data = {}
	data.boolval = true
	data.intval = 42
	data.strval = "string pack by sproto"
	data.arrval = {"hello", "world", "foo", "bar"}
	return {msg="welcome to pixel", data=data}
end

function REQUEST.quit()
	gated.req.kick(U.uid, U.sid)
end

function REQUEST.set(req)
	return {value = database.req.set(req.key, req.value)}
end

function REQUEST.get(req)
	return {value = database.req.get(req.key)}
end