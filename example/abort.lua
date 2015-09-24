local pixel = require "pixel"

function init()
	local db = pixel.bind("SIMPLEDB")
	local address = db.req.get("gate")
	if address then
		db.req.set("gate", nil)
		local gate = pixel.bind(address)
		gate.req.close()
	end
	pixel.abort()
end


