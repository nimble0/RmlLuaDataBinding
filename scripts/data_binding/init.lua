local bindings = require("data_binding.bindings")
local lenses = require("data_binding.lenses")
local reference = require("reference")
local set = require("set")


local module = {}

local WeakTable = { __mode = "kv" }
local WeakValueTable = { __mode = "v" }

module.allBindings = {}
setmetatable(module.allBindings, WeakValueTable)
local bindingId = 0

-- Lower priority values are updated first
-- Default priority is 1
-- Binding priority within bind-for elements only applies relative to other
-- elements within the bind-for.
local elementBindingPriorities = {
	option = 1,
	select = 2,
}

-- Unique keys to prevent conflicting with other keys in index metamethod
local __BINDINGS = {}

local error_handler = print
local onAddElementListeners = {}
local onRemoveElementListeners = {}

local eventTypes = {
	"mousedown",
	"mousescroll",
	"mouseover",
	"mouseout",
	"focus",
	"blur",
	"keydown",
	"keyup",
	"textinput",
	"mouseup",
	"click",
	"dblclick",
	"load",
	"unload",
	"show",
	"hide",
	"mousemove",
	"dragmove",
	"drag",
	"dragstart",
	"dragover",
	"dragdrop",
	"dragout",
	"dragend",
	"handledrag",
	"resize",
	"scroll",
	"animationend",
	"transitionend",
	"change",
	"submit",
	"tabchange",
}
local attributeTypes = {
	-- Taken from RmlUi documentation
	-- Elements
	"id",
	"class",
	"style",
	"lang",
	"dir",

	-- RML Document Structure
	"type",
	"href",
	"src",

	-- RML Style Sheets
	"style",

	-- RML Templates
	"name",
	"content",
	"src",
	"template",

	-- RML Images
	"src",
	"sprite",
	"width",
	"height",
	"rect",

	-- RML Forms
	"name",
	"value",
	"disabled",
	"autofocus",
	"type",
	"size",
	"maxlength",
	"placeholder",
	"checked",
	"min",
	"max",
	"step",
	"orientation",
	"cols",
	"rows",
	"wrap",
	"maxlength",
	"placeholder",
	"selected",
	"for",

	-- RML Controls
	"move_target",
	"size_target",
	"edge_margin",

	-- RML Data Display Elements
	"value",
	"max",
	"direction",
	"start-edge",
}


local function update_dirty_bindings(bindings)
	for binding, children in pairs(bindings) do
		if children == true then
			binding:singleUpdate()
		else
			update_dirty_bindings(children)
		end
	end
end

function element_path(e)
	local identifiers = {}
	table.insert(identifiers, e.tag_name)
	if e.id ~= "" then
		table.insert(identifiers, "#")
		table.insert(identifiers, e.id)
	end
	if e.class_name ~= "" then
		table.insert(identifiers, ".")
		table.insert(identifiers, e.class_name)
	end

	if e.parent_node then
		table.insert(identifiers, 1, " > ")
		table.insert(identifiers, 1, element_path(e.parent_node))
	end
	return table.concat(identifiers)
end


