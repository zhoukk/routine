local io = io
local table = table
local debug = debug

return function (pixel, export)

local internal_info_func

function pixel.info_func(func)
	internal_info_func = func
end

local dbgcmd = {}

function dbgcmd.MEM()
	local kb, bytes = collectgarbage "count"
	pixel.ret(kb,bytes)
end

function dbgcmd.GC()
	export.clear()
	collectgarbage "collect"
end

function dbgcmd.STAT()
	local stat = {}
	stat.mqlen = pixel.mqlen()
	stat.task = pixel.task()
	pixel.ret(stat)
end

function dbgcmd.TASK()
	local task = {}
	pixel.task(task)
	pixel.ret(task)
end

function dbgcmd.INFO()
	if internal_info_func then
		pixel.ret(internal_info_func())
	else
		pixel.ret(nil)
	end
end

function dbgcmd.EXIT()
	pixel.exit()
end

function dbgcmd.RUN(source, filename)
	local inject = require "pixel.inject"
	local output = inject(pixel, source, filename , export.dispatch, pixel.protocol)
	collectgarbage "collect"
	pixel.ret(table.concat(output, "\n"))
end

function dbgcmd.TERM(service)
	pixel.term(service)
end

function dbgcmd.REMOTEDEBUG(...)
	local remotedebug = require "pixel.remotedebug"
	remotedebug.start(export, ...)
end

local function _debug_dispatch(session, address, cmd, ...)
	local f = dbgcmd[cmd]
	assert(f, cmd)
	f(...)
end

pixel.protocol {
	name = "debug",
	id = assert(pixel.PIXEL_DEBUG),
	pack = assert(pixel.pack),
	unpack = assert(pixel.unpack),
	dispatch = _debug_dispatch,
}

end
