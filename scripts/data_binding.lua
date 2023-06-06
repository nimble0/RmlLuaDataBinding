local bindings = require("data_binding_bindings")
local reference = require("data_binding_reference")
local lenses = require("data_binding_lenses")

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
function Bindings:new(element)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	o.direct = {}
	for _, priority in pairs(elementBindingPriorities) do
		o.direct[priority] = {}
	end
	o.indirect = {}
	o.dirty = {}
	o.deferredSetBindings = {}
	-- Workaround because we can't store a binding reference directly in a element
	-- Store element (key) as string because element references do not satisfy equality
	o.elementSubmitBindings = {}
	o.updating = false
	setmetatable(o.elementSubmitBindings, WeakValueTable)

	reference.currentBindings = o
	o:bind(element)
	reference.currentBindings = nil

	return o
end

function Bindings:update()
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
		local abstractBinding = bindings.AbstractForBinding:new(element, self.indirect)

		if not useBindingId then
			self.direct[elementBindingPriorities[element.tag_name] or 1][element] = {abstractBinding:apply(element)}
		else
			local id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-id", id)

			self.indirect[id] = {abstractBinding}
		end

		-- Other binding on this element will only apply to its for elements
		useBindingId = true
		useForBindingId = true
	end

	if element:HasAttribute("bind-class") then
		table.insert(abstractElementBindings, bindings.AbstractClassBinding:new(element))
	end

	for attribute, bind in pairs(element.attributes) do
		if attribute:sub(1, 15) == "bind-attribute-" then
			local bindAttribute = attribute:sub(16)
			table.insert(abstractElementBindings, bindings.AbstractAttributeBinding:new(element, bindAttribute))
		end
	end

	for attribute, bind in pairs(element.attributes) do
		if attribute:sub(1, 11) == "bind-event-" then
			local event = attribute:sub(12)
			table.insert(abstractElementBindings, bindings.AbstractEventBinding:new(element, event))
		end
	end

	if element:HasAttribute("bind-value") then
		table.insert(abstractElementBindings, bindings.AbstractValueBinding:new(element))
	end

	if element:HasAttribute("bind-checked") then
		table.insert(abstractElementBindings, bindings.AbstractCheckedBinding:new(element))
	end

	if element:HasAttribute("bind-submit-value") then
		table.insert(abstractElementBindings, bindings.AbstractSubmitValueBinding:new(element))
	end

	if element:HasAttribute("bind-submit-checked") then
		table.insert(abstractElementBindings, bindings.AbstractSubmitCheckedBinding:new(element))
	end

	if element:HasAttribute("bind-submit") then
		table.insert(abstractElementBindings, bindings.AbstractSubmitBinding:new(element))
	end

	if element:HasAttribute("bind") then
		table.insert(abstractElementBindings, bindings.AbstractContentBinding:new(element))
	end

	if #abstractElementBindings > 0 then
		if useForBindingId then
			local id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-for-id", id)
			self.indirect[id] = abstractElementBindings
		elseif useBindingId then
			local id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-id", id)
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
			if data_binding.onCreateElement then
				xpcall(data_binding.onCreateElement, error_handler, element)
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

local function make_bindings(element)
	return Bindings:new(element)
end

bindings.error_handler = error_handler
bindings.elementBindingPriorities = elementBindingPriorities


return {
	make_bindings = make_bindings,
	make_lens = lenses.make_lens,
	make_number_lens = lenses.make_number_lens,
	make_float_lens = lenses.make_float_lens,
	make_boolean_lens = lenses.make_boolean_lens,
	make_enum_lens = lenses.make_enum_lens,
	onCreateElement = nil,
	onDestroyElement = nil,

	make_variable_dirtyable = reference.make_variable_dirtyable,
	make_container_dirtyable = reference.make_container_dirtyable,
	is_variable_dirtyable = reference.is_variable_dirtyable,
	-- Dirty bindings dependent on variable
	dirty_variable = reference.dirty_variable,
	set_variable = reference.set_variable,

	-- Index R to create references to global variables and special variables (for binding variables).
	-- Call R with a table argument to create a half reference, index the half reference to create a
	-- full reference.
	-- When a reference is dereferenced (with the length (#) operator) within a binding, it marks the
	-- binding as dependent on the variable and all ancestor variables
	-- eg/ A binding that uses `#R.a.b` is dependent on both `a` and `a.b`.
	R = reference.R,
}
