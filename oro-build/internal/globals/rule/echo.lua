--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Cross-platform `fail` rule
-- (does nothing, returns 1)
--

local Oro = require 'internal.oro'
local P = require 'internal.path'
local freeze = require 'internal.util.freeze'

local rule = {
	options = {
		command = {
			P.relpath(Oro.absbindir, Oro.absharnesspath),
			'--syscall',
			'echo',
			'$message'
		},
		description = 'ECHO'
	}
}

local function make_rule(onrule, onbuild)
	return function(opts)
		if type(opts) ~= 'table' then
			error('options must be a table; got '..tostring(opts), 2)
		end

		if opts.message == nil then
			error('missing \'message\' option', 2)
		end

		onrule(rule)

		onbuild {
			rule = rule,
			options = opts
		}

		return freeze{opts.out, opts.out_implicit}
	end
end

return make_rule
