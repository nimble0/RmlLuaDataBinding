return function(element)
	for _, element in pairs(element:QuerySelectorAll("[limit-input]")) do
		local limitInput = element:GetAttribute("limit-input")
		element:SetAttribute("old-value", element:GetAttribute("value") or "")
		element:AddEventListener(
			"change",
			function(event, element)
				local new = event.parameters.value
				local old = element:GetAttribute("old-value")
				if new and (not tostring(new):match(limitInput)) then
					event:StopImmediatePropagation()
					element:SetAttribute("value", old)
					element:DispatchEvent("change", { value = old })
				else
					element:SetAttribute("old-value", new or "")
				end
			end,
			true)
	end
end

