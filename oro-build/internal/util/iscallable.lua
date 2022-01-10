--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Returns true if you can reliably
-- invoke the value as a function
--

local function iscallable(v)
	if type(v) == 'function' then
		return true
	end

	local mt = getmetatable(v)
	return mt ~= nil and (mt.__callable or iscallable(mt.__call))
end

return iscallable
