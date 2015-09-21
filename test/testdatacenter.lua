local pixel = require "pixel"

local datacenterd

local function f1()
	print("====1==== wait hello")
	print("\t1>",datacenterd.req.wait ("hello"))
	print("====1==== wait key.foobar")
	print("\t1>", pcall(datacenterd.req.wait,"key"))	-- will failed, because "key" is a branch
	print("\t1>",datacenterd.req.wait ("key", "foobar"))
end

local function f2()
	pixel.sleep(10)
	print("====2==== set key.foobar")
	datacenterd.req.set("key", "foobar", "bingo")
end

function init()
	datacenterd = pixel.bind("DATACENTERD")
	datacenterd.req.set("hello", "world")
	print(datacenterd.req.get "hello")

	pixel.fork(f1)
	pixel.fork(f2)
end