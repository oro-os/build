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

local function shallowclone(tbl, to)
	if to == nil then to = {} end
	for k,v in pairs(tbl) do to[k] = v end
	return to
end

return shallowclone
