--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Wraps the standard `table` Lua library
-- with a few extra methods.
--

local flat = require 'internal.util.flat'
local List = require 'internal.util.list'

local stdtable = _G.table;
assert(stdtable ~= nil)

-- Make sure that what we expect to find
-- on the real 'table' library is actually there.
local function ensure(name)
	return (
		stdtable[name]
		or error('not a `table` standard library function: ' .. tostring(name))
	)
end

return {
	-- Lua built-ins
	-- NOTE: omit `unpack` here in lieu of the polyfill
	insert = ensure 'insert',
	concat = ensure 'concat',
	sort = ensure 'sort',
	move = ensure 'move',
	pack = ensure 'pack',
	remove = ensure 'remove',

	-- Additional utilities
	flat = flat,
	flatten = require 'internal.util.flatten',
	keys = require 'internal.util.keys',
	shallowclone = require 'internal.util.shallowclone',
	unpack = require 'internal.util.unpack'
}