local Bindings = {}
function Bindings:new(element, env)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.direct = {}
	for _, priority in pairs(elementBindingPriorities) do
		o.direct[priority] = {}
	end
	o.indirect = {}
	-- All real (not abstract) bindings
	-- Use tostring(element) as key because the same element can be bound as
	-- different Lua objects.
	o.real = {}
	o.dirty = nil
	o.deferredSetBindings = {}
	-- Workaround because we can't store a binding reference directly in a element
	-- Store element (key) as string because element references do not satisfy equality
	o.elementSubmitBindings = {}
	-- dependencies layout
	-- {
	-- 	root container
	-- 	{
	-- 		key1
	-- 		{
	-- 			bindings (__BINDINGS)
	-- 			{
	-- 				binding
	-- 			}
	-- 			key2
	-- 			{
	-- 				bindings (__BINDINGS)
	-- 				{
	-- 					binding
	-- 				}
	-- 			}
	-- 		}
	-- 	}
	-- }
	o.dependencies = {}
	o.updating = false
	o.env = env
	o.onAddElementListeners = {}
	o.onRemoveElementListeners = {}

	local selectors = {
		"[_bind]",
		"[bind]",
		"[bind-class]",
		"[bind-for]",
		"[bind-value]",
		"[bind-checked]",
		"[bind-submit]",
		"[bind-submit-value]",
		"[bind-submit-checked]",
	}
	for _, event in pairs(eventTypes) do
		table.insert(selectors, "[bind-event-" .. event .. "]")
	end
	local attributeSelectors = {}
	for _, attribute in pairs(attributeTypes) do
		table.insert(selectors, "[bind-attribute-" .. attribute .. "]")
	end

	local function deduplicate(l)
		table.sort(l)
		local i = 1
		while i < #l do
			if l[i] == l[i + 1] then
				table.remove(l, i)
			else
				i = i + 1
			end
		end
	end
	deduplicate(selectors)
	o.bindingsSelector = table.concat(selectors, ", ")

	setmetatable(o.elementSubmitBindings, WeakValueTable)

	table.insert(module.allBindings, o)

	bindings.currentBindings = o
	for _, element in pairs(element:QuerySelectorAll(o.bindingsSelector)) do
		o:bind(element)
	end
	bindings.currentBindings = nil
	o:addElement(element)

	return o
end

function Bindings:delete()
	set.remove(module.allBindings, self)
	self.direct = {}
	self.indirect = {}
	self.real = {}
	self.dirty = {}
	self.deferredSetBindings = {}
	self.elementSubmitBindings = {}
	self.dependencies = {}
	self.onAddElementListeners = {}
	self.onRemoveElementListeners = {}
end

function Bindings:addOnNewElementListener(l) set.insert(self.onAddElementListeners, l) end
function Bindings:removeOnNewElementListener(l) set.remove(self.onAddElementListeners, l) end
function Bindings:addOnDestroyElementListener(l) set.insert(self.onRemoveElementListeners, l) end
function Bindings:removeOnDestroyElementListener(l) set.remove(self.onRemoveElementListeners, l) end

function Bindings:registerBinding(element, binding)
	if not binding then
		return
	end

	local k = tostring(element)
	local elementBindings = self.real[k] or {}
	self.real[k] = elementBindings
	elementBindings[binding.id] = binding
end

function Bindings:addElement(element)
	for i = 1, #self.onAddElementListeners do
		xpcall(self.onAddElementListeners[i], error_handler, element)
	end

	-- global listeners
	for i = 1, #onAddElementListeners do
		xpcall(onAddElementListeners[i], error_handler, element)
	end
end

function Bindings:removeElement(element)
	self.real[tostring(element)] = {}

	for i = 1, #self.onRemoveElementListeners do
		xpcall(self.onRemoveElementListeners[i], error_handler, element)
	end

	-- global listeners
	for i = 1, #onRemoveElementListeners do
		xpcall(onRemoveElementListeners[i], error_handler, element)
	end
end

