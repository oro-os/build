--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Creates a phony rule and (fake) build target
-- to be used by exports, as one-off commands.
--

local isinstance = require 'internal.util.isinstance'
local Path = (require 'internal.path-factory').Path
local List = require 'internal.util.list'
local flat = require 'internal.util.flat'
local freeze = require 'internal.util.freeze'

local function make_phony_factory(makephony)
	return function(...)
		local deps = List()
		local arguments = List()

		for v in flat{...} do
			arguments[nil] = v
			if isinstance(v, Path) then
				deps[nil] = v
			end
		end

		if #arguments == 0 then
			error('must specify at least one argument to oro.phony{}', 2)
		end

		return freeze(makephony(arguments, deps))
	end
end

return make_phony_factory
