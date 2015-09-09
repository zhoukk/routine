local c = require "clientsocket.c"
local crypt = require "crypt"
local sproto = require "sproto"
local proto = require "proto"

local host = sproto.new(proto.s2c):host "package"
local request = host:attach(sproto.new(proto.c2s))

local socket = {}

local function closefd(self)
	if self.__fd then
		c.close(self.__fd)
		self.__fd = nil
	end
end

local function readline(self)
	local str = self.__read
	local nl = str:find("\n", 1, true)
	if nl then
		self.__read = str:sub(nl+1)
		return str:sub(1, nl-1)
	end
	while true do
		local ok, rd = pcall(function() return c.read(self.__fd) end)
		if not ok then
			break
		end
		if rd == "" then
			break
		end
		if rd then
			str = str .. rd
			local nl = str:find("\n", 1, true)
			if nl then
				self.__read = str:sub(nl+1)
				return str:sub(1, nl-1)
			end
		end
	end
	error("socket closed")
end

local function writeline(self, text)
	text = text .. "\n"
	c.write(self.__fd, text)
end

local function connect(addr, port)
	local fd = assert(c.connect(addr, port))
	return {
		__fd = fd,
		login = login,
		__read = "",
		__select_rd = { fd },
	}
end

local function split_package(text)
	-- read whole package, todo
	local ok, str, offset = pcall(string.unpack, ">s2", text)
	if not ok then
		return
	end
	return str, text:sub(offset)
end

local function read_package(self)
	local result, text = split_package(self.__read)
	if result then
		self.__read = text
		return result
	end
	local ok, rd = pcall(function() return c.read(self.__fd) end)
	if not ok then
		return false
	end
	if not rd then
		return false
	end
	while true do
		if rd == "" then
			return false
		end
		if rd then
			local text = self.__read .. rd
			local result, text = split_package(text)
			if result then
				self.__read = text
				return result
			else
				self.__read = text
				return false	-- block
			end
		end
	end
end

local function auth(self)
	if self.__auth == nil then
		local handshake = self.__token .. self.__index
		self.__index = self.__index + 1
		local hmac = crypt.hmac_hash(self.__secret, handshake)
		local package = string.pack(">s2", handshake .. ":" .. crypt.base64encode(hmac))
		c.write(self.__fd, package)
		self.__auth = false
		return false
	else
		-- recv response
		local pack = read_package(self)
		if pack then
			if pack ~= "200 OK" then
				self.__auth = nil
				closefd(self)
				error(pack)
			end
			self.__auth = true
		elseif pack == nil then
			-- disconnect
			self.__auth = nil
			return nil
		else
			-- block
			return false
		end
	end
	return true
end

local function send_request(self, data)
	c.write(self.__fd, data)
end

local function dispatch_response(self, session, ...)
	for k,v in ipairs(self.__request) do
		if v.session == session then
			local cb = v.callback
			table.remove(self.__request, k)
			if cb then
				cb(...)
			end
			return
		end
	end
	error("Invalid session " .. session)
end

local function dispatch_request(self, name, ...)
	if not self.__handle then
		return
	end
	local cb = self.__handle[name]
	if cb then
		cb(...)
	else
		error("no handle for:"..name)
	end
end

local function handle_response(self, t, ...)
	if t == "RESPONSE" then
		dispatch_response(self, ...)
	else
		dispatch_request(self, ...)
	end
end

local function recv_response(self)
	if self.__fd == nil then
		return nil
	end
	if not self.__auth then
		local ret = auth(self)
		if not ret then
			return ret
		end
		for _, v in ipairs(self.__request) do
			send_request(self, v.data)
			if not self.__fd then
				return nil
			end
		end
	end
	local v = read_package(self)
	if not v then
		return v
	end
	handle_response(self, host:dispatch(v))
	return true
end

local function connect_gameserver(self, addr, port)
	self.__fd = assert(c.connect(addr, port))
	self.login = nil
	self.dispatch = recv_response
	self.__host = addr
	self.__port = port
	self.__read = ""
	self.__select_rd[1] = self.__fd
	self.__request = {}
	self.__auth = nil
	self.__index = 1
	self.__session = 1
end

local function reconnect_gameserver(self)
	closefd(self)
	self.__fd = assert(c.connect(self.__host, self.__port))
	self.__read = ""
	self.__select_rd[1] = self.__fd
	self.__auth = nil
	self.__index = self.__index + 1
end

local function handle_gameserver(self, name, cb)
	if not self.__handle then
		self.__handle = {}
	end
	self.__handle[name] = cb
end

local function request_gameserver(self, req, args, callback)
	local session = self.__session
	local data = request(req, args, session)
	local r = {
		session = session,
		data = string.pack(">s2", data),
		callback = callback,
	}
	table.insert(self.__request, r)
	self.__session = session + 1
	if self.__auth then
		send_request(self, r.data)
	end
end

local function close_gameserver(self)
	closefd(self)
end

function socket.login(token)
	local self = connect(token.host, token.port)
	local clientkey = crypt.randomkey()
	writeline(self, crypt.base64encode(crypt.dhexchange(clientkey)))
	local challenge = crypt.base64decode(readline(self))
	local secret = crypt.dhsecret(crypt.base64decode(readline(self)), clientkey)
	local hmac = crypt.hmac64(challenge, secret)
	writeline(self, crypt.base64encode(hmac))

	local function encode_token(token)
		return string.format("%s@%s:%s",
			crypt.base64encode(token.user),
			crypt.base64encode(token.server),
			crypt.base64encode(token.pass))
	end

	local etoken = crypt.desencode(secret, encode_token(token))
	writeline(self, crypt.base64encode(etoken))
	local result = readline(self)
	local code = tonumber(string.sub(result, 1, 3))
	closefd(self)
	if code == 200 then
		self.__secret = secret
		local subid = crypt.base64decode(string.sub(result, 5))
		self.__token = string.format("%s@%s#%s:", crypt.base64encode(token.user), crypt.base64encode(token.server), crypt.base64encode(subid))
		crypt.base64decode(string.sub(result, 5))
		self.secret = secret
		self.connect = connect_gameserver
		self.request = request_gameserver
		self.reconnect = reconnect_gameserver
		self.handle = handle_gameserver
		self.close = close_gameserver
		return self
	else
		error(string.sub(result, 5))
	end
end

return socket
