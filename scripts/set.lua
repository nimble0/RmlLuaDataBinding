local function set_insert(t, v, i)
	for i = 1, #t do
		if t[i] == v then
			return
		end
	end
	if i then
		table.insert(t, i, v)
	else
		table.insert(t, v)
	end
end

local function set_remove(t, v)
	for i = 1, #t do
		if t[i] == v then
			table.remove(t, i)
			return
		end
	end
end

return {
	insert = set_insert,
	remove = set_remove
}
