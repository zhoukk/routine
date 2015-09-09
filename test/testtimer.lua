local pixel = require "pixel"

local function timeout(t)
	print(t)
end

local function wakeup(co)
	for i=1,5 do
		pixel.sleep(50)
		pixel.wakeup(co)
	end
end

local function test()
	pixel.timeout(10, function() print("test timeout 10") end)
	for i=1,10 do
		print("test sleep",i,pixel.now())
		pixel.sleep(1)
	end
end

function init()
	test()

	pixel.fork(wakeup, coroutine.running())
	pixel.timeout(300, function() timeout "Hello World" end)
	for i = 1, 10 do
		print(i, pixel.now())
		print(pixel.sleep(100))
	end
	pixel.exit()
	print("Test timer exit")
end

