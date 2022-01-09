--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Wraps a function with a metatable
-- and __index-er so that functions can
-- be member-accessed.
--

local function tablefunc(fn, init)
	assert(init == nil or type(init) == 'table')
	return setmetatable(
		init or {},
		{ __call = function (_, ...) return fn(...) end }
	)
end

return tablefunc
