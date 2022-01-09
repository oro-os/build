--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Creates an immutable environment map
-- that can be extended but never directly
-- modified
--

local tablefunc = require 'internal.util.tablefunc'

local Environ = {} -- dummy metatable

local function wrap_environ(environ)
	return setmetatable({}, {
		__metatable = Environ,
		__index = setmetatable(
			{
				extend = function(self, new_env)
					local t = {}
					for k, v in pairs(self) do t[k] = v end
					for k, v in pairs(new_env) do
						if v == false then v = nil end
						t[k] = v
					end
					return wrap_environ(t)
				end
			},
			{
				__index = function(self, k)
					-- We use a function here to prevent rascals
					-- from modifying the underlying environment
					-- object
					return environ[k]
				end
			}
		),
		__newindex = function()
			error('re-assigning environment variables is not allowed; use ENV:extend() instead')
		end,
		__call = function(self, k)
			return self[k]
		end,
		__pairs = function(self)
			return function(self_, k)
				return next(environ, k)
			end
		end
	})
end

return tablefunc(
	wrap_environ,
	{ Environ = Environ }
)
