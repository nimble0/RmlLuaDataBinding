local module = {}

local function consecutive_error_handler() end


local function safe_get_binding(binding)
	local errorHandler = module.error_handler
	-- Don't spam log with the same errors
	if binding.errored then
		errorHandler = consecutive_error_handler
	end
	local success, value = xpcall(binding.binding, errorHandler)
	binding.errored = not success
	return value
end

local function trim(s)
   return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end

local function split(s, d)
	local result = {}
	local i = 1
	local j, k = s:find(d, i)
	while j do
		table.insert(result, s:sub(i, j - 1))
		i = k + 1
		j, k = s:find(d, i)
	end
	table.insert(result, s:sub(i))
	return result
end

local function make_binding(source)
	local command, error = load("return " .. source)
	if command == nil then
		command, error = load(source)
	end

	return command, error
end

local function parse_bind_for(value)
	local a, b = value:find("%sin%s")
	local variables = split(value:sub(1, a), ",")

	local indexKey = nil
	local valueKey = nil
	if #variables == 0 then
		indexKey = "i"
		valueKey = "it"
	elseif #variables == 1 then
		indexKey = "i"
		valueKey = trim(variables[1])
	else
		indexKey = trim(variables[1])
		valueKey = trim(variables[2])
	end
	local eval = value:sub(b + 1)

	return indexKey, valueKey, make_binding(eval)
end

local function bind_value_set(element, binding)
	local currentBindings = module.currentBindings
	element:AddEventListener("change",
		function(event)
			if not element:GetAttribute("ignore-change") then
				currentBindings.ignoreDirtyBinding = binding
				binding.setBinding(event.parameters.value)
				currentBindings.ignoreDirtyBinding = nil
			end
		end,
		true)
end

local function form_submit(_, element)
	for _, e in pairs(element.child_nodes) do
		local submitValueBinding = e:GetAttribute("bind-submit-value") or e:GetAttribute("bind-submit-checked")
		if submitValueBinding and e:HasAttribute("bind-submit-dirty") then
			local value = Element.As.ElementFormControl(e).value
			local success = xpcall(
				function(src, value) select(2, make_binding(src)())(value) end,
				module.error_handler,
				submitValueBinding,
				value)
			if success then
				e:RemoveAttribute("bind-submit-dirty")
			end
		end
		form_submit(_, e)
	end
end

local function bind_submit_form(element)
	local containerForm = element.parent_node
	while containerForm ~= nil and containerForm.tag_name ~= "form" do
		containerForm = containerForm.parent_node
	end
	if containerForm == nil then
		return
	end
	if not containerForm:HasAttribute("bind-submit") then
		containerForm:SetAttribute("bind-submit", "true")
		containerForm:AddEventListener("submit", form_submit)
	end
end

local function bind_submit_value_set(element, bindValue)
	local currentBindings = module.currentBindings
	element:AddEventListener("change",
		function(event)
			if not element:GetAttribute("ignore-change") then
				element:SetAttribute("bind-submit-dirty", "")
			end
		end,
		true)
	bind_submit_form(element)
end

local function bind_for_sub_element(
	directBindings,
	indirectBindings,
	element,
	parent,
	parentIndex
)
	local id = tonumber(element:GetAttribute("bind-id"))
	local abstractBindings = indirectBindings[id] or {}
	local elementBindings = {}
	for i = 1, #abstractBindings do
		local elementBinding = abstractBindings[i]:apply(element)
		if elementBinding then
			elementBinding.parent = parent
			elementBinding.parentIndex = parentIndex
			table.insert(elementBindings, elementBinding)
		end
	end

	if #elementBindings > 0 then
		directBindings[module.elementBindingPriorities[element.tag_name] or 1][element] = elementBindings
	end

	if not element:HasAttribute("bind") and not element:HasAttribute("bind-for") then
		for _, child in pairs(element.child_nodes) do
			bind_for_sub_element(directBindings, indirectBindings, child, parent, parentIndex)
		end
	end
end

