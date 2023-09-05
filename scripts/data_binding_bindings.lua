local module = {}

local reference = require("data_binding_reference")


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

local function make_binding(env, source)
	local command, error = load("return " .. source, nil, "t", env)
	if command == nil then
		command, error = load(source, nil, "t", env)
	end

	return command, error
end

local function parse_bind_for(env, value)
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

	return indexKey, valueKey, make_binding(env, eval)
end

local function bind_value_set(element, binding)
	local currentBindings = reference.currentBindings
	element:AddEventListener("change",
		function(event)
			if not currentBindings.updating then
				currentBindings.deferredSetBindings[binding] = event.parameters.value
			end
		end,
		true)
end

local function bind_submit_form(element, binding)
	local currentBindings = reference.currentBindings
	currentBindings.elementSubmitBindings[tostring(element)] = binding
	element:AddEventListener("submit",
		function(event)
			for _, binding in pairs(binding.submitBindings) do
				local element = Element.As.ElementFormControl(binding.element)
				if element:HasAttribute("bind-submit-dirty") then
					local value = element.value
					currentBindings.deferredSetBindings[binding] = value
				end
			end
		end)
end

local function bind_submit_value_set(element, bindValue)
	local currentBindings = reference.currentBindings
	element:AddEventListener("change",
		function(event)
			if not currentBindings.updating then
				element:SetAttribute("bind-submit-dirty", "")
				local oldCurrentBindings = reference.currentBindings
				reference.currentBindings = currentBindings
				bindValue:clearVariables()
				reference.currentBindings = oldCurrentBindings
			end
		end,
		true)

	local elementSubmitBindings = currentBindings.elementSubmitBindings
	local containerForm = element.parent_node
	while containerForm ~= nil and elementSubmitBindings[tostring(containerForm)] == nil do
		containerForm = containerForm.parent_node
	end
	if containerForm == nil then
		return
	end
	table.insert(elementSubmitBindings[tostring(containerForm)].submitBindings, bindValue)
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


local WeakTable = { __mode = "kv" }

local Binding = {}
function Binding:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	o.variables = {}
	setmetatable(o.variables, WeakTable)
	return o
end

function Binding:clearVariables()
	reference.clear_dependencies(self)
end

function Binding:getValue()
	self:clearVariables()
	reference.currentBinding = self
	local _, value = xpcall(self.binding, module.error_handler)
	if reference.is_reference(value) then
		return #value, value
	else
		return value
	end
	reference.currentBinding = nil
end
function Binding:update() end
function Binding:singleUpdate()
	self:updateChainUp({})
end
-- Recreate context if necessary for single binding (bind-for variables)
function Binding:updateChainUp(chain)
	if self.parent then
		table.insert(chain, { binding = self, index = self.parentIndex })
		self.parent:updateChainUp(chain)
	else
		self:updateChainDown(chain)
	end
