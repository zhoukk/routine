local args = {}
for word in string.gmatch(..., "%S+") do
	table.insert(args, word)
end

SERVICE_NAME = args[1]

local err = {}
for pat in string.gmatch(LUA_SERVICE, "([^;]+);*") do
	local filename = string.gsub(pat, "?", SERVICE_NAME)
	local f, msg = loadfile(filename)
	if not f then
		table.insert(err, msg)
	else
		main = f
		break
	end
end

package.path = LUA_PATH
package.cpath = LUA_CPATH

if not main then
	error(table.concat(err, "\n"))
end

request = {}
post = {}
main(select(2, table.unpack(args)))

local pixel = require "pixel"
pixel.start {
	init = init,
	exit = exit,
	request = request,
	post = post,
}