local function bind_for_child(
	forElements,
	indirectBindings,
	element,
	parent
)
	local forElement = {}
	table.insert(forElements, forElement)
	forElement.element = element
	forElement.bindings = {}

	local parentIndex = #forElements

	local id = tonumber(element:GetAttribute("bind-for-id"))
	local abstractBindings = indirectBindings[id] or {}
	local elementBindings = {}
	for i = 1, #abstractBindings do
		local elementBinding = abstractBindings[i]:apply(element)
		if elementBinding then
			elementBinding.parent = parent
			elementBinding.parentIndex = parentIndex
			table.insert(elementBindings, elementBinding)
		end
	end

	forElement.bindings = {}
	for _, priority in pairs(module.elementBindingPriorities) do
		forElement.bindings[priority] = {}
	end

	if #elementBindings > 0 then
		forElement.bindings[module.elementBindingPriorities[element.tag_name] or 1][element] = elementBindings
	end

	if not element:HasAttribute("bind") then
		for _, child in pairs(element.child_nodes) do
			bind_for_sub_element(forElement.bindings, indirectBindings, child, parent, parentIndex)
		end
	end
end


local Binding = {}
function Binding:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Binding:update() end


local ContentBinding = Binding:new()
function ContentBinding:update()
	self.element.inner_rml = tostring(safe_get_binding(self))
end

