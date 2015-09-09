local pixel = require "pixel"
local socket = require "socket"
local crypt = require "crypt"

local config = {
	balance = 3,		--auth server number
	host = "0.0.0.0",
}

local gameserver_list = {}
local user_online = {}

local function send_package(fd, data)
	if not socket.write(fd, data.."\n") then
		error("socket :%d send failed", fd)
	end
end

local function recv_package(fd)
	return socket.readline(fd)
end

local function auth_handle(token, ip)
	local username, server, password = token:match("([^@]+)@([^:]+):(.+)")
	username = crypt.base64decode(username)
	server = crypt.base64decode(server)
	password = crypt.base64decode(password)

	--implement auth
	local uid = username

	return server, uid, username
end

local function login_handle(server, uid, username, secret)
	pixel.log("%s@%s is login, username:%s, secret:%s\n", uid, server, username, crypt.hexencode(secret))
	local gameserver = assert(gameserver_list[server], "unknown gameserver")
	local last = user_online[uid]
	if last then
		last.address.req.kick(uid, last.subid)
	end
	if user_online[uid] then
		error(string.format("user:%s is already online\n", username))
	end
	local subid = gameserver.req.login(uid, username, secret)
	user_online[uid] = {address = gameserver, subid = subid, server = server}
	return subid
end


function login_slave_init()
	local function auth(fd, addr)
		fd = assert(tonumber(fd))
		pixel.log("connect from %s (fd = %d)\n", addr, fd)
		socket.start(fd)
		socket.limit(fd, 8192)

		local clientkey = recv_package(fd)
		clientkey = crypt.base64decode(clientkey)
		if #clientkey ~= 8 then
			send_package(fd, "400 Bad Request")
			error("invalid clientkey\n")
		end
		local challenge = crypt.randomkey()
		send_package(fd, crypt.base64encode(challenge))
		local serverkey = crypt.randomkey()
		send_package(fd, crypt.base64encode(crypt.dhexchange(serverkey)))
		local secret = crypt.dhsecret(clientkey, serverkey)
		local hmac = crypt.hmac64(challenge, secret)
		local ret = recv_package(fd)
		if hmac ~= crypt.base64decode(ret) then
			send_package(fd, "400 Bad Request")
			error("challenge failed\n")
		end
		local check_token = recv_package(fd)
		local token = crypt.desdecode(secret, crypt.base64decode(check_token))
		local server, uid, username = auth_handle(token, addr)
		socket.abandon(fd)
		return server, uid, username, secret
	end

	function request:attach(fd, addr)
		return pcall(auth, fd, addr)
	end
end

local port
local listen
function login_master_init()
	local slaves = {}
	local user_login = {}

	function request:logout(uid, subid)
		local u = user_online[uid]
		if u then
			pixel.log("%s@%s is logout\n", uid, u.server)
			user_online[uid] = nil
		end
	end

	function request:regist(server)
		local address = self.source
		gameserver_list[server] = pixel.bind(address)
		pixel.log("gated [%s] regist, address:%d\n", server, address)
	end

	local function accept(slave, fd, addr)
		local ok, server, uid, username, secret = slave.req.attach(fd, addr)
		socket.start(fd)
		if not ok then
			send_package(fd, "401 Unauthorized")
			error(server)
		end
		if user_login[uid] then
			send_package(fd, "406 Not Acceptable")
			error(string.format("user %s is already login", username))
		end
		user_login[uid] = true

		local ok, err = pcall(login_handle, server, uid, username, secret)
		user_login[uid] = nil
		if ok then
			send_package(fd, "200 "..crypt.base64encode(err))
		else
			send_package(fd, "403 Forbidden")
			error(err)
		end
	end

	for i=1, config.balance do
		table.insert(slaves, pixel.service(SERVICE_NAME))
	end

	local balance = 1
	config.port = port or 8000
	listen = socket.listen(config.host, config.port)
	if listen == -1 then
		pixel.err("logind listen at %s:%d failed\n", config.host, config.port)
		return
	else
		pixel.log("logind listen at %s:%d\n", config.host, config.port)
	end
	socket.start(listen, function(fd, addr)
		local slave = slaves[balance]
		balance = balance + 1
		if balance > #slaves then
			balance = 1
		end
		local ok, err = pcall(accept, slave, fd, addr)
		if not ok then
			pixel.err("login %d err:%s\n", fd, err)
		end
		socket.close(fd)
	end)
end

function init(port)
	if pixel.query("logind") then
		login_slave_init()
	else
		pixel.name("logind")
		login_master_init()
		function exit()
			if listen >= 0 then
				socket.close(listen)
				listen = nil
			end
		end
	end
end