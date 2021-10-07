--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- Main entry point for the Oro build system
--

-- The `Oro` table is the set of utilities coming from
-- the C runtime (oro-build.c).
if type(_G.Oro) ~= 'table' then
	error '`Oro` not defined; do not call oro-build.lua directly!'
end

-- Set the locale for the entire program
os.setlocale('C', 'all')

-- Pre-load 'lfs' and load 'lua-path'
package.path = Oro.root_dir .. '/ext/lua-path/lua/?.lua'
package.loaded.lfs = Oro.lfs
require('path.fs') -- (just asserts that 'lfs' is loaded properly)
Oro.path = (require 'path').new('/')

-- Re-set the inclusion path to the Oro build library
-- as well as the source path.
package.path = (
	Oro.root_dir .. '/?.lua'
	.. ';' .. Oro.root_dir .. '/?/_.lua'
)

-- Include internal code
local util = require 'internal.util'
local Ninjafile = require 'internal.ninja'
local make_path_factory = require 'internal.path'
local flat = require 'internal.flat'
local wrap_environ = require 'internal.environ'
local wrap_config = require 'internal.config'

local Set = util.Set
local isinstance = util.isinstance
local List = util.List

-- Specialized output function
-- (prefixes the calling file's name)
local had_config_output = false
local function oro_print(...)
	if not had_config_output then io.stderr:write('\n') end
	had_config_output = true

	local info = debug.getinfo(2, 'S')
	local source = info.source:sub(2)
	io.stderr:write('-- ')
	io.stderr:write(source)
	io.stderr:write(':')
	for i = 1, select('#', ...) do
		local x = select(i, ...)
		io.stderr:write(' ')
		io.stderr:write(tostring(x))
	end
	io.stderr:write('\n')
end

local rule_cursor = 1
local function make_rule_factory(on_rule, on_entry)
	local function Rule(rule_opts)
		assert(type(rule_opts) == 'table', 'rule options must be a table')
		assert(rule_opts.command ~= nil, 'Rule() options must include `command` field')

		local name = '_R_' .. tostring(rule_cursor)
		rule_cursor = rule_cursor + 1

		on_rule(name, rule_opts)

		return function(entry_opts)
			assert(type(entry_opts) == 'table', 'build options must be a table')
			assert(entry_opts.out ~= nil, 'build options must include `out` field')

			on_entry(name, entry_opts)

			return entry_opts.out
		end
	end

	return Rule
end

local function make_env(source_dir, build_dir, environ, config, on_rule, on_entry)
	assert(Oro.path.isabs(source_dir))
	assert(Oro.path.isabs(build_dir))
	local env = {}

	-- Lua builtins
	env.assert = assert
	env.ipairs = ipairs
	env.pairs = pairs
	env.error = error
	env.getmetatable = getmetatable
	env.setmetatable = setmetatable
	env.next = next
	env.pcall = pcall
	env.xpcall = xpcall
	env.rawequal = rawequal
	env.rawset = rawset
	env.rawget = rawget
	env.select = select
	env.tonumber = tonumber
	env.tostring = tostring
	env.type = type

	-- Lua libraries (be careful with which are whitelisted)
	env.table = table
	env.string = string

	-- Build-related functions
	env.Rule = make_rule_factory(on_rule, on_entry)
	env.S = make_path_factory(build_dir, source_dir)
	env.B = make_path_factory(build_dir, build_dir)

	-- Extra utilities
	env.print = oro_print
	env.Set = Set
	env.List = List
	env.execute_immediately = Oro.execute
	env.E = environ
	env.C = config

	return env
end

-- Read config variables from the command line
local raw_config = {}
for _, arg in ipairs(Oro.arg) do
	local k, v = select(3, arg:find('^([^=]+)=(.*)$'))
	if k ~= nil then
		raw_config[k] = v
	end
end

-- Initialize build script environment
io.stderr:write('(Re-)configuring project...\n')

local ninja = Ninjafile()

-- Make sure the build script follows the name convention
if select(2, Oro.path.splitext(Oro.build_script)) ~= '.oro' then
	error('build scripts must have `.oro\' extension: ' .. tostring(Oro.build_script))
end

local env = make_env(
	Oro.path.dirname(Oro.path.abspath(Oro.build_script)),
	Oro.path.abspath(Oro.bin_dir),
	wrap_environ(Oro.env),
	wrap_config(raw_config),
	function(rule_name, opts) ninja:add_rule(rule_name, opts) end,
	function(rule_name, opts) ninja:add_build(rule_name, opts) end
)

local config_deps = {
	env.S(Oro.build_script),
	env.B'.oro-build'
}

-- Run build configuration script
local chunk, err = loadfile(Oro.build_script, 'bt', env)
assert(chunk ~= nil, err)

for output in flat{chunk()} do
	ninja:add_default(output)
end

if not ninja:has_defaults() then
	error 'no default rules returned from build script; did you forget to `return`?'
end

-- Add default generation rule (so that any config files
-- are checked in order to re-config)
local ninja_out = Oro.bin_dir .. '/build.ninja'

ninja:add_rule('_oro_build_regenerator', {
	command = { 'cd', Oro.path.currentdir(), '&&', 'env', '_ORO_BUILD_REGEN=1', arg },
	description = { 'Reconfigure', Oro.bin_dir },
	generator = '1'
})

ninja:add_build('_oro_build_regenerator', {
	out = ninja:add_default(env.B'build.ninja'),
	In = config_deps
})

-- Dump Ninja file to build directory
local ostream = io.open(ninja_out, 'wb')
ninja:write(ostream)
ostream:close()

-- Done!
if had_config_output then io.stderr:write('\n') end
io.stderr:write('OK, configured: ' .. Oro.path.abspath(Oro.bin_dir) .. '\n')
if os.getenv('_ORO_BUILD_REGEN') == nil then
	io.stderr:write('You should now run: ninja -C \''..Oro.bin_dir..'\'\n')
end
