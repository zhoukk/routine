local pixel = require "pixel"

local function dead_loop()
    while true do
        pixel.sleep(0)
    end
end

function init()
	pixel.fork(dead_loop)
end