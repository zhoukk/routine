local pixel = require "pixel"
local crypt = require "crypt"
local login = require "login"

local gameserver_list = {}
local user_online = {}

local logind = {
	host = "0.0.0.0",
	port = 8000,
	instance = 2,
	multi_login = false,
	name = "logind",
	request={},
}

function logind.auth_handler(token)
	-- the token is base64(user)@base64(server):base64(password)
	local user, server, password = token:match("([^@]+)@([^:]+):(.+)")
	user = crypt.base64decode(user)
	server = crypt.base64decode(server)
	password = crypt.base64decode(password)
	assert(password == "password")
	return server, user
end

function logind.login_handler(server, uid, secret)
	pixel.log("%s@%s is login, secret:%s\n", uid, server, crypt.hexencode(secret))
	local gameserver = assert(gameserver_list[server], "unknown gameserver")
	local last = user_online[uid]
	if last then
		last.address.req.kick(uid, last.subid)
	end
	if user_online[uid] then
		error(string.format("user:%s is already online\n", uid))
	end
	local subid = gameserver.req.login(uid, secret)
	user_online[uid] = {address = gameserver, subid = subid, server = server}
	return subid
end

function logind.request:regist(server)
	local address = self.source
	gameserver_list[server] = pixel.bind(address)
	pixel.log("gated [%s] regist, address:%d\n", server, address)
end

function logind.request:logout(uid, subid)
	local u = user_online[uid]
	if u then
		pixel.log("%s@%s is logout\n", uid, u.server)
		user_online[uid] = nil
	end
end


function init()
	login.start(logind)
end

function exit()
	login.exit()
end