local module = {}


local function make_lens(ref)
	return
		function() return ref.parent[ref.key] end,
		function(v)
			ref.parent[ref.key] = v
		end
end

local function make_number_lens(ref)
	return
		function() return ref.parent[ref.key] end,
		function(v)
			local v2 = tonumber(v)
			if v2 then
				ref.parent[ref.key] = v2
			end
		end
end

local function make_float_lens(ref, format)
	return
		function() return string.format(format, ref.parent[ref.key]) end,
		function(v)
			local v2 = tonumber(v)
			if v2 then
				ref.parent[ref.key] = v2
			end
		end
end

local function make_boolean_lens(ref)
	return
		function() return ref.parent[ref.key] end,
		function(v)
			ref.parent[ref.key] = v:len() > 0
		end
end

local function make_enum_lens(ref, enum)
	return
		function() return enum[ref.parent[ref.key]] end,
		function(v)
			local v2 = enum[v]
			if v2 then
				ref.parent[ref.key] = v2
			end
		end
end


module.make_lens = make_lens
module.make_number_lens = make_number_lens
module.make_float_lens = make_float_lens
module.make_boolean_lens = make_boolean_lens
module.make_enum_lens = make_enum_lens

return module
