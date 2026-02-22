local set = require("set")

local module = {}

local WeakTable = { __mode = "kv" }
local WeakKeyTable = { __mode = "k" }

-- Unique keys to prevent conflicting with other keys in index metamethod
local __ROOT = {}
local __KEYS = {}

local dirtyListeners = {}
local accessListeners = {}


local function dirty_variable(ref)
	for i = 1, #dirtyListeners do
		dirtyListeners[i](ref)
	end
end

local function set_variable(ref, value)
	local container = ref[__ROOT]
	local keys = ref[__KEYS]
	for i = 1, #keys - 1 do
		local part = keys[i]
		local inside = container[part]
		if inside then
			container = inside
		else
			container[part] = {}
			container = container[part]
		end
	end
	local key = keys[#keys]

	if container[key] ~= value then
		container[key] = value
		dirty_variable(ref)
	end
end


-- Dereference with length (#) operator to make a binding dependent on variable
-- and ancestor variables.
-- Index to create a Reference to a descendent variable
local ReferenceMt = {}
local Reference = {}
function Reference:new(root, keys)
	assert(root ~= nil and keys ~= nil)

	local o = {}
	o[__ROOT] = root
	o[__KEYS] = keys
	setmetatable(o, ReferenceMt)
	return o
end

function ReferenceMt:__index(k)
	local keys = self[__KEYS]
	local keysCopy = {}
	for i = 1, #keys do
		keysCopy[i] = keys[i]
	end
	table.insert(keysCopy, k)
	return Reference:new(self[__ROOT], keysCopy)
end

function ReferenceMt:__newindex(k, v)
	local container = self[__ROOT]
	local keys = self[__KEYS]
	for i = 1, #keys do
		container = container[keys[i]]
	end

	dirty_variable(self[k])
	container[k] = v
end

function ReferenceMt:__tostring()
	local container = self[__ROOT]
	local keys = self[__KEYS]

	local parts = { tostring(container) }
	for i = 1, #keys do
		table.insert(parts, tostring(keys[i]))
	end

	return table.concat(parts, ".")
end

function ReferenceMt:__eq(b)
	local container = self[__ROOT]
	local keys = self[__KEYS]
	local bContainer = b[__ROOT]
	local bKeys = b[__KEYS]

	if container ~= bContainer or #keys ~= #bKeys then
		return false
	end
	for i = 1, #keys do
		if keys[i] ~= bKeys[i] then
			return false
		end
	end

	return true
end

function ReferenceMt:dereference()
	for i = 1, #accessListeners do
		accessListeners[i](self)
	end

	local container = self[__ROOT]
	local keys = self[__KEYS]
	for i = 1, #keys do
		local key = keys[i]
		container = container[key]
		if container == nil then
			return nil
		end
	end
	return container
end

-- Return underlying value and mark as a dependency
function ReferenceMt:__len()
	return ReferenceMt.dereference(self)
end

function ReferenceMt:__call(...)
	local f = ReferenceMt.dereference(self)
	local first = select(1, ...)
	-- Check if method call
	if Reference.is(first) then
		local keys = self[__KEYS]
		local parentKeys = {}
		for i = 1, #keys - 1 do
			table.insert(parentKeys, keys[i])
		end
		local parent = Reference:new(self[__ROOT], parentKeys)

		if first == parent then
			-- Replace reference self with dereferenced self
			-- Dereference parent manually to avoid extra triggering access listeners
			-- for both method and parent
			local container = self[__ROOT]
			local keys = self[__KEYS]
			for i = 1, #keys - 1 do
				local key = keys[i]
				container = container[key]
				if container == nil then
					break
				end
			end
			return f(container, select(2, ...))
		end
	end

	return f(...)
end

function Reference.is(ref)
	return getmetatable(ref) == ReferenceMt
end

function Reference.get_root(ref)
	return ref[__ROOT]
end

function Reference.get_keys(ref)
	return ref[__KEYS]
end

local function is_reference(ref)
	return getmetatable(ref) == ReferenceMt
end


-- Can't be dereferenced, only indexed to create a Reference
local HalfReferenceMt = {}
local HalfReference = {}
function HalfReference:new(container)
	local o = {}
	setmetatable(o, HalfReferenceMt)
	rawset(o, __ROOT, container)
	return o
end

function HalfReferenceMt:__index(k)
	return Reference:new(rawget(self, __ROOT), {k})
end

function HalfReferenceMt:__newindex(k, v)
	local container = self[__ROOT]
	dirty_variable(self[k])
	container[k] = v
end

function HalfReferenceMt:dereference() end

local _G_HalfReference = HalfReference:new(_G)
local R = {}
setmetatable(R, R)
function R:__index(k)
	return _G_HalfReference[k]
end
function R:__call(r)
	return HalfReference:new(r)
end


-- Can be dereferenced like a Reference but doesn't have any of the other Reference functionality.
-- Exists just to ease binding syntax.
local FakeReferenceMt = {}
local FakeReference = {}
function FakeReference:new(value)
	local o = {}
	o.value = value
	setmetatable(o, FakeReferenceMt)
	return o
end

function FakeReferenceMt:dereference()
	return self.value
end

function FakeReferenceMt:__len()
	return FakeReferenceMt.dereference(self)
end

function FakeReference.is(ref)
	return getmetatable(ref) == FakeReferenceMt
end


module.R = R
module.Reference = Reference
module.HalfReference = HalfReference
module.FakeReference = FakeReference
module.dirty_variable = dirty_variable
module.set_variable = set_variable
module.add_dirty_listener = function(l) set.insert(dirtyListeners, l) end
module.remove_dirty_listener = function(l) set.remove(dirtyListeners, l) end
module.add_access_listener = function(l) set.insert(accessListeners, l) end
module.remove_access_listener = function(l) set.remove(accessListeners, l) end

return module
