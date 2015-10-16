local c = require "pixel.c"
local serial = require "pixel.serial"

local string_format = string.format

local table_remove = table.remove
local table_insert = table.insert
local table_concat = table.concat
local table_unpack = table.unpack

local coroutine_create = coroutine.create
local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local coroutine_running = coroutine.running

local debug_traceback = debug.traceback

local pixel = {
	PIXEL_TEXT = 0,
	PIXEL_RESPONSE = 1,
	PIXEL_MULTICAST = 2,
	PIXEL_CLIENT = 3,
	PIXEL_SYSTEM = 4,
	PIXEL_HARBOR = 5,
	PIXEL_SOCKET = 6,
	PIXEL_ERROR = 7,
	PIXEL_QUEUE = 8,
	PIXEL_DEBUG = 9,
	PIXEL_LUA = 10,
	PIXEL_SNAX = 11,
	PIXEL_SERVICE = 12,
}

pixel.dump = c.dump
pixel.drop = c.drop
pixel.pack = serial.pack
pixel.unpack = serial.unpack
pixel.tostring = c.tostring
pixel.harbor = c.harbor
pixel.harbor_unpack = c.harbor_unpack

pixel.err = function(...)
	return c.log("[ERROR] "..string_format(...))
end

pixel.log = function(...)
	return c.log(string_format(...))
end

local proto = {}

function pixel.protocol(p)
	proto[p.name] = p
	proto[p.id] = p
end

function pixel.dispatch(tname, func)
	local p = assert(proto[tname], tname)
	local ret = p.dispatch
	p.dispatch = func
	return ret
end

function pixel.setenv(key, val)
	c.command("SETENV", key.." "..val)
end

function pixel.getenv(key)
	local ret = c.command("GETENV", key)
	if ret == "" then
		return nil
	else
		return ret
	end
end

local self_addr
function pixel.self()
	if self_addr then
		return self_addr
	end
	self_addr = tonumber(c.command("SELF"))
	return self_addr
end

function pixel.start_harbor()
	c.command("HARBOR")
end

local harbor
local function get_harbor()
	if not harbor then
		harbor = pixel.bind("harbor")
	end
	return harbor
end

function pixel.name(name, addr)
	addr = addr or pixel.self()
	c.command("NAME", name.." "..addr)
	if name == string.upper(name) then
		get_harbor().post.regist(name, addr)
	end
end

function pixel.query(name)
	local addr = c.command("QUERY", name)
	if addr then
		return tonumber(addr)
	end
	if name == string.upper(name) then
		addr = get_harbor().req.query(name)
	end
	return addr
end

function pixel.now()
	return tonumber(c.command "NOW")
end

function pixel.starttime()
	return tonumber(c.command "STARTTIME")
end

function pixel.time()
	return math.floor(pixel.now()/100+pixel.starttime())
end

local coroutine_pool = {}
local function co_create(f)
	local co = table_remove(coroutine_pool)
	if co == nil then
		co = coroutine_create(function(...)
			f(...)
			while true do
				f = nil
				table_insert(coroutine_pool, co)
				f = coroutine_yield "EXIT"
				f(coroutine_yield())
			end
		end)
	else
		coroutine_resume(co, f)
	end
	return co
end

local fork_queue = {}
local wakeup_session = {}
local sleep_session = {}
local session_id_coroutine = {}
local session_coroutine_id = {}
local session_coroutine_address = {}
local session_response = {}
local unresponse = {}

local watching_service = {}
local watching_session = {}
local dead_service = {}
local error_queue = {}


function pixel.fork(func, ...)
	local args = {...}
	local co = co_create(function()
		func(table_unpack(args))
	end)
	table_insert(fork_queue, co)
	return co
end

function pixel.timeout(t, func)
	local flag = true
	local session = c.command("TIMEOUT", tostring(t))
	assert(session)
	session = tonumber(session)
	local co = co_create(function()
		if flag then func() end
	end)
	assert(session_id_coroutine[session] == nil)
	session_id_coroutine[session] = co
	return function() flag = false end
end

function pixel.sleep(t)
	local session = c.command("TIMEOUT", tostring(t))
	assert(session)
	session = tonumber(session)
	local ok, err = coroutine_yield("SLEEP", session)
	sleep_session[coroutine_running()] = session
	if ok then
		return
	end
	if err == "BREAK" then
		return "BREAK"
	else
		error(err)
	end
end

function pixel.yield()
	return pixel.sleep(0)
