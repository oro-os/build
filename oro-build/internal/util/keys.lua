--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Returns a list of keys in a table.
--
-- By default, omits numeric keys.
-- Pass `true` as the second parameter
-- to include them.
--

local function keys(tbl, all)
	local t = {}

	local i = 0
	if all then
		for k, _ in pairs(tbl) do
			if type(k) ~= 'number' then
				i = i + 1
				t[i] = k
			end
		end
	else
		for k, _ in pairs(tbl) do
			i = i + 1
			t[i] = k
		end
	end

	return t, i
end

return keys
