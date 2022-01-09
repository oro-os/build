--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Checks if a table is a 'nuclear' object.
--
-- I've invented the _internal_ concept
-- of 'nuclear' objects, which are tables
-- that have a metatable with a __name field.
--
-- These are interesting because they indicate
-- terminals during a recursive iteration
-- (e.g. in `util.flat()`). Nuclear objects
-- wouldn't be recursed into.
--
-- For example, Path objects are 'nuclear'.
--

local function isnuclear(v)
	local meta = getmetatable(v)
	return meta ~= nil and meta.__name ~= nil
end

return isnuclear
