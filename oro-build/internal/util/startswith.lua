--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Checks if a string starts with another string
--

local function startswith(str, start)
	if str == '' then return start == '' end
	return start == '' or string.sub(str, 1, string.len(start)) == start
end

return startswith
