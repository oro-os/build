--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Protects an object behind a sealed
-- metatable.
--
-- NOTE: Please don't use this as a
--       security mechanism. It should
--       be used as a good-faith deterrent
--       for enforcing conventions or
--       contracts.
--
--       That being said, if `rawset` in
--       the _G context is replaced with
--       the rawset exposed here, it will
--       be VERY hard to bypass.
--

local debug = require 'debug'

local tablefunc = (require 'internal.util').tablefunc

-- A 'private' symbol that cannot be forged.
local protectedsym = {}

local function protect_mt(obj)
	assert(
		type(obj) == 'table' or getmetatable(obj) ~= nil,
		'object must be a table or have a metatable'
	)

	local mt = {
		__index = obj,
		__newindex = function ()
			error 'cannot modify protected table or userdata'
		end,
		__metatable = function ()
			error 'cannot get metatable of protected table or userdata'
		end
	}

	mt[protectedsym] = true

	return setmetatable({}, mt)
end

local real_rawget = rawget
local real_rawset = rawset

local function protected_rawset(o, k, v)
	local mt = debug.getmetatable(o)
	if o ~= nil and real_rawget(mt, protectedsym) == true then
		error 'cannot rawset() a protected table or userdata'
	end
	return real_rawset(o, k, v)
end

return tablefunc(
	protect_mt,
	{
		rawset = protected_rawset
	}
)
