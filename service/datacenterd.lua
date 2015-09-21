local pixel = require "pixel"

local database = {}
local wait_queue = {}
local mode = {}

function init()
	pixel.name "DATACENTERD"
end

local function query(db, key, ...)
	if key == nil then
		return db
	else
		return query(db[key], ...)
	end
end

function request:get(key, ...)
	local d = database[key]
	if d then
		return query(d, ...)
	end
end

local function update(db, key, val, ...)
	if select("#", ...) == 0 then
		local ret = db[key]
		db[key] = val
		return ret, val
	else
		if db[key] == nil then
			db[key] = {}
		end
		return update(db[key], val, ...)
	end
end

local function wakeup(db, key, ...)
	if key == nil then
		return
	end
	local q = db[key]
	if q == nil then
		return
	end
	if q[mode] == "queue" then
		db[key] = nil
		if select("#", ...) ~= 1 then
			for _, response in ipairs(q) do
				response(false)
			end
		else
			return q
		end
	else
		return wakeup(q, ...)
	end
end

function request:set(...)
	local ret, val = update(database, ...)
	if ret or val == nil then
		return ret
	end
	local q = wakeup(wait_queue, ...)
	if q then
		for _, response in ipairs(q) do
			response(true, val)
		end
	end
end

local function waitfor(db, key1, key2, ...)
	if key2 == nil then
		local q = db[key1]
		if q == nil then
			q = {[mode] = "queue"}
			db[key1] = q
		else
			assert(q[mode] == "queue")
		end
		table.insert(q, pixel.response())
	else
		local q = db[key1]
		if q == nil then
			q = {[mode] = "branch"}
			db[key1] = q
		else
			assert(q[mode] == "branch")
		end
		return waitfor(q, key2, ...)
	end
end

function request:wait(...)
	local ret = request:get(...)
	if ret then
		return ret
	else
		waitfor(wait_queue, ...)
	end
end