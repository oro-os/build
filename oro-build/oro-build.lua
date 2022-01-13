--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Main entry point for the Oro build system
--

-- Set the locale for the entire program
os.setlocale('C', 'all')

-- Initialize the Oro harness (MUST come before
-- any other `require`s)
local Oro = require 'internal.oro'

-- Include internal code
local Ninjafile = require 'internal.ninja'
local make_context = require 'internal.context'
local Set = require 'internal.util.set'
local List = require 'internal.util.list'
local unpack = require 'internal.util.unpack'
local P = require 'internal.path'
local keys = require 'internal.util.keys'

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

-- Run main build script
local ctx = make_context {
	source_directory = P.dirname(Oro.absbuildscript),
	build_directory = Oro.absbindir,
	config = raw_config,
	env = Oro.env
}

ctx.root_module:dofile(Oro.absbuildscript)

local unreferenced = Set(keys(raw_config))
for k,v in pairs(ctx.referenced_config) do
	unreferenced[k] = nil
end
unreferenced = keys(unreferenced)
if #unreferenced > 0 then
	print('some configuration values specified on the command line were unused:')
	for _, v in ipairs(unreferenced) do
		print('\t'..tostring(v))
	end
end

-- Add default generation rule (so that any config files
-- are checked in order to re-config)
ctx.ninja:add_rule('_oro_build_regenerator', {
	command = { 'cd', P.currentdir(), '&&', 'env', '_ORO_BUILD_REGEN=1', Oro.buildscript, Oro.bindir, unpack(Oro.arg) },
	description = { 'Reconfigure', Oro.bindir },
	generator = '1'
})

local config_deps = List()
local build_offset = P.relpath(Oro.absbindir, Oro.abssrcdir)
local function add_build_dep(srcpath)
	config_deps[nil] = P.join(build_offset, srcpath)
end

add_build_dep(P.join(Oro.rootdir, 'oro-build.lua'))
add_build_dep(P.join(Oro.rootdir, 'oro-build.c'))

for _, srcpath in ipairs(keys(ctx.modules)) do
	add_build_dep(P.relpath(Oro.abssrcdir, srcpath))
end

ctx.ninja:add_build('_oro_build_regenerator', {
	out = 'build.ninja',
	config_deps
})

-- Add compilation database generation rule.
ctx.ninja:add_rule('_oro_build_compdb', {
	command = { 'ninja', '-t', 'compdb', '>', '$out' },
	description = 'COMPDB $out'
})

ctx.ninja:add_build('_oro_build_compdb', {
	in_implicit = 'build.ninja',
	out = 'compile_commands.json'
})

-- Dump Ninja file to build directory
local ninja_out = P.join(Oro.bindir, 'build.ninja')
local ostream = io.open(ninja_out, 'wb')
ctx.ninja:write(ostream)
ostream:close()

-- Done!
io.stderr:write('OK, configured: ' .. Oro.absbindir .. '\n')
if os.getenv('_ORO_BUILD_REGEN') == nil then
	io.stderr:write('You should now run: ninja -C \''..Oro.bindir..'\'\n')
end
