--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Escapes characters for a Ninja rule
-- (excludes '$')
--

local function escape_ninja(str)
	return str:gsub('[ \n]', '$%0')
end

return escape_ninja
