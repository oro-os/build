--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Checks if a table or userdata value
-- is an instance of a particular class
-- (by comparing __index and the provided
-- metatable)
--

local freeze = require 'internal.util.freeze'

local function isinstance(v, meta)
	assert(meta ~= nil)
	local mt = getmetatable(freeze.unfreeze(v))
	return mt ~= nil and mt.__index == meta
end

return isinstance
