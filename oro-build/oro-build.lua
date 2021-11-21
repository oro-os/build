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
local P = Oro.path -- cleans up the source considerably

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
local List = util.List
local unpack = util.unpack
local isinstance = util.isinstance
local shallowclone = util.shallowclone
local tablefunc = util.tablefunc
local isnuclear = util.isnuclear
local relpath = make_path_factory.relpath

-- Standard library extensions
-- NOTE: These extensions might be exposed to
--       user scripts, depending on the library
--       Make sure the functions don't allow
--       breaking out of the sandbox or have
--       any side effects.
string.split = Oro.split
string.lpad = util.lpad
string.rpad = util.rpad
table.flat = flat
table.keys = util.keys
table.shallowclone = shallowclone
table.unpack = unpack -- just to be sure.

function table.flatten(t)
	local res = List()
	for v in flat(t) do res[nil] = v end
	return res
end

-- The env stack is used by the prefix functions
-- instead of creating new prefix functions for
-- each environment. This allows cached scripts
-- to have functions called in various contexts
-- without needing to be re-initialized each time.
local env_stack = List()

-- Specialized output function
-- (prefixes the calling file's name)
local had_config_output = false
local function make_oro_print(source_override)
	local function oro_print(...)
		if not had_config_output then io.stderr:write('\n') end
		had_config_output = true

		local source = source_override
		if source == nil then
			local info = debug.getinfo(2, 'S')
			source = info.source:sub(2)
		end

		local prefix = '-- ' .. source .. ':'
		io.stderr:write(prefix)
		local args = {...}
		for _, x in ipairs(args) do
			local linedelim = ' '
			for _, line in ipairs(Oro.split(tostring(x), '\n')) do
				io.stderr:write(linedelim)
				io.stderr:write(tostring(line))
				linedelim = '\n' .. prefix .. ' '
			end
		end
		io.stderr:write('\n')
	end

	return oro_print
end

local function escape_ninja(str)
	return str:gsub('[ \n]', '$%0')
end

local function escape_ninja_all(str)
	return str:gsub('[$ \n]', '$%0')
end

local rule_cursor = 1
local function make_rule_factory(on_rule, on_entry)
	local Rule = {}
	local make_rule = nil

	function Rule:clone()
		local opts = {}
		for k, v in pairs(self) do
			opts[k] = v
		end

		return make_rule(opts)
	end

	make_rule = function(rule_opts)
		assert(type(rule_opts) == 'table', 'rule options must be a table')
		assert(rule_opts.command ~= nil, 'Rule() options must include `command` field')

		local name = '_R_' .. tostring(rule_cursor)
		rule_cursor = rule_cursor + 1

		on_rule(name, rule_opts)

		local function make_build(_, entry_opts)
			assert(type(entry_opts) == 'table', 'build options must be a table')
			assert(entry_opts.out ~= nil, 'build options must include `out` field')

			on_entry(name, entry_opts)

			return entry_opts.out
		end

		return setmetatable(
			rule_opts,
			{
				__index = Rule,
				__call = make_build
			}
		)
	end

	return tablefunc(
		make_rule,
		{
			escape = escape_ninja,
			escapeall = escape_ninja_all
		}
	)
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
local function on_ninja_rule(rule_name, opts) ninja:add_rule(rule_name, opts) end
local function on_ninja_build(rule_name, opts) ninja:add_build(rule_name, opts) end

local function internal_build_path(pth)
	return P.normalize(
		relpath(
			P.abspath(Oro.bin_dir),
			P.abspath(pth)
		)
	)
end

local function internal_build_root_path(pth)
	return internal_build_path(P.join(Oro.root_dir, pth))
end

local config_deps = List{
	'.oro-build',
	internal_build_root_path 'oro-build.c',
	internal_build_root_path 'oro-build.lua',
	internal_build_root_path 'internal/config.lua',
	internal_build_root_path 'internal/environ.lua',
	internal_build_root_path 'internal/flat.lua',
	internal_build_root_path 'internal/ninja.lua',
	internal_build_root_path 'internal/path.lua',
	internal_build_root_path 'internal/util.lua'
}

local envstack_getters = {
	C = 'config',
	E = 'environ',
	S = 'source_factory',
	B = 'build_factory'
}

local function pushenv(env, context, name)
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
	env.type = tablefunc(
		type,
		{ isnuclear = isnuclear }
	)

	-- Generic utilities
	env.print = make_oro_print(name)
	env.Set = Set
	env.List = List
	env.execute_immediately = Oro.execute
	env.search_path = Oro.search_path

	-- Build config facilities
	env.Rule = make_rule_factory(on_ninja_rule, on_ninja_build)

	env.Config = function (t)
		if isinstance(t, wrap_config.Config) then
			return t:extend{}
		end

		return wrap_config(t or {})
	end

	-- Prefix / variable functions
	env.S = prefixS
	env.B = prefixB
	env.E = prefixE
	env.C = prefixC

	-- Lua libraries (be careful with which are whitelisted)
	env.table = table
	env.string = string

	env_stack[nil] = {
		config = context.config,
		environ = context.environ,
		build_factory = make_path_factory(
			P.abspath(context.build_dir),
			P.abspath(Oro.bin_dir)),
		source_factory = make_path_factory(
			P.abspath(context.source_dir),
			P.abspath(Oro.bin_dir))
	}

	-- This should never happen.
	assert(getmetatable(env) == nil, 'cowardly refusing to overwrite env metatable')

	-- Create env-stack proxy for prefix functions
	return setmetatable(env, {
		__index = function(_, k)
			local getter = envstack_getters[k]
			return getter and env_stack[#env_stack][getter] or nil
		end
	})
end

local function popenv()
	env_stack:pop()
end

local require_cache = {}

local function run_build_script(build_script, context)
	-- Make sure the build script follows the name convention
	if select(2, P.splitext(build_script)) ~= '.oro' then
		error('build scripts must have `.oro\' extension: ' .. tostring(build_script))
	end

	assert(not P.isabs(build_script))
	assert(P.normalize(build_script):sub(1, 2) ~= '..')
	assert(not P.isabs(context.source_dir))
	assert(not P.isabs(context.build_dir))

	local env = pushenv({}, context)

	env.require = function(script)
		local overrides = {}

		if type(script) == 'table' then
			assert(
				#script == 1,
				'`require\' with table must only have one position element; got '..tonumber(#script)
			)

			overrides = script
			script = script[1]
		end

		local original_script = script
		assert(type(script) == 'string', '`require\'d script filenames must be strings')

		-- validate overrides
		assert(
			overrides.config == nil
			or isinstance(overrides.config, wrap_config.Config),
			'`config\' override in `require\' must be an instance of Config'
		)
		assert(
			overrides.env == nil
			or isinstance(overrides.env, wrap_environ.Environ),
			'`env\' override in `require\' must be an instance of Environ'
		)

		-- Lua pattern matching is a bit underpowered,
		-- so we use some primitive checks to enforce
		-- /^\.?[\w_-]+(\.[\w_-]+)*$/
		assert(
			script:find('^[%w%._-]+$') ~= nil and script:find('%.%.') == nil,
			'`require\'d script filename is invalid: ' .. script
		)

		if script:sub(1, 1) == '.' then
			-- Relative source import
			script = script:sub(2)

			-- check for `require '.'`
			-- TODO this is a really shoddy and weak check (e.g. require[[./]]
			--      would bypass it). There needs to be a check with the resolved
			--      script to make sure it's not the currently running script.
			assert(#script > 0, 'cannot `require\' the current directory: .')

			-- TODO Normalize and make sure that it doesn't traverse upward.
			-- TODO (this might need a realpath() call due to rascals trying
			-- TODO to symlink)

			-- resolve build path
			local search_path = (
				P.normalize(P.join(context.source_dir, './?.oro'))
				.. ';' .. P.normalize(P.join(context.source_dir, './?/build.oro'))
			)

			local discovered, attempted = package.searchpath(
				script,
				search_path
			)

			if discovered == nil then
				error(
					'`require\'d path not found: ' .. original_script
					.. '\n\n' .. attempted
				)
			end

			discovered = P.normalize(discovered)

			-- build nested context
			local context = shallowclone(context)

			context.config = overrides.config or context.config
			context.environ = overrides.env or context.environ
			context.source_dir = P.normalize(P.join(context.source_dir, P.dirname(discovered)))
			context.build_dir = P.normalize(P.join(context.build_dir, P.dirname(discovered)))

			-- immutable-ize context
			context.config = context.config:extend{}
			context.environ = context.environ:extend{}

			-- process the config
			return run_build_script(discovered, context)
		else
			-- Library import

			-- disallow internal imports
			if script:find('%._') ~= nil then
				error(
					'`require\'d standard library path not allowed (`_\' prefix indicates internal module): '
					.. script
				)
			end

			local internal_require = nil

			-- resolve build path
			internal_require = function(script)
				local cached = require_cache[script]
				if cached ~= nil then return unpack(cached) end

				local search_path = (
					P.normalize(P.join(Oro.root_dir, 'lib/?.lua'))
					.. ';' .. P.normalize(P.join(Oro.root_dir, 'lib/?/_.lua'))
				)

				local discovered, attempted = package.searchpath(
					script,
					search_path
				)

				if discovered == nil then
					error(
						'`require\'d standard library path not found: ' .. original_script
						.. '\n\n' .. attempted
					)
				end

				discovered = P.normalize(discovered)
				config_deps[nil] = internal_build_path(discovered)

				-- execute directly
				local libG = pushenv(shallowclone(_G), context, script:gsub('%._', '.'))
				libG.require = internal_require
				local chunk, err = loadfile(discovered, 'bt', libG)
				assert(chunk ~= nil, err)
				local vals = {chunk()}
				popenv()
				require_cache[script] = vals
				return unpack(vals)
			end

			return internal_require(script)
		end
	end

	-- Append the build script as a dependency
	config_deps[nil] = relpath(
		P.abspath(Oro.bin_dir),
		P.abspath(build_script)
	)

	-- Run build configuration script
	local chunk, err = loadfile(build_script, 'bt', env)
	assert(chunk ~= nil, err)

	local vals = {chunk()}
	popenv()
	return unpack(vals)
end

-- Run main build script
local exports = {
	run_build_script(
		Oro.build_script,
		{
			source_dir = P.dirname(Oro.build_script),
			build_dir = Oro.bin_dir,
			config = wrap_config(raw_config),
			environ = wrap_environ(Oro.env)
		}
	)
}

-- Add all returned targets as ninja defaults
for output in flat(exports) do
	if (
		isinstance(output, make_path_factory.Path)
		or type(output) == 'string'
	) then
		ninja:add_default(output)
	end
end

if not ninja:has_defaults() then
	error 'no default rules returned from build script; did you forget to `return`?'
end

-- Add default generation rule (so that any config files
-- are checked in order to re-config)
local ninja_out = Oro.bin_dir .. '/build.ninja'

ninja:add_rule('_oro_build_regenerator', {
	command = { 'cd', P.currentdir(), '&&', 'env', '_ORO_BUILD_REGEN=1', Oro.build_script, Oro.bin_dir, unpack(Oro.arg) },
	description = { 'Reconfigure', Oro.bin_dir },
	generator = '1'
})

ninja:add_build('_oro_build_regenerator', {
	out = ninja:add_default('build.ninja'),
	In = config_deps
})

-- Add compilation database generation rule.
ninja:add_rule('_oro_build_compdb', {
	command = { 'ninja', '-t', 'compdb', '>', '$out' },
	description = 'COMPDB $out'
})

ninja:add_build('_oro_build_compdb', {
	in_implicit = 'build.ninja',
	out = ninja:add_default('compile_commands.json')
})

-- Dump Ninja file to build directory
local ostream = io.open(ninja_out, 'wb')
ninja:write(ostream)
ostream:close()

-- Done!
if had_config_output then io.stderr:write('\n') end
io.stderr:write('OK, configured: ' .. P.abspath(Oro.bin_dir) .. '\n')
if os.getenv('_ORO_BUILD_REGEN') == nil then
	io.stderr:write('You should now run: ninja -C \''..Oro.bin_dir..'\'\n')
end
