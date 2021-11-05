local bindingId = 0

function trim(s)
   return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end

function split(s, d)
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

function make_binding(source)
	local command, error = load("return " .. source)
	if command == nil then
		command, error = load(source)
	end

	return command, error
end

function parse_bind_for(value)
	local a, b = value:find("%sin%s")
	local variables_ = split(value:sub(1, a), ",")

	local variables = nil
	if #variables_ == 0 then
		variables = {
			index = "i",
			it = "it"
		}
	elseif #variables_ == 1 then
		variables = {
			index = "i",
			it = trim(variables_[1])
		}
	else
		variables = {
			index = trim(variables_[1]),
			it = trim(variables_[2])
		}
	end
	local eval = value:sub(b + 1)

	return variables, eval
end

function make_lens(table, key)
	return
		function() return table[key] end,
		function(v) table[key] = v end
end

function make_number_lens(table, key)
	return
		function() return table[key] end,
		function(v)
			local v2 = tonumber(v)
			if v2 then
				table[key] = v2
			end
		end
end

function make_float_lens(table, key, format)
	return
		function() return string.format(format, table[key]) end,
		function(v)
			local v2 = tonumber(v)
			if v2 then
				table[key] = v2
			end
		end
end

function make_boolean_lens(table, key)
	return
		function() return table[key] end,
		function(v)
			if v:len() > 0 then
				table[key] = true
			else
				table[key] = false
			end
		end
end

function make_enum_lens(table, key, enum)
	return
		function() return enum[table[key]] end,
		function(v)
			local v2 = enum[v]
			if v2 then
				table[key] = enum[v]
			end
		end
end

function bind_value_set(element, bindValue)
	element:AddEventListener("change",
		function(event)
			if not element:GetAttribute("ignore-change") then
				bindValue.set(event.parameters.value)
				bindValue.value = bindValue.get()
			end
		end,
		true)
end

function bind(
	directBindings,
	indirectBindings,
	element,
	useBindingId
)
	local elementBindings = {}

	local bindingIdSet = false
	local id = false

	if element:HasAttribute("bind-for") then
		local variables, binding = parse_bind_for(element:GetAttribute("bind-for"))
		element:SetClass("bind-for-base", true)

		-- If useBindingId is true then bind-id will be set further down
		if not useBindingId then
			id = bindingId
			bindingId = bindingId + 1
			element:SetAttribute("bind-id", id)

			directBindings[element] = {
				["for"] = {
					binding = make_binding(binding),
					variables = variables,
					elements = {}
				}
			}

			-- Other binding on this element will apply to its for elements
			useBindingId = true
			-- Don't set the binding id again below
			bindingItSet = true
		else
			elementBindings["for"] = {
				binding = make_binding(binding),
				variables = variables,
				elements = {}
			}
		end

		for _, child in pairs(element.child_nodes) do
			bind(directBindings, indirectBindings, child, true)
		end
	end

	local bindClass = element:GetAttribute("bind-class")
	if bindClass then
		element:SetAttribute("fixed-class", element.class_name)
		elementBindings.class = {binding = make_binding(bindClass)}
	end

	local attributes = {}
	for attribute, bind in pairs(element.attributes) do
		if attribute:sub(1, 15) == "bind-attribute-" then
			local bindAttribute = attribute:sub(16)
			attributes[bindAttribute] = {binding = make_binding(bind)}
		end
	end
	if next(attributes) ~= nil then
		elementBindings.attributes = attributes
	end

	local events = {}
	for attribute, bind in pairs(element.attributes) do
		if attribute:sub(1, 11) == "bind-event-" then
			local event = attribute:sub(12)
			events[event] = {binding = bind}
			if not useBindingId then
				element:AddEventListener(event, bind, true)
			end
		end
	end
	if next(events) ~= nil then
		elementBindings.events = events
	end

	local bindValue = element:GetAttribute("bind-value")
	if bindValue then
		local get, set = make_binding(bindValue)()
		elementBindings.value = {get = get, set = set}
		if not useBindingId then
			bind_value_set(element, elementBindings.value)
		end
	end

	local bindChecked = element:GetAttribute("bind-checked")
	if bindChecked then
		local get, set = make_binding(bindChecked)()
		elementBindings.checked = {get = get, set = set}
		if not useBindingId then
			bind_value_set(element, elementBindings.checked)
		end
	end

	if element:HasAttribute("bind") then
		local bind = element:GetAttribute("bind")
		if bind:len() == 0 then
			elementBindings.content = {binding = make_binding(element.inner_rml)}
		else
			elementBindings.content = {binding = make_binding(bind)}
		end
	-- Can't nest content bindings because inner_rml is replaced by a content binding
	else
		for _, child in pairs(element.child_nodes) do
			bind(directBindings, indirectBindings, child, useBindingId)
		end
	end

	if next(elementBindings) ~= nil then
		if useBindingId then
			if not id then
				id = bindingId
				bindingId = bindingId + 1
				element:SetAttribute("bind-id", id)
			end
			indirectBindings[id] = elementBindings
		else
			directBindings[element] = elementBindings
		end
	end
end

function clone_binding(binding)
	local clone = {}

	for k, v in pairs(binding) do
		local bindingClone = {}
		for k2, v2 in pairs(v) do
			bindingClone[k2] = v2
		end
		clone[k] = bindingClone
	end

	if binding["for"] then
		clone["for"].elements = {}
	end

	if binding.attributes then
		clone.attributes = {}
		for k, v in pairs(binding.attributes) do
			local bindingClone = {}
			for k2, v2 in pairs(v) do
				bindingClone[k2] = v2
			end
			clone.attributes[k] = bindingClone
		end
	end

	if binding.events then
		clone.events = {}
		for k, v in pairs(binding.events) do
			local bindingClone = {}
			for k2, v2 in pairs(v) do
				bindingClone[k2] = v2
			end
			clone.events[k] = bindingClone
		end
	end

	return clone
