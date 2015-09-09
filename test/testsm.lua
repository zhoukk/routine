local pixel = require "pixel"
local sharemap = require "sharemap"

function init(mode)

	if mode == "slave" then
		local reader
		local function dump(reader)
			reader:update()
			print("x=", reader.x)
			print("y=", reader.y)
			print("s=", reader.s)
		end
		function request:init(...)
			reader = sharemap.reader(...)
		end

		function request:ping()
			dump(reader)
		end
	else
		-- register share type schema
		sharemap.register("./example/sharemap.sp")
		local slave = pixel.service(SERVICE_NAME, "slave")
		local writer = sharemap.writer("foobar", { x=0,y=0,s="hello" })
		slave.req.init("foobar", writer:copy())
		writer.x = 1
		writer:commit()
		slave.req.ping()
		writer.y = 2
		writer:commit()
		slave.req.ping()
		writer.s = "world"
		writer:commit()
		slave.req.ping()
	end

end