--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Checks if a string ends with another string
--

local function endswith(str, endstr)
	if str == '' then return endstr == '' end
	return endstr == '' or string.sub(str, -string.len(endstr)) == endstr
end

return endswith