end

function pixel.wait(co)
	local session = c.session()
	local ok, err = coroutine_yield("SLEEP", session)
	co = co or coroutine_running()
	sleep_session[co] = nil
	session_id_coroutine[session] = nil
end

function pixel.wakeup(co)
	if sleep_session[co] and wakeup_session[co] == nil then
		wakeup_session[co] = true
		return true
	end
end

local suspend

local function dispatch_wakeup()
	local co = next(wakeup_session)
	if co then
		wakeup_session[co] = nil
		local session = sleep_session[co]
		if session then
			session_id_coroutine[session] = "BREAK"
			return suspend(co, coroutine_resume(co, false, "BREAK"))
		end
	end
end

local function dispatch_error_queue()
	local session = table_remove(error_queue, 1)
	if session then
		local co = session_id_coroutine[session]
		session_id_coroutine[session] = nil
		return suspend(co, coroutine_resume(co, false))
	end
end

local function _error_dispatch(err_session, err_source)
	if err_session == 0 then
		if watching_service[err_source] then
			dead_service[err_source] = true
		end
		for session, srv in pairs(watching_session) do
			if src == err_source then
				table_insert(error_queue, session)
			end
		end
	else
		if watching_session[err_session] then
			table_insert(error_queue, err_session)
		end
	end
end

local function release_watching(address)
	local ref = watching_service[address]
	if ref then
		ref = ref - 1
		if ref > 0 then
			watching_service[address] = ref
		else
			watching_service[address] = nil
		end
	end
end

function suspend(co, ok, command, param, size)
	if not ok then
		local session = session_coroutine_id[co]
		if session then
			local addr = session_coroutine_address[co]
			if session ~= 0 then
				c.send(addr, 0, pixel.PIXEL_ERROR, session, "")
			end
			session_coroutine_id[co] = nil
			session_coroutine_address[co] = nil
		end
		error(debug_traceback(co, command))
	end

	if command == "CALL" then
		session_id_coroutine[param] = co
	elseif command == "SLEEP" then
		session_id_coroutine[param] = co
		sleep_session[co] = param
	elseif command == "RETURN" then
		local co_session = session_coroutine_id[co]
		local co_address = session_coroutine_address[co]
		if param == nil or session_response[co] then
			error(debug_traceback(co))
		end
		session_response[co] = true
		local ret
		if not dead_service[co_address] then
			ret = c.send(co_address, 0, pixel.PIXEL_RESPONSE, co_session, param, size) ~= nil
			if not ret then
				c.send(co_address, 0, pixel.PIXEL_ERROR, co_session, "")
			end
		elseif size ~= nil then
			c.drop(param, size)
			ret = false
		end
		return suspend(co, coroutine_resume(co, ret))
	elseif command == "RESPONSE" then
		local co_session = session_coroutine_id[co]
		local co_address = session_coroutine_address[co]
		if session_response[co] then
			error(debug_traceback(co))
		end
		local f = param
		local function response(ok, ...)
			if ok == "TEST" then
				if dead_service[co_address] then
					release_watching(co_address)
					unresponse[response] = nil
					f = false
					return false
				else
					return true
				end
			end
			if not f then
				if f == false then
					f = nil
					return false
				end
				error("cannot response more then once")
			end
			local ret
			if not dead_service[co_address] then
				if ok then
					ret = c.send(co_address, 0, pixel.PIXEL_RESPONSE, co_session, f(...)) ~= nil
					if not ret then
						c.send(co_address, 0, pixel.PIXEL_ERROR, co_session, "")
					end
				else
					ret = c.send(co_address, 0, pixel.PIXEL_ERROR, co_session, "") ~= nil
				end
			else
				ret = false
			end
			release_watching(co_address)
			unresponse[response] = nil
			f = nil
			return ret
		end
		watching_service[co_address] = watching_service[co_address] + 1
		session_response[co] = true
		unresponse[response] = true
		return suspend(co, coroutine_resume(co, response))
	elseif command == "EXIT" then
		local address = session_coroutine_address[co]
		release_watching(address)
		session_coroutine_id[co] = nil
		session_coroutine_address[co] = nil
		session_response[co] = nil
	elseif command == "QUIT" then
		return
	elseif command == nil then
		return
	else
		error("unknown command:"..command.."\n")
	end
	dispatch_wakeup()
	dispatch_error_queue()
end


