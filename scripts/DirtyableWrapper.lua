local data_binding = require("data_binding")
local reference = require("data_binding_reference")


local dirtyableWrappers = {}
local WeakKeyTable = { __mode = "k" }
setmetatable(dirtyableWrappers, WeakKeyTable)

-- Unique keys to prevent conflicting with other keys in index metamethod
local __BASE = {}

local DirtyableWrapper = {}
function DirtyableWrapper:new(v)
	if dirtyableWrappers[v] then
		return dirtyableWrappers[v]
	end

	local o = {}
	o[__BASE] = v
	data_binding.make_container_dirtyable(o)
	setmetatable(o, DirtyableWrapper)
	dirtyableWrappers[v] = o
	return o
end

function DirtyableWrapper:__add(b)
	return self[__BASE] + b
end
function DirtyableWrapper:__sub(b)
	return self[__BASE] - b
end
function DirtyableWrapper:__mul(b)
	return self[__BASE] * b
end
function DirtyableWrapper:__div(b)
	return self[__BASE] / b
end
function DirtyableWrapper:__unm()
	return -self[__BASE]
end
function DirtyableWrapper:__pow(b)
	return self[__BASE] ^ b
end
function DirtyableWrapper:__concat(b)
	return self[__BASE] .. b
end
function DirtyableWrapper:__eq(b)
	return self[__BASE] == b
end
function DirtyableWrapper:__lt(b)
	return self[__BASE] < b
end
function DirtyableWrapper:__le(b)
	return self[__BASE] <= b
end
function DirtyableWrapper:__len()
	return #self[__BASE]
end

function DirtyableWrapper:__index(k)
	local v = self[__BASE][k]
	local vType = type(v)
	if vType == "table" or vType == "userdata" then
		return DirtyableWrapper:new(v)
	else
		return v
	end
end
function DirtyableWrapper:__newindex(k, v)
	self[__BASE][k] = v
	data_binding.dirty_variable(reference.R(self)[k])
end

return DirtyableWrapper
