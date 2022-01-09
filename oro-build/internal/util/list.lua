--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- A lightweight List utility.
-- Can be used most places tables are
-- accepted.
--
-- l = List()
-- l = List({'existing', 'items'})
--
-- l[nil] = 'append item'   -- push item
-- l:pop()                  -- remove+return last item
--

local List = {}

function List:pop()
	local len = #self
	if len == 0 then return nil end
	local v = self[len]
	self[len] = nil
	return v
end

local function make_list(list)
	-- copy for posterity
	local t = {}

	if type(list) == 'table' then
		for i,v in ipairs(list) do
			t[i] = v
		end
	end

	return setmetatable(t, {
		__index = List,
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

return make_list
