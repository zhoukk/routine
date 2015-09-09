local pixel = require "pixel"
local socket = require "socket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local table = table
local string = string

function init(mode)
	if mode == "agent" then

		local function response(id, ...)
			local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
			if not ok then
				-- if err == sockethelper.socket_error , that means socket closed.
				pixel.err("fd = %d, %s\n", id, err)
			end
		end

		function post:attach(id)
			socket.start(id)
			-- limit request body size to 8192 (you can pass nil to unlimit)
			local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8192)
			if code then
				if code ~= 200 then
					response(id, code)
				else
					local tmp = {}
					if header.host then
						table.insert(tmp, string.format("host: %s", header.host))
					end
					local path, query = urllib.parse(url)
					table.insert(tmp, string.format("path: %s", path))
					if query then
						local q = urllib.parse_query(query)
						for k, v in pairs(q) do
							table.insert(tmp, string.format("query: %s=%s", k,v))
						end
					end
					table.insert(tmp, "-----header----")
					for k,v in pairs(header) do
						table.insert(tmp, string.format("%s = %s",k,v))
					end
					table.insert(tmp, "-----body----\n" .. body)
					response(id, code, table.concat(tmp,"\n"))
				end
			else
				if url == sockethelper.socket_error then
					pixel.err("socket closed\n")
				else
					pixel.log(url.."\n")
				end
			end
			socket.close(id)
		end

	else

		local agent = {}
		for i= 1, 4 do
			agent[i] = pixel.service(SERVICE_NAME, "agent")
		end
		local balance = 1
		local listen = socket.listen("0.0.0.0", 8080)
		pixel.log("Listen web port 8080\n")
		socket.start(listen , function(id, addr)
			pixel.log("%s connected, pass it to agent :%d\n", addr, agent[balance].address)
			agent[balance].post.attach(id)
			balance = balance + 1
			if balance > #agent then
				balance = 1
			end
		end)

		function exit()
			if listen >= 0 then
				socket.close(listen)
			end
		end
		
	end
end