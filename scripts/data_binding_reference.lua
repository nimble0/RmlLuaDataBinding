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

local dirtyableVariablesLayout = {}
-- dependents layout
-- {
-- 	Bindings
-- 	{
-- 		root container
-- 		{
-- 			key1
-- 			{
-- 				bindings (__BINDINGS)
-- 				{
-- 					binding
-- 				}
-- 				key2
-- 				{
-- 					bindings (__BINDINGS)
-- 					{
-- 						binding
-- 					}
-- 				}
-- 			}
-- 		}
-- 	}
-- }
local dependents = {}
setmetatable(dependents, WeakKeyTable)

-- Unique keys to prevent conflicting with other keys in index metamethod
local __ROOT = {}
local __KEYS = {}
local __DIRTYABLE_CONTAINER = {}
local __BINDINGS = {}


local function copy_dirtyable_layout(src, dest)
	for k, v in pairs(src) do
		local dependents = {}
		dependents[__BINDINGS] = {}
		dest[k] = dependents
		copy_dirtyable_layout(v, dest[k])
	end
end

local function make_dirtyable_layout(bindings)
	dependents[bindings] = {}
	copy_dirtyable_layout(dirtyableVariablesLayout, dependents[bindings])
end

local function clear_dependencies(binding)
	local bindingsDependents = dependents[module.currentBindings]
	for i = #binding.variables, 1, -1 do
		local ref = binding.variables[i]
		local root = ref[__ROOT]
		local keys = ref[__KEYS]
		local refDependents = bindingsDependents[root]
		for i = 1, #keys do
			local key = keys[i]
			if refDependents[key] ~= nil then
				refDependents = refDependents[key]
			else
				break
			end
		end
		set_remove(refDependents[__BINDINGS], binding)
	end
	binding.variables = {}
end

local function add_dependency(ref)
	if not module.currentBinding then
		return
	end

	local root = ref[__ROOT]
	local keys = ref[__KEYS]
	local refDependents = dependents[module.currentBindings][root]
	for i = 1, #keys do
		local key = keys[i]
		if refDependents[key] ~= nil then
			refDependents = refDependents[key]
		else
			break
		end
	end
	set_insert(refDependents[__BINDINGS], module.currentBinding)

	set_insert(module.currentBinding.variables, ref)
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

local function make_path(container, keys)
	for i = 1, #keys do
		local key = keys[i]
		local subContainer = container[key] or {}
		container[key] = subContainer
		container = subContainer
	end
end

local function make_path_with_bindings(container, keys)
	for i = 1, #keys do
		local key = keys[i]
		local subContainer = container[key] or {}
		subContainer[__BINDINGS] = {}
		container[key] = subContainer
		container = subContainer
	end
end

local function make_variable_dirtyable(ref)
	local rootKeys = { ref[__ROOT] }
	local keys = ref[__KEYS]
	for i = 1, #keys do
		table.insert(rootKeys, keys[i])
	end

	make_path(dirtyableVariablesLayout, rootKeys)
	for _, dependents in pairs(dependents) do
		make_path_with_bindings(dependents, rootKeys)
	end
end

local function make_container_dirtyable(container)
	if dirtyableVariablesLayout[container] ~= nil then
		return
	end
	dirtyableVariablesLayout[container] = {}
	for _, bindingsDependents in pairs(dependents) do
		containerDependents = {}
		containerDependents[__BINDINGS] = {}
		bindingsDependents[container] = containerDependents
	end
end

local function is_variable_dirtyable(ref)
	local container, key = get_container_key(ref)
	return ((dependents[container] or {})[key] ~= nil) or (dependents[container][__DIRTYABLE_CONTAINER] == true)
end

local function dirty_variable(ref)
	local refDependents = nil
	local root = ref[__ROOT]
	local keys = ref[__KEYS]
	for bindingsCollection, bindingsDependents in pairs(dependents) do
		refDependents = bindingsDependents[root]
		for i = 1, #keys do
			local key = keys[i]
			if refDependents[key] ~= nil then
				refDependents = refDependents[key]
			else
				break
			end
		end

		local dirtiedBindings = {}
		local checkRefDependents = { refDependents }
		while true do
			local newCheckRefDependents = {}
			for i = 1, #checkRefDependents do
				local refDependents = checkRefDependents[i]
				for key, dependent in pairs(refDependents) do
					if key ~= __BINDINGS then
						table.insert(newChecksRefs, dependent)
					else
						for i = 1, #dependent do
							table.insert(dirtiedBindings, dependent[i])
						end
					end
				end
			end
			checkRefDependents = newCheckRefDependents
			if #checkRefDependents == 0 then
				break
			end
		end

		for i = 1, #dirtiedBindings do
			local binding = dirtiedBindings[i]
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

	dirty_variable(self)
	container[k] = v
end

function ReferenceMt:dereference()
	add_dependency(self)
	local container = self[__ROOT]
	local keys = self[__KEYS]
	for i = 1, #keys do
		local key = keys[i]
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
	make_container_dirtyable(container)
	local o = {}
	setmetatable(o, HalfReferenceMt)
	o[__ROOT] = container
	return o
end

function HalfReferenceMt:__index(k)
	return Reference:new(self[__ROOT], {k})
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
module.make_dirtyable_layout = make_dirtyable_layout
module.clear_dependencies = clear_dependencies
module.make_variable_dirtyable = make_variable_dirtyable
module.make_container_dirtyable = make_container_dirtyable
module.is_variable_dirtyable = is_variable_dirtyable
module.dirty_variable = dirty_variable
module.set_variable = set_variable

return module
