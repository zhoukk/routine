local pixel = require "pixel"
local socket = require "socket"

function init()
	pixel.fork(function()
		local stdin = socket.stdin()
		socket.lock(stdin)
		while true do
			local cmdline = socket.readline(stdin, "\n")
			if cmdline ~= "" then
				cmdline = cmdline.." "
				local args = {}
				for m in cmdline:gmatch("(.-) ") do
					table.insert(args, m)
				end
				pcall(pixel.service, args[1], table.unpack(args, 2))
			end
		end
		socket.unlock(stdin)
	end)
end