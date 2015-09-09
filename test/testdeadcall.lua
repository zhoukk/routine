local pixel = require "pixel"

function init(mode)

	if mode == "test" then
		pixel.dispatch("lua", function (...)
			print("====>", ...)
			pixel.exit()
		end)
	elseif mode == "dead" then
		pixel.dispatch("lua", function (...)
			pixel.sleep(100)
			print("return", pixel.ret "")
		end)
	else
		local test = pixel.service(SERVICE_NAME, "test")	-- launch self in test mode
		print(pcall(function() pixel.call(test.address,"lua", "dead call") end))
		local dead = pixel.service(SERVICE_NAME, "dead")	-- launch self in dead mode
		pixel.timeout(0, pixel.exit)	-- exit after a while, so the call never return
		pixel.call(dead.address, "lua", "whould not return")
	end

end
