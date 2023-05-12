local module = {}

local function set_insert(t, v)
	for i = 1, #t do
		if t[i] == v then
			return
		end
	end
	table.insert(t, v)
end

local function set_remove(t, v)
	for i = 1, #t do
		if t[i] == v then
			table.remove(t, i)
			return
		end
	end
end


local WeakTable = { __mode = "kv" }
local WeakKeyTable = { __mode = "k" }

-- dependents layout
-- {
-- 	container
-- 	{
-- 		key
-- 		{
-- 			bindings
-- 			{
-- 				binding
-- 			}
-- 		}
-- 	}
-- }
local dependents = {}
setmetatable(dependents, WeakKeyTable)

-- Unique keys to prevent conflicting with other keys in index metamethod
local __PARENT = {}
local __CONTAINER = {}
local __KEY = {}
local __ROOT = {}
local __KEYS = {}
local __DIRTYABLE_CONTAINER = {}


local function clear_dependencies(binding)
	for i = #binding.variables, 1, -1 do
		local variable = binding.variables[i]
		local variableDependents = (dependents[variable.container] or {})[variable.key]
		if variableDependents then
			set_remove(variableDependents[module.currentBindings], binding)
		end
		binding.variables[i] = nil
	end
end

local function add_dependency(container, key)
	if not module.currentBinding then
		return
	end

	local containerDependents = dependents[container]
	if not containerDependents then
		return
	end
	local variableDependents = containerDependents[key] or {}
	containerDependents[key] = variableDependents
	local bindings = variableDependents[module.currentBindings] or {}
	variableDependents[module.currentBindings] = bindings
	set_insert(bindings, module.currentBinding)

	set_insert(module.currentBinding.variables, { container = container, key = key })
end

local function get_container_key(ref)
	local container = ref[__ROOT]
	local keys = ref[__KEYS]
	for i = 1, #keys - 1 do
		container = container[keys[i]]
	end
	local key = keys[#keys]

	return container, key
end

local function make_variable_dirtyable(ref)
	local container, key = get_container_key(ref)
	local a = dependents[container] or {}
	dependents[container] = a
	a[key] = a[key] or {}
end

local function make_container_dirtyable(v)
	dependents[v] = dependents[v] or {}
	dependents[v][__DIRTYABLE_CONTAINER] = true
end

local function is_variable_dirtyable(ref)
	local container, key = get_container_key(ref)
	return ((dependents[container] or {})[key] ~= nil) or (dependents[container][__DIRTYABLE_CONTAINER] == true)
end

local function dirty_variable(ref)
	local container = ref[__ROOT]
	local keys = ref[__KEYS]
	for i = 1, #keys - 1 do
		local key = keys[i]
		add_dependency(container, key)
		container = container[key]
	end
	local key = keys[#keys]

	local bindingsCollections = (dependents[container] or {})[key]
	if not bindingsCollections then
		return
	end
	for bindingsCollection, bindings in pairs(bindingsCollections) do
		for i = 1, #bindings do
			local binding = bindings[i]
			if binding ~= bindingsCollection.ignoreDirtyBinding then
				local lineage = {binding}
				while lineage[#lineage].container do
					table.insert(lineage, lineage[#lineage].container)
				end

				local d = bindingsCollection.dirty
				for i = #lineage, 2, -1 do
					d[lineage[i]] = d[lineage[i]] or {}
					d = d[lineage[i]]
				end
				d[binding] = true
			end
		end
	end
end

local function set_variable(ref, value)
	local container, key = get_container_key(ref)
	container[key] = value
end


-- Dereference with length (#) operator to make a binding dependent on variable
-- and ancestor variables.
-- Index to create a Reference to a descendent variable
local ReferenceMt = {}
local Reference = {}
function Reference:new(root, keys)
	assert(root ~= nil and keys ~= nil)

	local o = {}
	setmetatable(o, ReferenceMt)
	o[__ROOT] = root
	o[__KEYS] = keys
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

function ReferenceMt:dereference()
	local container = self[__ROOT]
	local keys = self[__KEYS]
	for i = 1, #keys do
		local key = keys[i]
		add_dependency(container, key)
		container = container[key]
	end
	return container
end

-- Return underlying value and mark as a dependency
function ReferenceMt:__len()
	return ReferenceMt.dereference(self)
end


-- Can't be dereferenced, only indexed to create a Reference
local HalfReferenceMt = {}
local HalfReference = {}
function HalfReference:new(container)
	local o = {}
	setmetatable(o, HalfReferenceMt)
	o[__CONTAINER] = container
	return o
end

function HalfReferenceMt:__index(k)
	return Reference:new(self[__CONTAINER], {k})
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


module.R = R
module.Reference = Reference
module.HalfReference = HalfReference
module.currentBindings = nil
module.currentBinding = nil
module.clear_dependencies = clear_dependencies
module.make_variable_dirtyable = make_variable_dirtyable
module.make_container_dirtyable = make_container_dirtyable
module.is_variable_dirtyable = is_variable_dirtyable
module.dirty_variable = dirty_variable
module.set_variable = set_variable

return module
