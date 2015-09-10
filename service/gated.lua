local pixel = require "pixel"
local gate = require "gate"

local users = {}
local username_map = {}
local internal_id = 0

local gated = {}

function gated.login_handler(uid, secret)
	if users[uid] then
		error(string.format("%s is already login", uid))
	end

	internal_id = internal_id + 1
	local id = internal_id	-- don't use internal_id directly
	local username = gate.username(uid, id, servername)

	-- you can use a pool to alloc new agent
	local agent = pixel.service "agent"
	local u = {
		username = username,
		agent = agent,
		uid = uid,
		subid = id,
	}

	-- trash subid (no used)
	agent.req.login(uid, id, secret)

	users[uid] = u
	username_map[username] = u

	gate.login(username, secret)

	-- you should return unique subid
	return id
end

function gated.logout_handler(uid, subid)
	local u = users[uid]
	if u then
		local username = gate.username(uid, subid, servername)
		assert(u.username == username)
		gate.logout(u.username)
		users[uid] = nil
		username_map[u.username] = nil
		logind.req.logout(uid, subid)
	end
end

function gated.kick_handler(uid, subid)
	local u = users[uid]
	if u then
		local username = gate.username(uid, subid, servername)
		assert(u.username == username)
		pcall(u.agent.req.logout)
	end
end

function gated.disconnect_handler(username)
	local u = username_map[username]
	if u then
		u.agent.req.afk()
	end
end

function gated.request_handler(username, msg)
	local u = username_map[username]
	return pixel.rawcall(u.agent.address, 0, "client", 0, msg, sz)
end

function gated.register_handler(name)
	servername = name
	logind.req.regist(servername)
end


function init()
	logind = pixel.bind("logind")
	gate.start(gated)
end

function exit()
	gate.exit()
end

