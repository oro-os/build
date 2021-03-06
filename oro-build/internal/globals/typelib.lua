--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Nuclear object type tests
--
-- NOTE: To be clear, this has nothing to do with
-- NOTE: the `type` builtin extensions. These are
-- NOTE: helper utilities that live on the global
-- NOTE: `oro` object and check for Oro-specific types.
--

local isinstance = require 'internal.util.isinstance'
local rulelib = require 'internal.globals.rule'
local pathlib = require 'internal.path-factory'

local TypeLib = {}

function TypeLib.isbuild(v)
	return isinstance(v, rulelib.Build)
end

function TypeLib.isrule(v)
	return isinstance(v, rulelib.Rule)
end

function TypeLib.ispath(v)
	return isinstance(v, pathlib.Path)
end

return TypeLib
