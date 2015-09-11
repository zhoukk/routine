--[[

Protocol:

	line (\n) based text protocol

	1. Client->Server : base64(8bytes handshake client key)
	2. Server->Client : base64(8bytes random challenge)
	3. Server: Gen a 8bytes handshake server key
	4. Server->Client : base64(DH-Exchange(server key))
	5. Server/Client secret := DH-Secret(client key/server key)
	6. Client->Server : base64(HMAC(challenge, secret))
	7. Client->Server : DES(secret, base64(token))
	8. Server : call auth_handler(token) -> server, uid (A user defined method)
	9. Server : call login_handler(server, uid, secret) ->subid (A user defined method)
	10. Server->Client : 200 base64(subid)

Error Code:
	400 Bad Request . challenge failed
	401 Unauthorized . unauthorized by auth_handler
	403 Forbidden . login_handler failed
	406 Not Acceptable . already in login (disallow multi login)

Success:
	200 base64(subid)
]]

local pixel = require "pixel"
local socket = require "socket"
local crypt = require "crypt"


local function send_package(fd, data)
	if not socket.write(fd, data.."\n") then
		error(string.format("socket: %d send failed", fd))
	end
end

local function recv_package(fd)
	return socket.readline(fd)
end

local function launch_slave(auth_handler)
	local function auth(fd, addr)
		pixel.log("connect from %s (fd = %d)\n", addr, fd)
		socket.start(fd)
		socket.limit(fd, 8192)

		local clientkey = recv_package(fd)
		clientkey = crypt.base64decode(clientkey)
		if #clientkey ~= 8 then
			send_package(fd, "400 Bad Request")
			error("invalid clientkey")
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
			error("challenge failed")
		end
		local check_token = recv_package(fd)
		local token = crypt.desdecode(secret, crypt.base64decode(check_token))
		local ok, server, uid = pcall(auth_handler, token)
		socket.abandon(fd)
		return ok, server, uid, secret
	end

	function request:attach(fd, addr)
		return auth(fd, addr)
	end

end

local function launch_master(conf)
	local user_login = {}

	local function accept(conf, slave, fd, addr)
		local ok, server, uid, secret = slave.req.attach(fd, addr)
		socket.start(fd)

		if not ok then
			send_package(fd, "401 Unauthorized")
			error(server)
		end

		if not conf.multi_login then
			if user_login[uid] then
				send_package(fd, "406 Not Acceptable")
				error(string.format("user %s is already login", uid))
			end
			user_login[uid] = true
		end

		local ok, err = pcall(conf.login_handler, server, uid, secret)
		user_login[uid] = nil

		if ok then
			err = err or ""
			send_package(fd, "200 "..crypt.base64encode(err))
		else
			send_package(fd, "403 Forbidden")
			error(err)
		end
	end

	local balance = 1
	local host = conf.host or "0.0.0.0"
	local port = assert(tonumber(conf.port))
	local instance = conf.instance or 8
	local slaves = {}

	for i, v in pairs(conf.request) do
		request[i] = v
	end

	for i=1, instance do
		local slave = pixel.service(SERVICE_NAME)
		table.insert(slaves, slave)
	end
	listen = socket.listen(host, port)
	if listen == -1 then
		pixel.err("login listen at %s:%d failed\n", host, port)
		return
	end
	pixel.log("login listen at %s:%d\n", host, port)
	socket.start(listen, function(fd, addr)
		local slave = slaves[balance]
		balance = balance + 1
		if balance > #slaves then
			balance = 1
		end
		local ok, err = pcall(accept, conf, slave, fd, addr)
		if not ok then
			pixel.err("login %d err:%s\n", fd, err)
			socket.start(fd)
		end
		socket.close(fd)
	end)
end

local login = {}

function login.start(conf)
	local address = pixel.query(conf.name)
	if address then
		launch_slave(conf.auth_handler)
	else
		pixel.name(conf.name)
		launch_master(conf)
	end
end

function login.exit()
	if listen then
		socket.close(listen)
	end
end

return login