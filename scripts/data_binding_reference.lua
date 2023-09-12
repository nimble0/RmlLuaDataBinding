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
local bindingsCollections = {}
setmetatable(bindingsCollections, WeakTable)

-- Unique keys to prevent conflicting with other keys in index metamethod
local __ROOT = {}
local __KEYS = {}
local __DIRTYABLE_CONTAINER = {}
local __BINDINGS = {}


local function add_bindings(bindings)
	table.insert(bindingsCollections, bindings)
end

local function clear_dependencies(binding)
	local bindingsDependencies = module.currentBindings.dependencies
	for i = #binding.variables, 1, -1 do
		local ref = binding.variables[i]
		local root = ref[__ROOT]
		local keys = ref[__KEYS]
		local refDependentBindings = bindingsDependencies[root]
		if refDependentBindings ~= nil then
			for i = 1, #keys do
				local key = keys[i]
				refDependentBindings = refDependentBindings[key]
			end
			set_remove(refDependentBindings[__BINDINGS], binding)
		end
	end
	binding.variables = {}
end

local function clear_all_dependencies(bindings)
	bindings.dependencies = {}
end

local function add_dependency(ref)
	if not module.currentBinding then
		return
	end

	local root = ref[__ROOT]
	local keys = ref[__KEYS]
	local bindingsDependencies = module.currentBindings.dependencies
	local refDependentBindings = bindingsDependencies[root]
	if refDependentBindings == nil then
		bindingsDependencies[root] = {}
		refDependentBindings = bindingsDependencies[root]
		refDependentBindings[__BINDINGS] = {}
	end
	for i = 1, #keys do
		local key = keys[i]
		if refDependentBindings[key] == nil then
			refDependentBindings[key] = {}
			refDependentBindings[key][__BINDINGS] = {}
		end
		refDependentBindings = refDependentBindings[key]
	end
	set_insert(refDependentBindings[__BINDINGS], module.currentBinding)

	set_insert(module.currentBinding.variables, ref)
end

local function get_children(t, exclude_key)
	local children = {}
	local check = { t }
	while #check > 0 do
		local newCheck = {}
		for _, t in pairs(check) do
			for k, v in pairs(t) do
				if k ~= exclude_key then
					table.insert(children, v)
					if type(v) == "table" then
						table.insert(newCheck, v)
					end
				end
			end
		end
		check = newCheck
	end

	return children
end

local function dirty_variable(ref)
	local root = ref[__ROOT]
	local keys = ref[__KEYS]
	for _, bindingsCollection in pairs(bindingsCollections) do
		local bindingsDependencies = bindingsCollection.dependencies
		local refDependentBindings = bindingsDependencies[root]
		if refDependentBindings ~= nil then
			for i = 1, #keys do
				local key = keys[i]
				if refDependentBindings[key] ~= nil then
					refDependentBindings = refDependentBindings[key]
				else
					refDependentBindings = nil
					break
				end
			end
		end

		if refDependentBindings ~= nil then
			-- Find dirtied bindings
			local dirtiedBindings = {}
			local refs = get_children(refDependentBindings, __BINDINGS)
			table.insert(refs, refDependentBindings)
			for _, ref in pairs(refs) do
				for _, binding in pairs(ref[__BINDINGS]) do
					table.insert(dirtiedBindings, binding)
				end
			end

			-- Add to Bindings.dirty structure
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

local function is_reference(ref)
	return getmetatable(ref) == ReferenceMt
end


-- Can't be dereferenced, only indexed to create a Reference
local HalfReferenceMt = {}
local HalfReference = {}
function HalfReference:new(container)
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
module.add_bindings = add_bindings
module.is_reference = is_reference
module.clear_dependencies = clear_dependencies
module.clear_all_dependencies = clear_all_dependencies
module.dirty_variable = dirty_variable
module.set_variable = set_variable

return module
