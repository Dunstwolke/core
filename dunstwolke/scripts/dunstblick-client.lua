local Socket = require "socket"

local MSGType = {
	uploadResource = 1, -- (rid, kind, data)
	addOrUpdateObject = 2, -- (obj)
	removeObject = 3, -- (oid)
	setView = 4, -- (rid)
	setRoot = 5, -- (oid)
	setProperty = 6, -- (oid, name, value) // "unsafe command", uses the serverside object type or fails of property does not exist
	clear = 7, -- (oid, name)
	insertRange = 8, -- (oid, name, index, count, value …) // manipulate lists
	removeRange = 9, -- (oid, name, index, count) // manipulate lists
	moveRange = 10, -- (oid, name, indexFrom, indexTo, count) // manipulate lists
}

local ResourceKind = {
	layout  = 0,
	bitmap  = 1,
	drawing = 2,
}

local sock = assert(Socket.tcp())

assert(sock:connect("127.0.0.1", "1309"))

function send_packet(payload)
	assert(type(payload) == "string")
	
	local prefix = string.char(
		(#payload >> 0) & 0xFF,
		(#payload >> 8) & 0xFF,
		(#payload >> 16) & 0xFF,
		(#payload >> 24) & 0xFF
	)
	
	local msg = prefix .. payload

	local off = 0
	while off < #msg do
		off = sock:send(msg, off)
	end
end

local function slurp(file)
	local f = assert(io.open(file, "rb"))
	local c = f:read("*all")
	f:close()
	return c
end

local function makeVarint(i)
	local str = ""
	while true do
		local c = i & 0x7F
		i = i >> 7
		if i ~= 0 then
			c = c | 0x80
		end
		str = str .. string.char(c)
		if i == 0 then
			break
		end
	end
	return str:reverse()
end

function uploadResource(id, kind, fileName)
	send_packet(
		   string.char(MSGType.uploadResource)
		.. makeVarint(id)
		.. string.char(kind)
		.. slurp(fileName)
	)
end

function setView(id)
	send_packet(
		   string.char(MSGType.setView)
		.. makeVarint(id)
	)
end

function setRoot(id)
	send_packet(
		   string.char(MSGType.setRoot)
		.. makeVarint(id)
	)
end

function removeObject(id)
	send_packet(
		   string.char(MSGType.removeObject)
		.. makeVarint(id)
	)
end

uploadResource(1, ResourceKind.layout, "/tmp/layout.bin")


setView(1)

sock:close()