local function unknown_request(session, address, msg, sz, prototype)
	pixel.err("Unknown request (%s): %s\n", prototype, c.tostring(msg,sz))
	error(string_format("Unknown session : %d from %u", session, address))
end

function pixel.dispatch_unknown_request(unknown)
	local prev = unknown_request
	unknown_request = unknown
	return prev
end

local function unknown_response(session, address, msg, sz)
	pixel.err("Response message : %s\n" , c.tostring(msg,sz))
	error(string_format("Unknown session : %d from %u", session, address))
end

function pixel.dispatch_unknown_response(unknown)
	local prev = unknown_response
	unknown_response = unknown
	return prev
end


local function _dispatch_message(pid, msg, sz, session, source, ...)
	-- pixel.log("dispatch %s pid:%d, sz:%d, session:%d, source:%d\n", SERVICE_NAME, pid, sz, session, source)
	if pid == pixel.PIXEL_RESPONSE then
		local co = session_id_coroutine[session]
		if co == "BREAK" then
			session_id_coroutine[session] = nil
		elseif co == nil then
			unknown_response(session, source, msg, sz)
		else
			session_id_coroutine[session] = nil
			suspend(co, coroutine_resume(co, true, msg, sz))
		end
	else
		local p = proto[pid]
		if p == nil then
			if session ~= 0 then
				c.send(source, 0, pixel.PIXEL_ERROR, session, "")
			else
				unknown_request(session, source, msg, sz, pid)
			end
			return
		end
		local f = p.dispatch
		if f then
			local ref = watching_service[source]
			if ref then
				watching_service[source] = ref + 1
			else
				watching_service[source] = 1
			end
			local co = co_create(f)
			session_coroutine_id[co] = session
			session_coroutine_address[co] = source
			suspend(co, coroutine_resume(co, session, source, p.unpack(msg, sz, ...)))
		else
			unknown_request(session, source, msg, sz, proto[pid].name)
		end
	end
end

function pixel.dispatch_message(...)
	local ok, err = pcall(_dispatch_message, ...)
	while true do
		local i, co = next(fork_queue)
		if co == nil then
			break
		end
		fork_queue[i] = nil
		local fork_ok, fork_err = pcall(suspend, co, coroutine_resume(co))
		if not fork_ok then
			error(fork_err)
		end
	end
	if not ok then
		pixel.err("%s\n", err)
	end
end

local init_func = {}

function pixel.init(f, name)
	assert(type(f) == "function")
	if init_func == nil then
		f()
	else
		if name == nil then
			table_insert(init_func, f)
		else
			assert(init_func[name] == nil)
			init_func[name] = f
		end
	end
end

local function init_all()
	local funcs = init_func
	init_func = nil
	if funcs then
		for k, v in pairs(funcs) do
			v()
		end
	end
end

local function start(cb)
	pixel.dispatch("service", function(session, source, t, id, ...)
		if t == "init" then
			init_all()
			init_func = {}
			if cb.init then
				cb.init(id, ...)
				cb.init = nil
			end
			local ret = {}
			ret.request = {}
			ret.post = {}
			for i in pairs(cb.request) do
				table_insert(ret.request, i)
			end
			for i in pairs(cb.post) do
				table_insert(ret.post, i)
			end
			pixel.ret(ret)
		elseif t == "request" then
			local args = {session=session,source=source}
			local func = cb.request[id]
			if func then
				pixel.ret(func(args,...))
			end
		elseif t == "post" then
			local args = {session=session,source=source}
			local func = cb.post[id]
			if func then
				func(args,...)
			end
		elseif t == "exit" then
			if cb.exit then
				cb.exit()
				cb.exit = nil
			end
			pixel.ret()
		else
			error("invalid internel cmd:"..t.."\n")
		end
	end)
end

local function init_template(cb)
	start(cb)
end

local function init_service(cb)
	local ok, err = xpcall(init_template, debug_traceback, cb)
	if not ok then
		pixel.err("init service failed:%s\n", err)
		pixel.exit()
	end
end

function pixel.start(cb)
	c.callback(pixel.dispatch_message)
	cb.request = cb.request or {}
	cb.post = cb.post or {}
	pixel.timeout(0, function()
		init_service(cb)
	end)
end

local service_manager

local function get_service_manager()
	if not service_manager then
		service_manager = pixel.query("service_manager")
	end
	return service_manager
end

