local pixel = require "pixel"
local httpc = require "http.httpc"
local dns = require "dns"

function init()
	print("GET baidu.com")
	local respheader = {}
	local status, body = httpc.get("baidu.com", "/", respheader)
	print("[header] =====>")
	for k,v in pairs(respheader) do
		print(k,v)
	end
	print("[body] =====>", status)
	print(body)

	local respheader = {}
	dns.server("114.114.114.114", 53)
	local ip = dns.resolve "baidu.com"
	print(string.format("GET %s (baidu.com)", ip))
	local status, body = httpc.get("baidu.com", "/", respheader, { host = "baidu.com" })
	print(status)

	pixel.exit()
end