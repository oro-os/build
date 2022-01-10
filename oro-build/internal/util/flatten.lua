--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- A one-shot version of `flat()` that returns a List.
--

local flat = require 'internal.util.flat'
local List = require 'internal.util.list'

local function flatten(t)
	local res = List()
	for v in flat(t) do res[nil] = v end
	return res
end

return flatten
