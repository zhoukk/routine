local pixel = require "pixel"

function init(mode)

	if mode == "slave" then
		function post:sum(n)
			pixel.err("for loop begin\n")
			local s = 0
			for i = 1, n do
				s = s + i
			end
			pixel.err("for loop end\n")
		end

		function post:blackhole()

		end
	else
		local slave = pixel.service(SERVICE_NAME, "slave")
		for step = 1, 20 do
			pixel.err("overload test "..step.."\n")
			for i = 1, 512 * step do
				slave.post.blackhole()
			end
			pixel.sleep(step)
		end
		local n = 1000000000
		pixel.err("endless test n=%d\n", n)
		slave.post.sum(n)
	end
	
end