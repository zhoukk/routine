local pixel = require "pixel"
local stm = require "stm"

function init(mode)

	if mode == "slave" then
		function request:dump(obj)
			local obj = stm.newcopy(obj)
			print("read:", obj(pixel.unpack))
			pixel.ret()
			pixel.log("sleep and read\n")
			for i=1,10 do
				pixel.sleep(10)
				print("read:", obj(pixel.unpack))
			end
			pixel.exit()
		end
	else
		local slave = pixel.service(SERVICE_NAME, "slave")
		local obj = stm.new(pixel.pack(1,2,3,4,5))
		local copy = stm.copy(obj)
		slave.req.dump(copy)
		for i=1,5 do
			pixel.sleep(20)
			print("write", i)
			obj(pixel.pack("hello world", i))
		end
		pixel.exit()
	end

end