function Bindings:_dirtyBinding(binding)
	if not binding then
		return
	end

	if binding ~= self.ignoreDirtyBinding then
		local lineage = {binding}
		while lineage[#lineage].container do
			table.insert(lineage, lineage[#lineage].container)
		end

		local d = self.dirty
		for i = #lineage, 2, -1 do
			d[lineage[i]] = d[lineage[i]] or {}
			d = d[lineage[i]]
		end
		d[binding] = true
	end
end
function Bindings:dirtyBinding(element, bindingId)
	local elementBindings = self.real[tostring(element)]
	if not elementBindings then
		return
	end

	if bindingId then
		self:_dirtyBinding(elementBindings[bindingId])
	else
		for id, binding in pairs(elementBindings) do
			self:_dirtyBinding(binding)
		end
	end
end
function Bindings:_dirtySetBinding(binding)
	if not binding or not binding.setBinding then
		return
	end
	self.deferredSetBindings[binding] = true
end
function Bindings:dirtySetBinding(element, bindingId)
	local elementBindings = self.real[tostring(element)]
	if not elementBindings then
		return
	end

	if bindingId then
		self:_dirtySetBinding(elementBindings[bindingId])
	else
		for id, binding in pairs(elementBindings) do
			self:_dirtySetBinding(binding)
		end
	end
end

function Bindings:update()
	self:setDeferredBindings()
	if self.dirty then
		self:updateDirty()
	else
		self:updateFull()
	end
end

function Bindings:updateFull()
	self.dirty = {}

	self.updating = true
	bindings.currentBindings = self
	for _, bindingsGroup in pairs(self.direct) do
		for element, elementBindings in pairs(bindingsGroup) do
			for i = 1, #elementBindings do
				elementBindings[i]:update()
			end
		end
	end
	bindings.currentBindings = nil
	self.updating = false
end

function Bindings:updateDirty()
	if not self.dirty then
		error("Must do full update before updateDirty", 2)
	end

	self.updating = true
	bindings.currentBindings = self
	update_dirty_bindings(self.dirty)
	bindings.currentBindings = nil
	self.updating = false
	self.dirty = {}
end

function Bindings:setDeferredBindings()
	bindings.currentBindings = self
	for binding in pairs(self.deferredSetBindings) do
		self.ignoreDirtyBinding = binding
		binding.setBinding(binding.value)
		self.ignoreDirtyBinding = nil
		binding.value = nil
		local element = Element.As.ElementFormControl(binding.element)
		element:RemoveAttribute("bind-submit-dirty")
	end
	bindings.currentBindings = nil
	self.deferredSetBindings = {}
end

function Bindings:bind(
	element,
	useBindingId
)
	if element:HasAttribute("bind-id") then
		return
	end

	local abstractElementBindings = {}

	local useForBindingId = false
	if element:HasAttribute("bind-for") then
		element.class_name = element.class_name .. " bind-for-base"
		local abstractBinding = bindings.AbstractForBinding:new(self.env, element, self.indirect)

		if not useBindingId then
			local elementBinding = abstractBinding:apply(element)
			self.direct[elementBindingPriorities[element.tag_name] or 1][element] = {elementBinding}
			self:registerBinding(element, elementBinding)
		else
			local id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-id", tostring(id))

			self.indirect[id] = {abstractBinding}
		end

		-- Other binding on this element will only apply to its for elements
		useForBindingId = true
	end

	if element:HasAttribute("bind-class") then
		table.insert(abstractElementBindings, bindings.AbstractClassBinding:new(self.env, element))
	end

	for attribute, bind in pairs(element.attributes) do
		if attribute:sub(1, 15) == "bind-attribute-" then
			local bindAttribute = attribute:sub(16)
			table.insert(abstractElementBindings, bindings.AbstractAttributeBinding:new(self.env, element, bindAttribute))
		end
	end

	for attribute, bind in pairs(element.attributes) do
		if attribute:sub(1, 11) == "bind-event-" then
			local event = attribute:sub(12)
			table.insert(abstractElementBindings, bindings.AbstractEventBinding:new(self.env, element, event))
		end
	end

	if element:HasAttribute("bind-value") then
		table.insert(abstractElementBindings, bindings.AbstractValueBinding:new(self.env, element))
	end

	if element:HasAttribute("bind-checked") then
		table.insert(abstractElementBindings, bindings.AbstractCheckedBinding:new(self.env, element))
	end

	if element:HasAttribute("bind-submit-value") then
		table.insert(abstractElementBindings, bindings.AbstractSubmitValueBinding:new(self.env, element))
	end

	if element:HasAttribute("bind-submit-checked") then
		table.insert(abstractElementBindings, bindings.AbstractSubmitCheckedBinding:new(self.env, element))
	end

	if element:HasAttribute("bind-submit") then
		table.insert(abstractElementBindings, bindings.AbstractSubmitBinding:new(self.env, element))
	end

	if element:HasAttribute("bind") then
		table.insert(abstractElementBindings, bindings.AbstractContentBinding:new(self.env, element))
	end

	if #abstractElementBindings > 0 then
		if useForBindingId then
			local id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-for-id", tostring(id))
			self.indirect[id] = abstractElementBindings
		elseif useBindingId then
			local id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-id", tostring(id))
			self.indirect[id] = abstractElementBindings
		else
			local elementBindings = {}
			for i = 1, #abstractElementBindings do
				local elementBinding = abstractElementBindings[i]:apply(element)
				if elementBinding then
					table.insert(elementBindings, elementBinding)
				end
				self:registerBinding(element, elementBinding)
			end
			self.direct[elementBindingPriorities[element.tag_name] or 1][element] = elementBindings
		end
	end

	if useForBindingId then
		for _, element in pairs(element:QuerySelectorAll("* " .. self.bindingsSelector)) do
			self:bind(element, true)
		end
	end

	self:addElement(element)
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

function Bindings:dirtyVariable(ref)
	local root = reference.Reference.get_root(ref)
	local keys = reference.Reference.get_keys(ref)
	local refDependentBindings = self.dependencies[root]
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
			if binding ~= self.ignoreDirtyBinding then
				local lineage = {binding}
				while lineage[#lineage].container do
					table.insert(lineage, lineage[#lineage].container)
				end

				local d = self.dirty
				for i = #lineage, 2, -1 do
					d[lineage[i]] = d[lineage[i]] or {}
					d = d[lineage[i]]
				end
				d[binding] = true
			end
		end
	end
end

local function Bindings_addDependency(ref)
	local self = bindings.currentBindings
	if not self or not bindings.currentBinding then
		return
	end

	local root = reference.Reference.get_root(ref)
	local keys = reference.Reference.get_keys(ref)
	local refDependentBindings = self.dependencies[root]
	if refDependentBindings == nil then
		self.dependencies[root] = {}
		refDependentBindings = self.dependencies[root]
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
	set.insert(refDependentBindings[__BINDINGS], bindings.currentBinding)

	set.insert(bindings.currentBinding.variables, ref)
end


local function make_bindings(element, env)
	return Bindings:new(element, env)
end

bindings.error_handler = error_handler
bindings.elementBindingPriorities = elementBindingPriorities

reference.add_dirty_listener(function(ref)
	for i = 1, #module.allBindings do
		module.allBindings[i]:dirtyVariable(ref)
	end
end)
reference.add_access_listener(Bindings_addDependency)

module.make_bindings = make_bindings
module.make_lens = lenses.make_lens
module.make_number_lens = lenses.make_number_lens
module.make_float_lens = lenses.make_float_lens
module.make_boolean_lens = lenses.make_boolean_lens
module.make_enum_lens = lenses.make_enum_lens
module.add_on_add_element_listener = function(l) set.insert(onAddElementListeners, l) end
module.remove_on_add_element_listener = function(l) set.remove(onAddElementListeners, l) end
module.add_on_remove_element_listener = function(l) set.insert(onRemoveElementListeners, l) end
module.remove_on_remove_element_listener = function(l) set.remove(onRemoveElementListeners, l) end
module.eventTypes = eventTypes
module.attributeTypes = attributeTypes

module.dirty_variable = reference.dirty_variable
module.set_variable = reference.set_variable

-- Index R to create references to global variables and special variables (for binding variables).
-- Call R with a table argument to create a half reference, index the half reference to create a
-- full reference.
-- When a reference is dereferenced (with the length (#) operator) within a binding, it marks the
-- binding as dependent on the variable and all ancestor variables
-- eg/ A binding that uses `#R.a.b` is dependent on both `a` and `a.b`.
module.R = reference.R

return module
