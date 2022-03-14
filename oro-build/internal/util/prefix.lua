--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Prefix a string's lines with another string
--

local Oro = require 'internal.oro'

local function prefix(str, pref)
	pref = tostring(pref)
	str = tostring(str)
	local lines = Oro.split(str, '\n')
	for i, v in ipairs(lines) do
		lines[i] = pref .. v
	end
	return table.concat(lines, '\n')
end

return prefix
