local pixel = require "pixel"
local sharedata = require "sharedata"

function init(mode)

	if mode == "host" then
		pixel.log("new foobar\n")
		sharedata.new("foobar", { a=1, b= { "hello",  "world" } })

		pixel.fork(function()
			pixel.sleep(200)	-- sleep 2s
			pixel.log("update foobar a = 2\n")
			sharedata.update("foobar", { a =2 })
			pixel.sleep(200)	-- sleep 2s
			pixel.log("update foobar a = 3\n")
			sharedata.update("foobar", { a = 3, b = { "change" } })
			pixel.sleep(100)
			pixel.log("delete foobar\n")
			sharedata.delete "foobar"
		end)
	else
		pixel.service(SERVICE_NAME, "host")

		local obj = sharedata.query "foobar"
		local b = obj.b
		pixel.log("a=%d\n", obj.a)

		for k,v in ipairs(b) do
			pixel.log("b[%d]=%s\n", k,v)
		end
		
		-- test lua serialization
		local nobj = pixel.unpack(pixel.pack(obj))
		for k,v in pairs(nobj.b) do
			pixel.log("nobj[%s]=%s\n", k,v)
		end
		for k,v in ipairs(nobj) do
			pixel.log("nobj.b[%d]=%s\n", k,v)
		end

		for i = 1, 5 do
			pixel.sleep(100)
			pixel.log("second " ..i.."\n")
			for k,v in pairs(obj) do
				pixel.log("%s = %s\n", k , tostring(v))
			end
		end

		local ok, err = pcall(function()
			local tmp = { b[1], b[2] }	-- b is invalid , so pcall should failed
		end)

		if not ok then
			pixel.log(err.."\n")
		end

		-- obj. b is not the same with local b
		for k,v in ipairs(obj.b) do
			pixel.log("b[%d] = %s\n", k , tostring(v))
		end

		collectgarbage()
		pixel.log("sleep\n")
		pixel.sleep(100)
		b = nil
		collectgarbage()
		pixel.log("sleep\n")
		pixel.sleep(100)

		pixel.exit()
	end
end