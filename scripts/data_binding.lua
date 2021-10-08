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

function bind(bindings, element, useBindingId)
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

			bindings.direct[element] = {
				["for"] = {binding = make_binding(binding), variables = variables, subBindings = {}}
			}

			-- Other binding on this element will apply to its for elements
			useBindingId = true
			-- Don't set the binding id again below
			bindingItSet = true
		else
			elementBindings["for"] = {binding = make_binding(binding), variables = variables, subBindings = {}}
		end

		for _, child in pairs(element.child_nodes) do
			bind(bindings, child, true)
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
			bind(bindings, child, useBindingId)
		end
	end

	if next(elementBindings) ~= nil then
		if useBindingId then
			if not id then
				id = bindingId
				bindingId = bindingId + 1
				element:SetAttribute("bind-id", id)
			end
			bindings.indirect[id] = elementBindings
		else
			bindings.direct[element] = elementBindings
		end
	end
end

function update_bindings(bindings)
	for element, elementBindings in pairs(bindings.direct) do
		if elementBindings["for"] then
			local variables = elementBindings["for"].variables
			local newValues = elementBindings["for"].binding()
			local id = element:GetAttribute("bind-id")

			local forElements = {}
			for i, sibling in pairs(element.parent_node.child_nodes) do
				if sibling:GetAttribute("bind-for-parent") == id then
					table.insert(forElements, sibling)
				end
			end

			while #newValues > #forElements do
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
				table.insert(forElements, forElement)
			end
			while #newValues < #forElements do
				element.parent_node:RemoveChild(forElements[#forElements])
				table.remove(forElements, #forElements)
			end

			local index_ = _G[variables.index]
			local it_ = _G[variables.it]
			for i, newValue in pairs(newValues) do
				local forElement = forElements[i]
				_G[variables.index] = i
				_G[variables.it] = newValue

				update_element_bindings(bindings, forElement)
			end
			_G[variables.index] = index_
			_G[variables.it] = it_
		else
			if elementBindings.class then
				local newValue = elementBindings.class.binding()
				local fixedClass = element:GetAttribute("fixed_class")
				if not fixedClass then
					fixedClass = ""
				end
				element.class_name = fixedClass .. " " .. newValue
			end

			for attribute, binding in pairs(elementBindings.attributes or {}) do
				local newValue = binding.binding()
				element:SetAttribute(attribute, newValue)
			end

			if elementBindings.content then
				local newValue = elementBindings.content.binding()
				element.inner_rml = newValue
			end
		end
	end
end

function update_element_bindings(bindings, element)
	local id = element:GetAttribute("bind-id")
	local elementBindings = bindings.indirect[tonumber(id)]

	if elementBindings then
		if element:GetAttribute("bind-for") and elementBindings["for"] then
			local variables = elementBindings["for"].variables
			local newValues = elementBindings["for"].binding()
			local id = element:GetAttribute("bind-id")

			local forElements = {}
			for i, sibling in pairs(element.parent_node.child_nodes) do
				if sibling:GetAttribute("bind-for-parent") == id then
					table.insert(forElements, sibling)
				end
			end

			while #newValues > #forElements do
				element.parent_node:InsertBefore(element.owner_document:CreateElement(element.tag_name), element)
				local forElement = element.previous_sibling
				for k, v in pairs(element.attributes) do
					forElement:SetAttribute(k, v)
				end
				forElement:RemoveAttribute("bind-for")
				forElement:SetAttribute("bind-for-parent", id)
				forElement.inner_rml = element.inner_rml
				table.insert(forElements, forElement)
			end
			while #newValues < #forElements do
				element.parent_node:RemoveChild(forElements[#forElements])
				table.remove(forElements, #forElements)
			end

			local index_ = _G[variables.index]
			local it_ = _G[variables.it]
			for i, newValue in pairs(newValues) do
				local forElement = forElements[i]
				_G[variables.index] = i
				_G[variables.it] = newValue

				update_element_bindings(bindings, forElement)
			end
			_G[variables.index] = index_
			_G[variables.it] = it_
		else
			if elementBindings.class then
				local newValue = elementBindings.class.binding()
				element.class_name = element:GetAttribute("fixed_class") .. " " .. newValue
			end

			for attribute, binding in pairs(elementBindings.attributes or {}) do
				local newValue = binding.binding()
				element:SetAttribute(attribute, newValue)
			end

			if elementBindings.content then
				local newValue = elementBindings.content.binding()
				element.inner_rml = newValue
			end
		end
	end

	if not element:GetAttribute("bind-for") then
		-- Copy child_nodes to make sure insertions by update_element_bindings
		-- don't mess up iteration
		local children = {}
		for i, child in pairs(element.child_nodes) do
			-- bind-for children are handled above
			if not child:GetAttribute("bind-for-parent") then
				table.insert(children, child)
			end
		end

		for i, child in pairs(children) do
			update_element_bindings(bindings, child)
		end
	end
end

return {
	bind = bind,
	update_bindings = update_bindings
}