function pixel.exit()
	pixel.call(pixel.self(), "service", "exit")
	pixel.call(get_service_manager(), "service", "request", "exit", pixel.self())
	fork_queue = {}
	for co, session in pairs(session_coroutine_id) do
		local address = session_coroutine_address[co]
		if session ~= 0 and address then
			c.send(address, 0, pixel.PIXEL_ERROR, session, "")
		end
	end
	for resp in pairs(unresponse) do
		resp(false)
	end
	local tmp = {}
	for session, address in pairs(watching_session) do
		tmp[address] = true
	end
	for address in pairs(tmp) do
		c.send(address, 0, pixel.PIXEL_ERROR, 0, "")
	end
	c.command "KILL"
	coroutine_yield "QUIT"
end

function pixel.abort()
	c.command("ABORT")
end

function pixel.service(name, ...)
	local address = c.command("LAUNCH", table_concat({"lua", name, ...}, " "))
	if not address then
		return nil
	end
	address = tonumber(address)
	pixel.call(get_service_manager(), "service", "request", "launch", address, name, ...)
	return pixel.bind(address, ...)
end

function pixel.bind(address, ...)
	local s = {}
	if type(address) == "string" then
		address = tonumber(pixel.query(address))
	end
	s.address = address
	s.req = {}
	s.post = {}
	local ok, interface = pcall(pixel.call, s.address, "service", "init", ...)
	if not ok then
		return nil
	end
	for _, v in pairs(interface.request) do
		s.req[v] = function(...)
			return pixel.call(s.address, "service", "request", v, ...)
		end
	end
	for _, v in pairs(interface.post) do
		s.post[v] = function(...)
			pixel.send(s.address, "service", "post", v, ...)
		end
	end
	return s
end

local function yield_call(service, session)
	watching_session[session] = service
	local ok, msg, sz = coroutine_yield("CALL", session)
	watching_session[session] = nil
	if not ok then
		error("call failed\n")
	end
	return msg, sz
end

function pixel.rawsend(addr, source, tname, ...)
	local p = proto[tname]
	if type(addr) == "string" then
		addr = tonumber(pixel.query(addr))
	end
	return c.send(addr, source, p.id, ...)
end

function pixel.response(pack)
	pack = pack or pixel.pack
	return coroutine_yield("RESPONSE", pack)
end

function pixel.ret(...)
	local co = coroutine_running()
	if session_response[co] then
		return
	end
	local msg, sz = pixel.pack(...)
	return coroutine_yield("RETURN", msg, sz)
end

function pixel.send(addr, tname, ...)
	local p = proto[tname]
	if type(addr) == "string" then
		addr = tonumber(pixel.query(addr))
	end
	return c.send(addr, 0, p.id, 0, p.pack(...))
end

function pixel.rawcall(addr, source, tname, ...)
	local p = proto[tname]
	if type(addr) == "string" then
		addr = tonumber(pixel.query(addr))
	end
	local session = c.send(addr, source, p.id, ...)
	if session == nil then
		error("call to invalid address " .. addr)
	end
	return yield_call(addr, session)
end

function pixel.call(addr, tname, ...)
	local p = proto[tname]
	if type(addr) == "string" then
		addr = tonumber(pixel.query(addr))
	end
	local session = c.send(addr, 0, p.id, nil, p.pack(...))
	if session == nil then
		error("call to invalid address " .. addr)
	end
	return p.unpack(yield_call(addr, session))
end

function pixel.endless()
	return c.command("ENDLESS")~=nil
end

function pixel.mqlen()
	return tonumber(c.command "MQLEN")
end

function pixel.task(ret)
	local t = 0
	for session,co in pairs(session_id_coroutine) do
		if ret then
			ret[session] = debug_traceback(co)
		end
		t = t + 1
	end
	return t
end

function pixel.term(service)
	return _error_dispatch(0, service)
end

pixel.protocol {
	name = "lua",
	id = pixel.PIXEL_LUA,
	pack = pixel.pack,
	unpack = pixel.unpack
}

pixel.protocol {
	name = "service",
	id = pixel.PIXEL_SERVICE,
	pack = pixel.pack,
	unpack = pixel.unpack
}

pixel.protocol {
	name = "response",
	id = pixel.PIXEL_RESPONSE
}

pixel.protocol {
	name = "error",
	id = pixel.PIXEL_ERROR,
	unpack = function(...) return ... end,
	dispatch = _error_dispatch
}

local debug = require "pixel_debug"
debug(pixel, {
	dispatch = pixel.dispatch_message,
	clear = function()
		coroutine_pool = {}
	end,
	suspend = suspend,
})


return pixel