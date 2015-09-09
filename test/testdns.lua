local pixel = require "pixel"
local dns = require "dns"

function init(dns_server)
	dns_server = dns_server or "114.114.114.114"
	print("nameserver:", dns.server(dns_server, 53))	-- set nameserver
	-- you can specify the server like dns.server("8.8.4.4", 53)
	local ip, ips = dns.resolve "github.com"
	print(ip)
	for k,v in ipairs(ips) do
		print("github.com",v)
	end
	pixel.exit()
end