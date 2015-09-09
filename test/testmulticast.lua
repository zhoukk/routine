local pixel = require "pixel"
local mc = require "multicast"

function init(mode)

	if mode == "sub" then
		function request:init(channel)
			local c = mc.new {
				channel = channel ,
				dispatch = function (channel, source, ...)
					print(string.format("%s <=== %s %s",pixel.self(), source, channel), ...)
				end
			}
			print(pixel.self(), "sub", c)
			c:subscribe()
		end
	else
		local dc = pixel.bind("datacenterd")
		local channel = mc.new()
		print("New channel", channel)
		for i=1,10 do
			local sub = pixel.service(SERVICE_NAME, "sub")
			sub.req.init(channel.channel)
		end

		dc.req.set("MCCHANNEL", channel.channel)	-- for multi node test

		print(pixel.self(), "===>", channel)
		channel:publish("Hello World")
	end

end