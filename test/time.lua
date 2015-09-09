local pixel = require "pixel"

function init()
	print(pixel.starttime())
	print(pixel.now())
	print(pixel.time())

	pixel.timeout(1, function()
		print("in 1", pixel.now())
	end)
	pixel.timeout(2, function()
		print("in 2", pixel.now())
	end)
	pixel.timeout(3, function()
		print("in 3", pixel.now())
	end)

	pixel.timeout(4, function()
		print("in 4", pixel.now())
	end)
	pixel.timeout(100, function()
		print("in 100", pixel.now())
	end)
end