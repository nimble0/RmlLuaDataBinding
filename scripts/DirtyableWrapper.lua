local data_binding = require("data_binding")
local reference = require("reference")


local dirtyableWrappers = {}
local WeakKeyTable = { __mode = "k" }
setmetatable(dirtyableWrappers, WeakKeyTable)

-- Unique keys to prevent conflicting with other keys in index metamethod
local __REF = {}
local __BASE = {}

local FunctionWrapper = {}
function FunctionWrapper:new(self, realSelf, f)
	local o = {}
	o.self = self
	o.realSelf = realSelf
	o.f = f
	setmetatable(o, self)
	return o
end
function FunctionWrapper:__call(...)
	local first = select(1, ...)
	-- Check if method call
	if first == self.self then
		return f(self.realSelf, select(2, ...))
	end

	return f(...)
end

local DirtyableWrapper = {}
function DirtyableWrapper:new(ref, base)
	assert(reference.Reference.is(ref) and base ~= nil)

	local existing = dirtyableWrappers[ref]
	if existing then
		existing[__BASE] = base
		return existing
	end

	local o = {}
	o[__REF] = ref
	o[__BASE] = base
	setmetatable(o, DirtyableWrapper)
	dirtyableWrappers[ref] = o
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
	local mt = getmetatable(v) or {}
	if vType == "function" or mt.__call then
		return FunctionWrapper:new(self, self[__BASE], v)
	elseif (vType == "table" or vType == "userdata") and not mt.__noDirtyableWrapper then
		return DirtyableWrapper:new(self[__REF][k], v)
	else
		return v
	end
end
function DirtyableWrapper:__newindex(k, v)
	self[__BASE][k] = v
	reference.dirty_variable(self[__REF][k])
end

function DirtyableWrapper:__tostring()
	return table.concat({"DirtyableWrapper(", tostring(self[__BASE]), ")"})
end

return DirtyableWrapper
