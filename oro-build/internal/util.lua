--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- Various utility structures and functions
--

local function Set(list)
	local d = {}
	for _, v in ipairs(list) do d[v] = true end
	return d
end

local function isinstance(v, meta)
	assert(meta ~= nil)
	local mt = getmetatable(v)
	return mt ~= nil and mt.__index == meta
end

local function List(list)
	-- copy for posterity
	local t = {}

	for i,v in ipairs(list) do
		t[i] = v
	end

	return setmetatable(t, {
		__newindex = function(self, k, v)
			if k == nil then
				k = #self + 1
			end
			assert(type(k) == 'number', 'key must be a number')
			assert(k == #self + 1, 'cannot set out-of-bounds index')
			rawset(self, k, v)
		end
	})
end

local unpack = table.unpack or unpack or error('no unpack!')

local function tablefunc(fn, init)
	assert(init == nil or type(init) == 'table')
	return setmetatable(
		init or {},
		{ __call = function (_, ...) return fn(...) end }
	)
end

return {
	Set = Set,
	isinstance = isinstance,
	unpack = unpack,
	List = List,
	tablefunc = tablefunc
}
