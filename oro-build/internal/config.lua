--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Creates an immutable configuration map
-- that can be extended but never directly
-- modified
--

local util = require 'internal.util'
local tablefunc = util.tablefunc

local wrap_config_fn = nil

local Config = {
	extend = function(self, new_config)
		local t = {}
		for k, v in pairs(self) do t[k] = v end
		for k, v in pairs(new_config) do
			if v == false then v = nil end
			t[k] = v
		end
		return wrap_config_fn(t)
	end,
	default = function(self, k, v)
		if self[k] == nil then
			self[k] = new_config
		end
		return self
	end
}

local function wrap_config(config)
	return setmetatable(
		config,
		{
			__index=Config,
			__newindex=function(self, k, v)
				-- Make sure the config key doesn't conflict
				-- with a method name.
				assert(
					getmetatable(self).__index[k] == nil,
					'cannot set config key to a Config method name: '..tostring(k)
				)
				return rawset(self, k, v)
			end,
			__call=function(self, k)
				-- Make sure the config key isn't part of the
				-- interface, as we don't want to encourage
				-- accidental mis-use.
				assert(
					getmetatable(self).__index[k] == nil,
					'not a config key; use C:'..tostring(k)..'() instead'
				)
				return self[k]
			end
		}
	)
end

wrap_config_fn = wrap_config

return tablefunc(
	wrap_config,
	{ Config = Config }
)
