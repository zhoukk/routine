local pixel = require "pixel"

local db = {}

pixel.name "SIMPLEDB"

function exit()
	db = nil
end

function request:set(key, val)
	local last = db[key]
	db[key] = val
	return last
end

function request:get(key)
	return db[key]
end
