local pixel = require "pixel"

function init(mode)

	if mode == "slave" then
		pixel.dispatch("lua", function(_,_,...)
			pixel.ret(...)
		end)
	else
		local server = pixel.service(SERVICE_NAME, "slave")
		local slave = server.address
		local n = 100000
		local start = pixel.now()
		print("call salve", n, "times in queue")
		for i=1, n do
			pixel.call(slave, "lua")
		end
		print("qps = ", n/ (pixel.now() - start) * 100)

		start = pixel.now()

		local worker = 10
		local task = n/worker
		print("call salve", n, "times in parallel, worker = ", worker)

		for i=1, worker do
			pixel.fork(function()
				for i=1,task do
					pixel.call(slave, "lua")
				end
				worker = worker -1
				if worker == 0 then
					print("qps = ", n/ (pixel.now() - start) * 100)
				end
			end)
		end
	end
end