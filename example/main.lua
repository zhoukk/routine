local pixel = require "pixel"

function init()
	pixel.log("Server start\n")
	pixel.service "console"
	pixel.service("debug_console", 6000)
	pixel.service "protoloader"
	pixel.service "simpleweb"
	pixel.service "simpledb"

	pixel.service("logind", 8000)

	pixel.exit()
end
