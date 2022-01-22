--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Returns a set of arguments for invoking an
-- Oro build system syscall (usually wrapped
-- via `oro.Rule.somesyscall{}`). Useful for
-- decorating other commands.
--

local Oro = require 'internal.oro'
local P = require 'internal.path'
local freeze = require 'internal.util.freeze'

local function make_syscall(name)
	if type(name) ~= 'string' or #name == 0 then
		error('name must be non-empty string; got'..tostring(name), 2)
	end

	return freeze {
		P.relpath(Oro.absbindir, Oro.absharnesspath),
		'--syscall',
		name
	}
end

return make_syscall
