local pixel = require "pixel"

function init()
	pixel.service "service"
	local standalone = pixel.getenv "standalone"
	if standalone then
		pixel.service "master"
	end
	pixel.service "harbor"

	if standalone then
		pixel.service "datacenterd"
	end
	pcall(pixel.service(pixel.getenv "start" or "main"))
	pixel.exit()
end

pixel.fork(function()
	pixel.call(pixel.self(), "service", "init")
end)