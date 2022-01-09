--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Simple Set utility.
--

local function Set(list)
	local d = {}
	for _, v in ipairs(list) do d[v] = true end
	return d
end

return Set
