local reference = require("data_binding_reference")

local module = {}


local function make_lens(ref)
	return
		function() return #ref end,
		function(v)
			reference.set_variable(ref, v)
			reference.dirty_variable(ref)
		end
end

local function make_number_lens(ref)
	return
		function() return #ref end,
		function(v)
			local v2 = tonumber(v)
			if v2 then
				reference.set_variable(ref, v2)
				reference.dirty_variable(ref)
			end
		end
end

local function make_float_lens(ref, format)
	return
		function() return string.format(format, #ref) end,
		function(v)
			local v2 = tonumber(v)
			if v2 then
				reference.set_variable(ref, v2)
				reference.dirty_variable(ref)
			end
		end
end

local function make_boolean_lens(ref)
	return
		function() return #ref end,
		function(v)
			reference.set_variable(ref, v:len() > 0)
			reference.dirty_variable(ref)
		end
end

local function make_enum_lens(ref, enum)
	return
		function() return enum[#ref] end,
		function(v)
			local v2 = enum[v]
			if v2 then
				reference.set_variable(ref, v2)
				reference.dirty_variable(ref)
			end
		end
end


module.make_lens = make_lens
module.make_number_lens = make_number_lens
module.make_float_lens = make_float_lens
module.make_boolean_lens = make_boolean_lens
module.make_enum_lens = make_enum_lens

return module
