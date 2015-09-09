local pixel = require "pixel"
local sd = require "sharedata_corelib"

local service

pixel.init(function()
	local service_address = pixel.query("sharedatad")
	if not service_address then
		service = pixel.service "sharedatad"
	else
		service = pixel.bind(service_address)
	end
end)

local sharedata = {}

local function monitor(name, obj, cobj)
	local newobj = cobj
	while true do
		newobj = service.req.monitor(name, newobj)
		if newobj == nil then
			break
		end
		sd.update(obj, newobj)
	end
end

function sharedata.query(name)
	local obj = service.req.query(name)
	local r = sd.box(obj)
	service.post.confirm(obj)
	pixel.fork(monitor, name, r, obj)
	return r
end

function sharedata.new(name, v)
	service.req.new(name, v)
end

function sharedata.update(name, v)
	service.req.update(name, v)
end

function sharedata.delete(name)
	service.req.delete(name)
end

return sharedata
