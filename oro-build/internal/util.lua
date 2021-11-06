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

local function isnuclear(v)
	local meta = getmetatable(v)
	return meta ~= nil and meta.__name ~= nil
end

local ListType = {}

function ListType:pop()
	local len = #self
	if len == 0 then return nil end
	local v = self[len]
	self[len] = nil
	return v
end

local function List(list)
	-- copy for posterity
	local t = {}

	if type(list) == 'table' then
		for i,v in ipairs(list) do
			t[i] = v
		end
	end

	return setmetatable(t, {
		__index = ListType,
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

local function shallowclone(tbl)
	local t = {}
	for k,v in pairs(tbl) do t[k] = v end
	return t
end

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

return {
	Set = Set,
	isinstance = isinstance,
	isnuclear = isnuclear,
	unpack = unpack,
	List = List,
	tablefunc = tablefunc,
	shallowclone = shallowclone,
	keys = keys
}
