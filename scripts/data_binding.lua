local bindings = require("data_binding_bindings")
local reference = require("data_binding_reference")
local lenses = require("data_binding_lenses")

local module = {}

local WeakValueTable = { __mode = "v" }

local bindingId = 0

-- Lower priority values are updated first
-- Default priority is 1
-- Binding priority within bind-for elements only applies relative to other
-- elements within the bind-for.
local elementBindingPriorities = {
	option = 1,
	select = 2,
}

local function error_handler(m)
	print(m)
end


local function update_dirty_bindings(bindings)
	for binding, children in pairs(bindings) do
		if children == true then
			binding:singleUpdate()
		else
			update_dirty_bindings(children)
		end
	end
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
	o.dirty = nil
	o.deferredSetBindings = {}
	-- Workaround because we can't store a binding reference directly in a element
	-- Store element (key) as string because element references do not satisfy equality
	o.elementSubmitBindings = {}
	o.dependencies = {}
	o.updating = false
	o.env = env
	setmetatable(o.elementSubmitBindings, WeakValueTable)

	reference.add_bindings(o)

	reference.currentBindings = o
	o:bind(element)
	reference.currentBindings = nil

	return o
end

function Bindings:delete()
	reference.clear_all_dependencies(self)
	self.direct = {}
	self.indirect = {}
	self.dirty = {}
	self.deferredSetBindings = {}
	self.elementSubmitBindings = {}
end

function Bindings:update()
	if self.dirty then
		self:updateDirty()
	else
		self:updateFull()
	end
end

function Bindings:updateFull()
	self.dirty = {}

	self.updating = true
	reference.currentBindings = self
	for _, bindingsGroup in pairs(self.direct) do
		for element, elementBindings in pairs(bindingsGroup) do
			for i = 1, #elementBindings do
				elementBindings[i]:update()
			end
		end
	end
	reference.currentBindings = nil
	self.updating = false
end

function Bindings:updateDirty()
	if not self.dirty then
		error("Must do full update before updateDirty", 2)
	end

	self.updating = true
	reference.currentBindings = self
	update_dirty_bindings(self.dirty)
	reference.currentBindings = nil
	self.updating = false
	self.dirty = {}
end

function Bindings:setDeferredBindings()
	reference.currentBindings = self
	for binding, value in pairs(self.deferredSetBindings) do
		reference.currentBindings.ignoreDirtyBinding = binding
		binding.setBinding(value)
		reference.currentBindings.ignoreDirtyBinding = nil
	end
	reference.currentBindings = nil
	self.deferredSetBindings = {}
end

function Bindings:bind(
	element,
	useBindingId
)
	local abstractElementBindings = {}

	local useForBindingId = false
	if element:HasAttribute("bind-for") then
		element:SetClass("bind-for-base", true)
		local abstractBinding = bindings.AbstractForBinding:new(self.env, element, self.indirect)

		if not useBindingId then
			self.direct[elementBindingPriorities[element.tag_name] or 1][element] = {abstractBinding:apply(element)}
		else
			local id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-id", tostring(id))

			self.indirect[id] = {abstractBinding}
		end

		-- Other binding on this element will only apply to its for elements
		useBindingId = true
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
			end
			self.direct[elementBindingPriorities[element.tag_name] or 1][element] = elementBindings
			if module.onCreateElement then
				xpcall(module.onCreateElement, error_handler, element)
			end
		end
	end

	-- Can't nest content bindings because inner_rml is replaced by a content binding
	if not element:HasAttribute("bind") then
		for _, child in pairs(element.child_nodes) do
			self:bind(child, useBindingId)
		end
	end
end

local function make_bindings(element, env)
	return Bindings:new(element, env)
end

bindings.error_handler = error_handler
bindings.elementBindingPriorities = elementBindingPriorities
bindings.callbacks = module

module.make_bindings = make_bindings
module.make_lens = lenses.make_lens
module.make_number_lens = lenses.make_number_lens
module.make_float_lens = lenses.make_float_lens
module.make_boolean_lens = lenses.make_boolean_lens
module.make_enum_lens = lenses.make_enum_lens
module.onCreateElement = nil
module.onDestroyElement = nil

module.make_variable_dirtyable = reference.make_variable_dirtyable
module.make_container_dirtyable = reference.make_container_dirtyable
module.is_variable_dirtyable = reference.is_variable_dirtyable
-- Dirty bindings dependent on variable
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
