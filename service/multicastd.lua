local pixel = require "pixel"
local mc = require "multicast.core"
local datacenterd

local harbor_id = pixel.harbor(pixel.self())
local channel = {}
local channel_n = {}
local channel_remote = {}
local channel_id = harbor_id

local function get_address(t, id)
	local v = assert(datacenterd.req.get("multicast", id))
	v = pixel.bind(v)
	t[id] = v
	return v
end

local node_address = setmetatable({}, { __index = get_address })

-- new LOCAL channel , The low 8bit is the same with harbor_id
function request:NEW()
	while channel[channel_id] do
		channel_id = mc.nextid(channel_id)
	end
	channel[channel_id] = {}
	channel_n[channel_id] = 0
	local ret = channel_id
	channel_id = mc.nextid(channel_id)
	return ret
end

-- MUST call by the owner node of channel, delete a remote channel
function post:DELR(c)
	channel[c] = nil
	channel_n[c] = nil
end

-- delete a channel, if the channel is remote, forward the command to the owner node
-- otherwise, delete the channel, and call all the remote node, DELR
function post:DEL(c)
	local node = c % 256
	if node ~= harbor_id then
		node_address[node].post.DEL(c)
		return
	end
	local remote = channel_remote[c]
	channel[c] = nil
	channel_n[c] = nil
	channel_remote[c] = nil
	if remote then
		for node in pairs(remote) do
			node_address[node].post.DELR(c)
		end
	end
end

-- forward multicast message to a node (channel id use the session field)
local function remote_publish(node, channel, source, ...)
	pixel.rawsend(node_address[node].address, source, "multicast", channel, ...)
end

-- publish a message, for local node, use the message pointer (call mc.bind to add the reference)
-- for remote node, call remote_publish. (call mc.unpack and pixel.tostring to convert message pointer to string)
local function publish(c , source, pack, size)
	local group = channel[c]
	if group == nil then
		-- dead channel, delete the pack. mc.bind returns the pointer in pack
		local pack = mc.bind(pack, 1)
		mc.close(pack)
		return
	end
	mc.bind(pack, channel_n[c])
	local msg = pixel.tostring(pack, size)
	for k in pairs(group) do
		-- the msg is a pointer to the real message, publish pointer in local is ok.
		pixel.rawsend(k, source, "multicast", c, msg)
	end
	local remote = channel_remote[c]
	if remote then
		-- remote publish should unpack the pack, because we should not publish the pointer out.
		local _, msg, sz = mc.unpack(pack, size)
		local msg = pixel.tostring(msg,sz)
		for node in pairs(remote) do
			remote_publish(node, c, source, msg)
		end
	end
end

pixel.protocol {
	name = "multicast",
	id = pixel.PIXEL_MULTICAST,
	unpack = function(msg, sz)
		return mc.packremote(msg, sz)
	end,
	dispatch = publish,
}

-- publish a message, if the caller is remote, forward the message to the owner node (by remote_publish)
-- If the caller is local, call publish
function request:PUB(c, pack, size)
	local source = self.source
	assert(pixel.harbor(source) == harbor_id)
	local node = c % 256
	if node ~= harbor_id then
		-- remote publish
		remote_publish(node, c, source, mc.remote(pack))
	else
		publish(c, source, pack,size)
	end
end

-- the node (source) subscribe a channel
-- MUST call by channel owner node (assert source is not local and channel is create by self)
-- If channel is not exist, return true
-- Else set channel_remote[channel] true
function request:SUBR(c)
	local source = self.source
	local node = pixel.harbor(source)
	if not channel[c] then
		-- channel none exist
		return true
	end
	assert(node ~= harbor_id and c % 256 == harbor_id)
	local group = channel_remote[c]
	if group == nil then
		group = {}
		channel_remote[c] = group
	end
	group[node] = true
end

-- the service (source) subscribe a channel
-- If the channel is remote, node subscribe it by send a SUBR to the owner .
function request:SUB(c)
	local source = self.source
	local node = c % 256
	if node ~= harbor_id then
		-- remote group
		if channel[c] == nil then
			if node_address[node].req.SUBR(c) then
				return
			end
			if channel[c] == nil then
				-- double check, because pixel.call whould yield, other SUB may occur.
				channel[c] = {}
				channel_n[c] = 0
			end
		end
	end
	local group = channel[c]
	if group and not group[source] then
		channel_n[c] = channel_n[c] + 1
		group[source] = true
	end
end

-- MUST call by a node, unsubscribe a channel
function post:USUBR(c)
	local source = self.source
	local node = pixel.harbor(source)
	assert(node ~= harbor_id)
	local group = assert(channel_remote[c])
	group[node] = nil
end

-- Unsubscribe a channel, if the subscriber is empty and the channel is remote, send USUBR to the channel owner
function post:USUB(c)
	local source = self.source
	local group = assert(channel[c])
	if group[source] then
		group[source] = nil
		channel_n[c] = channel_n[c] - 1
		if channel_n[c] == 0 then
			local node = c % 256
			if node ~= harbor_id then
				-- remote group
				channel[c] = nil
				channel_n[c] = nil
				node_address[node].post.USUBR(c)
			end
		end
	end
end

function init()
	datacenterd = pixel.bind("DATACENTERD")
	local self = pixel.self()
	local id = pixel.harbor(self)
	assert(datacenterd.req.set("multicast", id, self) == nil)
	pixel.name "multicastd"
end

