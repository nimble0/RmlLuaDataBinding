local data_binding = require("data_binding")

return function(element)
	for _, element in pairs(element:QuerySelectorAll("[submit-on-blur]")) do
		element:AddEventListener(
			"blur",
			function(_, element)
				for i = 1, #data_binding.allBindings do
					local bindings = data_binding.allBindings[i]
					bindings:dirtySetBinding(element, "bind-submit-value")
					bindings:dirtyBinding(element, "bind-submit-value")
				end
			end,
			false)
		element:AddEventListener(
			"keydown",
			function(event, element)
				if event.parameters.key_identifier == rmlui.key_identifier.RETURN then
					element:Blur()
				end
			end,
			false)
	end
end