local AbstractContentBinding = {}
function AbstractContentBinding:new(element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	local source = element:GetAttribute("bind")
	if source:len() == 0 then
		source = element.inner_rml
	end
	o.binding = make_binding(source)
	o.source = source
	return o
end

function AbstractContentBinding:apply(element)
	return ContentBinding:new{element = element, binding = self.binding, source = self.source}
end


local ClassBinding = Binding:new()
function ClassBinding:update()
	self.element.class_name = self.fixedClass .. " " .. tostring(safe_get_binding(self))
end

local AbstractClassBinding = {}
function AbstractClassBinding:new(element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.binding = make_binding(element:GetAttribute("bind-class"))
	o.source = source
	return o
end

function AbstractClassBinding:apply(element)
	return ClassBinding:new{element = element, binding = self.binding, fixedClass = element.class_name, source = self.source}
end


local AttributeBinding = Binding:new()
function AttributeBinding:update()
	self.element:SetAttribute(self.attribute, tostring(safe_get_binding(self)))
end

local AbstractAttributeBinding = {}
function AbstractAttributeBinding:new(element, attribute)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.attribute = attribute
	o.binding = make_binding(element:GetAttribute("bind-attribute-"..attribute))
	o.source = source
	return o
end

function AbstractAttributeBinding:apply(element)
	return AttributeBinding:new{element = element, binding = self.binding, attribute = self.attribute, source = self.source}
end


local AbstractEventBinding = {}
function AbstractEventBinding:new(element, event)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.event = event
	o.binding = make_binding(element:GetAttribute("bind-event-"..event))
	o.source = source
	return o
end

function AbstractEventBinding:apply(element)
	element:AddEventListener(self.event, self.binding, true)
end


local ValueBinding = Binding:new()
function ValueBinding:update()
	local newValue = tostring(safe_get_binding(self))

	self.element:SetAttribute("ignore-change", "")
	Element.As.ElementFormControl(self.element).value = newValue
	self.element:DispatchEvent("change", { value = newValue })
	self.element:RemoveAttribute("ignore-change")
end

local AbstractValueBinding = {}
function AbstractValueBinding:new(element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.binding, o.setBinding = make_binding(element:GetAttribute("bind-value"))()
	o.source = source
	return o
end

function AbstractValueBinding:apply(element)
	local o = ValueBinding:new{element = element, binding = self.binding, setBinding = self.setBinding, source = self.source}
	bind_value_set(element, o)
	return o
end


local CheckedBinding = Binding:new()
function CheckedBinding:update()
	local newValue = tostring(safe_get_binding(self))

	self.element:SetAttribute("ignore-change", "")
	Element.As.ElementFormControlInput(self.element).checked = newValue == self.element:GetAttribute("value")
	self.element:DispatchEvent("change", { value = newValue })
	self.element:RemoveAttribute("ignore-change")
end

local AbstractCheckedBinding = {}
function AbstractCheckedBinding:new(element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.binding, o.setBinding = make_binding(element:GetAttribute("bind-checked"))()
	o.source = source
	return o
end

function AbstractCheckedBinding:apply(element)
	local o = CheckedBinding:new{element = element, binding = self.binding, setBinding = self.setBinding, source = self.source}
	bind_value_set(element, o)
	return o
end


local SubmitValueBinding = Binding:new()
function SubmitValueBinding:update()
	if not self.element:HasAttribute("bind-submit-dirty") then
		local newValue = tostring(safe_get_binding(self))

		self.element:SetAttribute("ignore-change", "")
		Element.As.ElementFormControl(self.element).value = newValue
		self.element:DispatchEvent("change", { value = newValue })
		self.element:RemoveAttribute("ignore-change")
	end
end

local AbstractSubmitValueBinding = {}
function AbstractSubmitValueBinding:new(element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.binding, o.setBinding = make_binding(element:GetAttribute("bind-submit-value"))()
	o.source = source
	return o
end

function AbstractSubmitValueBinding:apply(element)
	local o = SubmitValueBinding:new{element = element, binding = self.binding, setBinding = self.setBinding, source = self.source}
	bind_submit_value_set(element, o)
	return o
end


local SubmitCheckedBinding = Binding:new()
function SubmitCheckedBinding:update()
	if not self.element:HasAttribute("bind-submit-dirty") then
		local newValue = tostring(safe_get_binding(self))

		self.element:SetAttribute("ignore-change", "")
		Element.As.ElementFormControlInput(self.element).checked = newValue == self.element:GetAttribute("value")
		self.element:DispatchEvent("change", { value = newValue })
		self.element:RemoveAttribute("ignore-change")
	end
end

local AbstractSubmitCheckedBinding = {}
function AbstractSubmitCheckedBinding:new(element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.binding, o.setBinding = make_binding(element:GetAttribute("bind-submit-checked"))()
	o.source = source
	return o
end

function AbstractSubmitCheckedBinding:apply(element)
	local o = SubmitCheckedBinding:new{element = element, binding = self.binding, setBinding = self.setBinding, source = self.source}
	bind_submit_value_set(element, o)
	return o
end


local ForBinding = Binding:new()
function ForBinding:update()
	self.values = safe_get_binding(self) or {}

	local indexKey = self.indexKey
	local valueKey = self.valueKey
	local elements = self.elements

	while #self.values > #elements do
		self.element.parent_node:InsertBefore(self.element.owner_document:CreateElement(self.element.tag_name), self.element)
		local forElement = self.element.previous_sibling
		for k, v in pairs(self.element.attributes) do
			forElement:SetAttribute(k, v)
		end
		forElement:RemoveAttribute("bind-for")
		if self.element.tag_name == "option" then
			forElement:RemoveAttribute("selected")
		end
		forElement.class_name = self.element.class_name
		forElement:SetClass("bind-for-base", false)
		forElement.inner_rml = self.element.inner_rml
		bind_for_child(elements, self.indirectBindings, forElement, self)
		if data_binding.onCreateElement then
			xpcall(data_binding.onCreateElement, module.error_handler, forElement)
		end
	end
	while #self.values < #elements do
		if data_binding.onDestroyElement then
			xpcall(data_binding.onDestroyElement, module.error_handler, elements[#elements].element)
		end
		self.element.parent_node:RemoveChild(elements[#elements].element)
		table.remove(elements, #elements)
	end

	local index_ = _G[indexKey]
	local it_ = _G[valueKey]
	for k, v in pairs(self.values) do
		local forElementBindings = elements[k]
		_G[indexKey] = k
		_G[valueKey] = v

		for _, bindingsGroup in pairs(forElementBindings.bindings) do
			for element, bindings in pairs(bindingsGroup) do
				for i = 1, #bindings do
					bindings[i]:update()
				end
			end
		end
	end
	_G[indexKey] = index_
	_G[valueKey] = it_
end

local AbstractForBinding = {}
function AbstractForBinding:new(element, indirectBindings)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.indirectBindings = indirectBindings
	o.indexKey, o.valueKey, o.binding = parse_bind_for(element:GetAttribute("bind-for"))
	o.source = element:GetAttribute("bind-for")
	return o
end

function AbstractForBinding:apply(element)
	return ForBinding:new{
		element = element,
		indirectBindings = self.indirectBindings,
		binding = self.binding,
		indexKey = self.indexKey,
		valueKey = self.valueKey,
		elements = {},
		source = self.source}
end


module.AbstractContentBinding = AbstractContentBinding
module.AbstractClassBinding = AbstractClassBinding
module.AbstractAttributeBinding = AbstractAttributeBinding
module.AbstractEventBinding = AbstractEventBinding
module.AbstractValueBinding = AbstractValueBinding
module.AbstractCheckedBinding = AbstractCheckedBinding
module.AbstractSubmitValueBinding = AbstractSubmitValueBinding
module.AbstractSubmitCheckedBinding = AbstractSubmitCheckedBinding
module.AbstractForBinding = AbstractForBinding

return module