end
function Binding:updateChainDown(chain)
	assert(#chain == 0)
	self:update()
end


local ContentBinding = Binding:new()
function ContentBinding:update()
	local value = self:getValue()
	self.element.inner_rml = tostring(value)
end

local AbstractContentBinding = {}
function AbstractContentBinding:new(env, element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.source = element:GetAttribute("bind")
	if o.source:len() == 0 then
		o.source = element.inner_rml
	end
	o.binding = make_binding(env, o.source)
	return o
end

function AbstractContentBinding:apply(element)
	return ContentBinding:new{element = element, binding = self.binding, source = self.source}
end


local ClassBinding = Binding:new()
function ClassBinding:update()
	local value = self:getValue()
	self.element.class_name = self.fixedClass .. " " .. tostring(value)
end

local AbstractClassBinding = {}
function AbstractClassBinding:new(env, element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.source = element:GetAttribute("bind-class")
	o.binding = make_binding(env, o.source)
	return o
end

function AbstractClassBinding:apply(element)
	return ClassBinding:new{element = element, binding = self.binding, fixedClass = element.class_name, source = self.source}
end


local AttributeBinding = Binding:new()
function AttributeBinding:update()
	local value = self:getValue()
	self.element:SetAttribute(self.attribute, tostring(value))
end

local AbstractAttributeBinding = {}
function AbstractAttributeBinding:new(env, element, attribute)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.attribute = attribute
	o.source = element:GetAttribute("bind-attribute-"..attribute)
	o.binding = make_binding(env, o.source)
	return o
end

function AbstractAttributeBinding:apply(element)
	return AttributeBinding:new{element = element, binding = self.binding, attribute = self.attribute, source = self.source}
end


local AbstractEventBinding = {}
function AbstractEventBinding:new(env, element, event)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.event = event
	o.source = element:GetAttribute("bind-event-"..event)
	o.binding = make_binding(env, o.source)
	return o
end

function AbstractEventBinding:apply(element)
	element:AddEventListener(self.event, self.binding, true)
end

local ValueBinding = Binding:new()
function ValueBinding:update()
	local value = self:getValue()
	Element.As.ElementFormControl(self.element).value = value
	self.element:DispatchEvent("change", { value = value })
end

local AbstractValueBinding = {}
function AbstractValueBinding:new(env, element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.source = element:GetAttribute("bind-value")
	o.binding, o.setBinding = make_binding(env, o.source)()
	return o
end

function AbstractValueBinding:apply(element)
	local o = ValueBinding:new{element = element, binding = self.binding, setBinding = self.setBinding, source = self.source}
	bind_value_set(element, o)
	return o
end


local CheckedBinding = Binding:new()
function CheckedBinding:update()
	local value = self:getValue()
	Element.As.ElementFormControlInput(self.element).checked = (value == self.element:GetAttribute("value"))
	self.element:DispatchEvent("change", { value = value })
end

local AbstractCheckedBinding = {}
function AbstractCheckedBinding:new(env, element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.source = element:GetAttribute("bind-checked")
	o.binding, o.setBinding = make_binding(env, o.source)()
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
		local value = self:getValue()
		Element.As.ElementFormControl(self.element).value = value
		self.element:DispatchEvent("change", { value = value })
	end
end

local AbstractSubmitValueBinding = {}
function AbstractSubmitValueBinding:new(env, element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.source = element:GetAttribute("bind-submit-value")
	o.binding, o.setBinding = make_binding(env, o.source)()
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
		local value = self:getValue()
		Element.As.ElementFormControlInput(self.element).checked = (value == self.element:GetAttribute("value"))
		self.element:DispatchEvent("change", { value = value })
	end
end

local AbstractSubmitCheckedBinding = {}
function AbstractSubmitCheckedBinding:new(env, element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.source = element:GetAttribute("bind-submit-checked")
	o.binding, o.setBinding = make_binding(env, o.source)()
	return o
end

function AbstractSubmitCheckedBinding:apply(element)
	local o = SubmitCheckedBinding:new{element = element, binding = self.binding, setBinding = self.setBinding, source = self.source}
	bind_submit_value_set(element, o)
	return o
end


local SubmitBinding = Binding:new()

local AbstractSubmitBinding = {}
function AbstractSubmitBinding:new(env, element)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	return o
end

function AbstractSubmitBinding:apply(element)
	local o = SubmitBinding:new{element = element, submitBindings = {}}
	bind_submit_form(element, o)
	return o
end


local ForBinding = Binding:new()
function ForBinding:update()
	local values, containerReference = self:getValue()
	self.values = values or {}
	if containerReference == nil then
		containerReference = reference.HalfReference:new(self.values)
	end

	local _, valuesLength = xpcall(function() return #self.values end, module.error_handler)
	if not valuesLength then
		return
	end

	local indexKey = self.indexKey
	local valueKey = self.valueKey
	local elements = self.elements

	while valuesLength > #elements do
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
	while valuesLength < #elements do
		if data_binding.onDestroyElement then
			xpcall(data_binding.onDestroyElement, module.error_handler, elements[#elements].element)
		end
		self.element.parent_node:RemoveChild(elements[#elements].element)
		table.remove(elements, #elements)
	end

	local index_ = self.env[indexKey]
	local rIndex_ = self.env.R[indexKey]
	local it_ = self.env[valueKey]
	local rIt_ = self.env.R[valueKey]
	for i = 1, valuesLength do
		local v = self.values[i]
		local forElementBindings = elements[i]

		self.env[indexKey] = i
		self.env.R[indexKey] = nil
		self.env[valueKey] = v
		self.env.R[valueKey] = containerReference[i]

		for _, bindingsGroup in pairs(forElementBindings.bindings) do
			for element, bindings in pairs(bindingsGroup) do
				for j = 1, #bindings do
					bindings[j]:update()
				end
			end
		end
	end
	self.env[indexKey] = index_
	self.env.R[indexKey] = rIndex_
	self.env[valueKey] = it_
	self.env.R[valueKey] = rIt_
end

function ForBinding:updateChainDown(chain)
	local next = chain[#chain]
	if next then
		table.remove(chain, #chain)

		local index_ = self.env[self.indexKey]
		local rIndex_ = self.env.R[self.indexKey]
		local it_ = self.env[self.valueKey]
		local rIt_ = self.env.R[self.valueKey]
		local containerReference = reference.HalfReference:new(self.values)

		self.env[self.indexKey] = next.index
		self.env.R[self.indexKey] = reference.HalfReference:new(next.index)
		self.env[self.valueKey] = self.values[next.index]
		self.env.R[self.valueKey] = containerReference[next.index]

		next.binding:updateChainDown(chain)

		self.env[self.indexKey] = index_
		self.env.R[self.indexKey] = rIndex_
		self.env[self.valueKey] = it_
		self.env.R[self.valueKey] = rIt_
	else
		self:update()
	end
end

local AbstractForBinding = {}
function AbstractForBinding:new(env, element, indirectBindings)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.element = element
	o.indirectBindings = indirectBindings
	o.source = element:GetAttribute("bind-for")
	o.indexKey, o.valueKey, o.binding = parse_bind_for(env, o.source)
	o.env = env
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
		source = self.source,
		env = self.env}
end


module.AbstractContentBinding = AbstractContentBinding
module.AbstractClassBinding = AbstractClassBinding
module.AbstractAttributeBinding = AbstractAttributeBinding
module.AbstractEventBinding = AbstractEventBinding
module.AbstractValueBinding = AbstractValueBinding
module.AbstractCheckedBinding = AbstractCheckedBinding
module.AbstractSubmitValueBinding = AbstractSubmitValueBinding
module.AbstractSubmitCheckedBinding = AbstractSubmitCheckedBinding
module.AbstractSubmitBinding = AbstractSubmitBinding
module.AbstractForBinding = AbstractForBinding

return module
