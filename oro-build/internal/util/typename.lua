--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- type.name() helper
--

local function typename(v)
	local mt = getmetatable(v)
	if mt and mt.__name then
		return mt.__name
	end
	return type(v)
end

return typename