end

function bind_for_child(
	directBindings,
	indirectBindings,
	element
)
	local id = tonumber(element:GetAttribute("bind-id"))

	local elementBindings = clone_binding(indirectBindings[id] or {})

	for event, binding in pairs(elementBindings.events or {}) do
		element:AddEventListener(event, binding.binding, true)
	end

	if elementBindings.value then
		bind_value_set(element, elementBindings.value)
	end

	if elementBindings.checked then
		bind_value_set(element, elementBindings.checked)
	end

	elementBindings["for"] = nil
	elementBindings.element = element
	elementBindings.childBindings = {}
	if not element.bind then
		for _, child in pairs(element.child_nodes) do
			bind_for_sub_element(elementBindings.childBindings, indirectBindings, child)
		end
	end

	table.insert(directBindings, elementBindings)
end

function bind_for_sub_element(
	directBindings,
	indirectBindings,
	element
)
	local id = tonumber(element:GetAttribute("bind-id"))
	local bindings = clone_binding(indirectBindings[id] or {})

	if next(bindings) ~= nil then
		directBindings[element] = bindings

		for event, binding in pairs(bindings.events or {}) do
			element:AddEventListener(event, binding.binding, true)
		end
	end

	if bindings and bindings.value then
		bind_value_set(element, bindings.value)
	end

	if bindings and bindings.checked then
		bind_value_set(element, bindings.checked)
	end

	if not bindings.bind and not bindings["for"] then
		for _, child in pairs(element.child_nodes) do
			bind_for_sub_element(directBindings, indirectBindings, child)
		end
	end
end

function update_binding(elementBindings, indirectBindings, element)
	if elementBindings["for"] then
		local variables = elementBindings["for"].variables
		local newValues = elementBindings["for"].binding()
		local elements = elementBindings["for"].elements
		local id = element:GetAttribute("bind-id")

		while #newValues > #elements do
			element.parent_node:InsertBefore(element.owner_document:CreateElement(element.tag_name), element)
			local forElement = element.previous_sibling
			for k, v in pairs(element.attributes) do
				forElement:SetAttribute(k, v)
			end
			forElement:RemoveAttribute("bind-for")
			forElement:SetAttribute("bind-for-parent", id)
			forElement.class_name = element.class_name
			forElement:SetClass("bind-for-base", false)
			forElement.inner_rml = element.inner_rml
			bind_for_child(elements, indirectBindings, forElement)
		end
		while #newValues < #elements do
			element.parent_node:RemoveChild(elements[#elements].element)
			table.remove(elements, #elements)
		end

		local index_ = _G[variables.index]
		local it_ = _G[variables.it]
		for i, newValue in pairs(newValues) do
			local forElementBindings = elements[i]
			_G[variables.index] = i
			_G[variables.it] = newValue

			update_binding(forElementBindings, indirectBindings, forElementBindings.element)
			for childElement, childBindings in pairs(forElementBindings.childBindings) do
				update_binding(childBindings, indirectBindings, childElement)
			end
		end
		_G[variables.index] = index_
		_G[variables.it] = it_
	else
		if elementBindings.class then
			local newValue = elementBindings.class.binding()
			if newValue ~= elementBindings.class.value then
				elementBindings.class.value = newValue
				local fixedClass = element:GetAttribute("fixed_class")
				if not fixedClass then
					fixedClass = ""
				end
				element.class_name = fixedClass .. " " .. newValue
			end
		end

		for attribute, binding in pairs(elementBindings.attributes or {}) do
			local newValue = binding.binding()
			if newValue ~= binding.value then
				binding.value = newValue
				element:SetAttribute(attribute, newValue)
			end
		end

		if elementBindings.value then
			local lens = elementBindings.value
			local newValue = lens.get()
			if newValue ~= elementBindings.value.value then
				elementBindings.value.value = newValue
				element:SetAttribute("ignore-change", "")
				Element.As.ElementFormControl(element).value = newValue
				element:DispatchEvent("change", { value = newValue })
				element:RemoveAttribute("ignore-change")
			end
		end

		if elementBindings.checked then
			local lens = elementBindings.checked
			local newValue = lens.get()
			if newValue ~= elementBindings.checked.value then
				elementBindings.checked.value = newValue
				element:SetAttribute("ignore-change", "")
				Element.As.ElementFormControlInput(element).checked = newValue == element:GetAttribute("value")
				element:DispatchEvent("change", { value = newValue })
				element:RemoveAttribute("ignore-change")
			end
		end

		if elementBindings.content then
			local newValue = elementBindings.content.binding()
			if newValue ~= elementBindings.content.value then
				elementBindings.content.value = newValue
				element.inner_rml = newValue
			end
		end
	end
end

function make_bindings(bindings, element)
	bindings.direct = {}
	bindings.indirect = {}
	bind(bindings.direct, bindings.indirect, element)
end

function update_bindings(bindings)
	for element, elementBindings in pairs(bindings.direct) do
		update_binding(elementBindings, bindings.indirect, element)
	end
end

return {
	make_bindings = make_bindings,
	update_bindings = update_bindings,
	make_lens = make_lens,
	make_number_lens = make_number_lens,
	make_boolean_lens = make_boolean_lens,
	make_enum_lens = make_enum_lens,
}
