--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Oro harness initializer.
-- Should be require'd first.
--
-- These are just things exposed by the `__ORO__`
-- global but we go ahead and delete it just
-- to help make sure nothing depends on it.
--
-- A few wrappers are also created to make some
-- of the more complicated functions a little more
-- developer-friendly.
--

-- Consume the harness global provided to us by
-- oro-build.c (the harness)
assert(
	_G.__ORO__ ~= nil,
	'do not call oro-build.lua directly!'
)
local ORO = _G.__ORO__
_G.__ORO__ = nil

-- The identifiers are renamed from foo_bar to foobar
-- to follow typical Lua conventions. Conversely, they're
-- named with the underscore in the harness to keep them
-- visually similar to the variables used inside the C source.
local Oro = {
	rootdir = ORO.root_dir,
	bindir = ORO.bin_dir,
	buildscript = ORO.build_script,
	searchpath = ORO.search_path,
	execute = ORO.execute,
	split = ORO.split,
	env = ORO.env,
	arg = ORO.arg
}

-- Pre-load 'lfs' and load 'lua-path', making sure
-- to preserve the search path provided by the harness.
local origpath = package.path
package.path = ORO.root_dir .. '/ext/lua-path/lua/?.lua'
package.loaded.lfs = ORO.lfs
require('path.fs') -- (just asserts that 'lfs' is loaded properly)
Oro.path = (require 'path').new('/')
package.path = origpath

return Oro
