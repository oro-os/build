--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- Flat array iterator with special
-- handling for paths
--

local util = require 'internal.util'
local Path = (require 'internal.path').Path

local isinstance = util.isinstance

local function flat(t)
	local stack = {{t, 1}}

	local function iter(i)
		local v = i[1][i[2]]
		i[2] = i[2] + 1
		return v
	end

	return function()
		local v = stack[#stack]
		if v == nil then return end
		v = iter(v)

		while v == nil do
			stack[#stack] = nil
			v = stack[#stack]
			if v == nil then return nil end
			v = iter(v)
		end

		while type(v) == 'table' do
			-- Special handling for Path objects
			if isinstance(v, Path) then
				break
			end

			itr = {v, 1}
			local nv = iter(itr)
			if nv ~= nil then
				stack[#stack + 1] = itr
				v = nv
			end
		end

		return v
	end
end

return flat
