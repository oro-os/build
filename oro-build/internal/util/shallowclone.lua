--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Shallow clones a table
--

local function shallowclone(tbl)
	local t = {}
	for k,v in pairs(tbl) do t[k] = v end
	return t
end

return shallowclone
