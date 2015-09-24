local pixel = require "pixel"

function init()
	pixel.log("Server start\n")
	pixel.service "console"
	pixel.service("debug_console", 6000)
	pixel.service "protoloader"

	local gate = pixel.service("gated")
	gate.req.open {
		port = 8001,
		maxclient = 64,
		servername = "sample",
	}
	local db = pixel.bind("SIMPLEDB")
	db.req.set("gate", gate.address)
	pixel.exit()
end
