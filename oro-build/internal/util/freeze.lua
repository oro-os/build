--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Freezes an entire object, recursively,
-- except for its methods.
--
-- NOTE: Do not use this for security.
-- NOTE: There are VERY subtle ways
-- NOTE: to bypass frozen object statuses
-- NOTE: in script contexts that I won't
-- NOTE: document here. Just know that it's
-- NOTE: possible, in the same vein that
-- NOTE: accessing private members in C++
-- NOTE: without invoking UB is possible;
-- NOTE: only the most masochistic Lua
-- NOTE: programmers would figure out how
-- NOTE: to do it.
-- NOTE:
-- NOTE: Just heed my warning - do NOT use
-- NOTE: this for anything that must have
-- NOTE: security guarantees. This is merely
-- NOTE: to enforce a contract to a reasonable
-- NOTE: degree of confidence, in order to
-- NOTE: discourage script contexts from doing
-- NOTE: something annoying or footgun-ey.
-- NOTE:
-- NOTE: To security researchers attempting
-- NOTE: to figure it out, I'll give you a
-- NOTE: hint: Rule{}{{__tostring}}.
--

local debug = require 'debug'

local tablefunc = require 'internal.util.tablefunc'
local iscallable = require 'internal.util.iscallable'

local function unfreeze(obj)
	local mt = getmetatable(obj)
	if type(mt) == 'table' and mt.__frozen then
		return debug.getmetatable(obj).__this
	end

	return obj
end

local function freeze(obj, newindex)
	if obj == nil then return nil end

	local objt = type(obj)
	if objt == 'function' then
		return function (this, ...)
			this = unfreeze(this)
			return obj(this, ...)
		end
	end

	if objt ~= 'table' and objt ~= 'userdata' then
		return obj
	end

	local omt = getmetatable(obj)
	if type(omt) ~= 'table' then omt = nil end

	-- don't create nested frozen objects
	if omt and omt.__frozen then return obj end

	local proxy = {}

	local mt = {
		__this = obj,
		__index = function(_, k)
			return freeze(obj[k])
		end,
		__newindex = function()
			error('cannot modify frozen object', 2)
		end,
		__tostring = function ()
			return tostring(obj)
		end,
		__pairs = function()
			local obj_next = pairs(obj)

			local function protected_next(this, key)
				local k, v = obj_next(obj, unfreeze(key))
				return freeze(k), freeze(v)
			end

			return protected_next, proxy, nil
		end,
		__eq = function(_, y)
			return obj == unfreeze(y)
		end,
		__len = function()
			return freeze(#obj)
		end
	}

	-- some callers might want to allow assigning new values
	-- so switch out __newindex if that's the case
	if newindex then
		mt.__newindex = function(_, ...)
			return newindex(...)
		end
	end

	local callable = false
	if iscallable(obj) then
		mt.__call = function(_, this, ...)
			this = unfreeze(this)
			return obj(this, ...)
		end

		callable = true
	end

	local name = nil
	if omt then name = omt.__name end

	mt.__metatable = setmetatable({}, {
		__index = function(_, k)
			if k == '__frozen' then return true end
			if k == '__name' then return name end
			-- used by iscallable() to check callability of frozen objects
			-- without needing to unfreeze them (since we also depend on
			-- iscallable)
			if k == '__callable' then return callable end
			error('attempt to index a frozen object\'s metatable', 2)
		end,
		__newindex = function()
			error('attempt to assign to a frozen object\'s metatable', 2)
		end
	})

	return setmetatable(proxy, mt)
end

local real_rawset = rawset
local function frozen_rawset(obj, k, v)
	local mt = getmetatable(obj)
	if type(mt) == 'table' and mt.__frozen then
		error('cannot modify frozen object', 2)
	end
	return real_rawset(obj, k, v)
end

return tablefunc(
	freeze,
	{
		unfreeze = unfreeze,
		rawset = frozen_rawset
	}
)
