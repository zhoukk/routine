local pixel = require "pixel"

local db = {}

function init()
	pixel.name "SIMPLEDB"
end

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
