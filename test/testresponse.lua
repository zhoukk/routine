local pixel = require "pixel"

-- this service whould response the request every 1s.

local response_queue = {}

local function response()
	while true do
		pixel.sleep(100)	-- sleep 1s
		for k,v in ipairs(response_queue) do
			v(true, pixel.now())		-- true means succ, false means error
			response_queue[k] = nil
		end
	end
end

local function request(tick, i)
	print(i, "call", pixel.now())
	print(i, "response", pixel.call(tick.address, "lua"))
	print(i, "end", pixel.now())
end

function init(mode)
	if mode == "TICK" then
		pixel.fork(response)
		pixel.dispatch("lua", function()
			table.insert(response_queue, pixel.response())
		end)
	else
		local tick = pixel.service(SERVICE_NAME, "TICK")
		for i=1,5 do
			pixel.fork(request, tick, i)
			pixel.sleep(10)
		end
	end
end