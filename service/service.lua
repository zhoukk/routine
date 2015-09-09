local pixel = require "pixel"

local services = {}
pixel.name "service_manager"

function request:launch(addr, ...)
	local param = table.concat({...}, " ")
	services[addr] = param
end

function request:exit(addr)
	services[addr] = nil
end

function request:list()
	local list = {}
	for k, v in pairs(services) do
		list[k] = v
	end
	return list
end

function request:stat()
	local list = {}
	for k, v in pairs(services) do
		local stat = pixel.call(k, "debug", "STAT")
		list[k] = stat
	end
	return list
end

function request:mem()
	local list = {}
	for k, v in pairs(services) do
		local kb, bytes = pixel.call(k, "debug", "MEM")
		list[k] = string.format("%.2f Kb (%s)", kb, v)
	end
	return list
end

function request:kill(address)
	-- pixel.kill(address)
	local ret = { [address] = tostring(services[address]) }
	services[address] = nil
	return ret
end

function request:gc()
	for k, v in pairs(services) do
		pixel.send(k, "debug", "GC")
	end
	return request:mem()
end