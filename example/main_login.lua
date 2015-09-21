local pixel = require "pixel"

function init()
	pixel.log("Server start\n")
	pixel.service "console"
	pixel.service "protoloader"
	pixel.service "simpledb"

	local datacenter = pixel.bind("DATACENTERD")
	datacenter.req.set("a","b")

	pixel.exit()
end
