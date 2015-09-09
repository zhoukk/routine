local pixel = require "pixel"
local socket = require "socket.c"
local crypt = require "crypt"
local netpack = require "netpack"

local b64encode = crypt.base64encode
local b64decode = crypt.base64decode

local maxclient
local nodelay
local queue
local expired_number
local client_number = 0
local internal_id = 0
local connection = {}
local handshake = {}
local uid_login = {}
local user_login = {}
local fd_login = {}

local gate = {}
local gated = {}

local SOCKET = {}
local listen

local logind

function init()
	logind = pixel.bind("logind")
end

function exit()
	if listen then
		socket.close(listen)
		listen = nil
	end
end

function gate.disconnect(fd)
	handshake[fd] = nil
	local u = fd_login[fd]
	if u then
		u.agent.req.afk()
		fd_login[fd] = nil
	end
end

function gate.openclient(fd)
	if connection[fd] then
		socket.start(fd)
	end
end

function gate.closeclient(fd)
	local c = connection[fd]
	if c then
		connection[fd] = false
		socket.close(fd)
	end
end

function gated.user(token)
	-- base64(username)@base64(server)#base64(subid)
	local username, servername, subid = token:match "([^@]*)@([^#]*)#(.*)"
	return b64decode(username), b64decode(subid), b64decode(servername)
end

function gated.token(username, servername, subid)
	return string.format("%s@%s#%s", b64encode(username), b64encode(servername), b64encode(tostring(subid)))
end

function gated.ip(token)
	local u = user_login[token]
	if u and u.fd then
		return u.ip
	end
end

local function do_auth(fd, message, addr)
	local token, index, hmac = string.match(message, "([^:]*):([^:]*):([^:]*)")
	local u = user_login[token]
	if u == nil then
		return "404 User Not Found"
	end
	local idx = assert(tonumber(index))
	hmac = b64decode(hmac)

	if idx <= u.version then
		return "403 Index Expired"
	end

	local text = string.format("%s:%s", token, index)
	local v = crypt.hmac_hash(u.secret, text)	-- equivalent to crypt.hmac64(crypt.hashkey(text), u.secret)
	if v ~= hmac then
		return "401 Unauthorized"
	end
	u.version = idx
	u.fd = fd
	u.ip = addr
	fd_login[fd] = u
end

local function auth(fd, addr, msg, sz)
	local message = pixel.tostring(msg, sz)
	pixel.drop(msg, sz)
	local ok, result = pcall(do_auth, fd, message, addr)
	if not ok then
		pixel.err("%s\n", result)
		result = "400 Bad Request"
	end
	local close = result ~= nil
	if result == nil then
		result = "200 OK"
		local u = fd_login[fd]
		u.agent.req.auth(fd)
	end
	socket.send(fd, string.pack(">s2", result))
	if close then
		gate.closeclient(fd)
	end
end

pixel.protocol {
	name = "client",
	id = pixel.PIXEL_CLIENT,
}

local function do_request(fd, msg, sz)
	local u = assert(fd_login[fd], "invalid fd")
	pixel.rawsend(u.agent.address, 0, "client", 0, msg, sz)
end

local function client_request(fd, msg, sz)
	local ok, err = pcall(do_request, fd, msg, sz)
	if not ok then
		pixel.err("invalid package %s from %d\n", err, fd)
		gate.closeclient(fd)
	end
end

function SOCKET.open(fd, addr)
	if client_number >= maxclient then
		socket.close(fd)
		return
	end
	if nodelay then
		socket.nodelay(fd)
	end
	connection[fd] = true
	client_number = client_number + 1

	handshake[fd] = addr
	gate.openclient(fd)
end

local function close(fd)
	gate.disconnect(fd)
	local c = connection[fd]
	if c ~= nil then
		connection[fd] = nil
		client_number = client_number - 1		
	end
end

function SOCKET.close(fd)
	close(fd)
end

function SOCKET.error(fd, msg)
	close(fd)
end

local function dispatch_msg(fd, msg, sz)
	if connection[fd] then
		local addr = handshake[fd]
		if addr then
			auth(fd, addr, msg, sz)
			handshake[fd] = nil
		else
			client_request(fd, msg, sz)
		end
	end
end

local function dispatch_queue()
	local fd, msg, sz = netpack.pop(queue)
	if fd then
		pixel.fork(dispatch_queue)
		dispatch_msg(fd, msg, sz)
		for fd, msg, sz in netpack.pop, queue do
			dispatch_msg(fd, msg, sz)
		end
	end
end

SOCKET.data = dispatch_msg

SOCKET.more = dispatch_queue

SOCKET.warning = function(id, size)
	pixel.err("%d K bytes send blocked on %d\n", size, id)
end


pixel.protocol {
	name = "socket",
	id = pixel.PIXEL_SOCKET,
	unpack = function(msg, sz)
		return netpack.filter(queue, msg, sz)
	end,
	dispatch = function(_,_,q,t, ...)
		queue = q
		if t then
			SOCKET[t](...)
		end
	end
}

function request:open(conf)
	local address = conf.address or "0.0.0.0"
	local port = assert(conf.port)
	maxclient = conf.maxclient or 1024
	expired_number = conf.expired_number or 128
	nodelay = conf.nodelay
	servername = conf.servername
	listen = socket.listen(address, port)
	if listen == -1 then
		pixel.err("gated [%s] listen at %s:%d failed\n", servername, address, port)
		return
	else
		pixel.log("gated [%s] listen at %s:%d\n", servername, address, port)
	end
	socket.start(listen)
	logind.req.regist(servername)
end

function request:login(uid, username, secret)
	if uid_login[uid] then
		error(string.format("%s is already login", username))
	end
	internal_id = internal_id + 1
	local subid = internal_id

	local token = gated.token(username, servername, subid)

	local agent = pixel.service "agent"
	local u = {
		uid = uid,
		subid = subid,
		username = username,
		token = token,
		agent = agent,
		secret = secret,
		version = 0,
	}
	agent.req.login(uid, subid, secret)

	uid_login[uid] = u
	user_login[token] = u
	return subid
end

function request:logout(uid, subid)
	local u = uid_login[uid]
	if u then
		local token = gated.token(u.username, servername, subid)
		assert(u.token == token)
		if u.fd then
			gate.closeclient(u.fd)
			fd_login[u.fd] = nil
		end
		uid_login[uid] = nil
		user_login[token] = nil
		logind.req.logout(uid, subid)
	end
end

function request:kick(uid, subid)
	local u = uid_login[uid]
	if u then
		local token = gated.token(u.username, servername, subid)
		assert(u.token == token)
		pcall(u.agent.req.logout)
	end
end