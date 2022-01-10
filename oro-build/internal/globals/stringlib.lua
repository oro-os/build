--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Wraps the standard `string` Lua library
-- with a few extra methods.
--

local Oro = require 'internal.oro'
local pad = require 'internal.util.pad'

local stdstring = _G.string;
assert(stdstring ~= nil)

-- Make sure that what we expect to find
-- on the real 'string' library is actually there.
local function ensure(name)
	return (
		stdstring[name]
		or error('not a `string` standard library function: ' .. tostring(name))
	)
end

return {
	-- Lua built-ins
	match = ensure 'match',
	gmatch = ensure 'gmatch',
	lower = ensure 'lower',
	format = ensure 'format',
	byte = ensure 'byte',
	find = ensure 'find',
	char = ensure 'char',
	rep = ensure 'rep',
	unpack = ensure 'unpack',
	packsize = ensure 'packsize',
	reverse = ensure 'reverse',
	dump = ensure 'dump',
	pack = ensure 'pack',
	len = ensure 'len',
	gsub = ensure 'gsub',
	sub = ensure 'sub',
	upper = ensure 'upper',

	-- Additional utilities
	padleft = pad.left,
	padright = pad.right,
	split = Oro.split -- implemented in C since it's actually easier in C
}
