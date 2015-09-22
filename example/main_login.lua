local pixel = require "pixel"

function init()
	pixel.log("Server start\n")
	pixel.service "console"
	pixel.service "protoloader"

	local gate = pixel.service("gated")
	gate.req.open {
		port = 8001,
		maxclient = 64,
		servername = "sample",
	}

	pixel.exit()
end
