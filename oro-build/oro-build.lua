--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

-- The `Oro` table is the set of utilities coming from
-- the C runtime (oro-build.c).
if type(_G.Oro) ~= 'table' then
	error '`Oro` not defined; do not call oro-build.lua directly!'
end

-- Set the locale for the entire program
os.setlocale('C', 'all')

-- Set the require() search path
package.path = (
	Oro.root_dir .. '/ext/lua-path/lua/?.lua'
	.. ';' .. Oro.root_dir .. '/lib/?.lua'
	.. ';' .. Oro.root_dir .. '/lib/?/_.lua'
	.. ';' .. package.path
)

-- Pre-load 'lfs' and load 'lua-path'
package.loaded.lfs = Oro.lfs
require('path.fs') -- (just asserts that 'lfs' is loaded properly)
Oro.path = (require 'path').new('/')

-- Forward declare metatables
local Ninja = {}
local Path = {}

-- Utilities
local unpack = table.unpack or unpack or error('no unpack!')

local function isinstance(v, meta)
	local mt = getmetatable(v)
	return mt ~= nil and mt.__index == meta
end

local function Set(list)
	local d = {}
	for _, v in ipairs(list) do d[v] = true end
	return d
end

local function List(list)
	-- copy for posterity
	local t = {}

	for i,v in ipairs(list) do
		t[i] = v
	end

	return setmetatable(t, {
		__newindex = function(self, k, v)
			if k == nil then
				k = #self + 1
			end
			assert(type(k) == 'number', 'key must be a number')
			assert(k == #self + 1, 'cannot set out-of-bounds index')
			rawset(self, k, v)
		end
	})
end

local function flat(t)
	local stack = {{t, 1}}

	local function iter(i)
		local v = i[1][i[2]]
		i[2] = i[2] + 1
		return v
	end

	return function()
		local v = stack[#stack]
		if v == nil then return end
		v = iter(v)

		while v == nil do
			stack[#stack] = nil
			v = stack[#stack]
			if v == nil then return nil end
			v = iter(v)
		end

		while type(v) == 'table' do
			-- Special handling for Path objects
			if isinstance(v, Path) then
				break
			end

			itr = {v, 1}
			local nv = iter(itr)
			if nv ~= nil then
				stack[#stack + 1] = itr
				v = nv
			end
		end

		return v
	end
end

local ninja_rule_keys = Set {
	'name', -- NOTE: *not* a real Ninja key; it's ignored by the emitter.
	'command', 'depfile', 'deps', 'msvc_deps_prefix',
	'description', 'dyndep', 'generator', 'in',
	'in_newline', 'out', 'restat', 'rspfile',
	'rspfile_content'
}

function Ninja:write(to_stream)
	to_stream:write('#\n# THIS IS A GENERATED BUILD CONFIGURATION\n')
	to_stream:write('# DO NOT MANUALLY EDIT!\n#')

	-- NOTE: this emits the initial ' ' if a value is found.
	local function escape(v, colon)
		-- re-assign here to ignore second returned value
		v = v:gsub(colon and '[ \n:]' or '[ \n]', '$%0')
		return v
	end

	local function emit(v)
		if type(v) == 'table' then
			for v in flat(v) do
				to_stream:write(' ')
				to_stream:write(escape(tostring(v)))
			end
		elseif v ~= nil then
			to_stream:write(' ')
			to_stream:write(tostring(v))
		end
	end

	for name, opts in pairs(self.rules) do
		-- sanity checks
		assert(opts.command ~= nil)

		-- emit
		to_stream:write('\n\nrule ')
		to_stream:write(tostring(name))

		for opt_name, opt_val in pairs(opts) do
			-- special case: 'name' is not a real
			-- ninja key but is used internally
			-- to create a cleaner API.
			if opt_name ~= 'name' then
				to_stream:write('\n  ')
				to_stream:write(tostring(opt_name))
				to_stream:write(' =')
				emit(opt_val)
			end
		end
	end

	for _, build_def in ipairs(self.builds) do
		local rule_name, opts = build_def.rule, build_def.opts

		-- sanity checks
		assert(rule_name ~= nil)
		assert(opts ~= nil)
		assert(type(opts.out) == 'table')
		assert(#(opts.out) > 0)

		-- emit
		-- TODO enforce that build-line paths are Path objects.
		to_stream:write('\n\nbuild')
		local ignore_keys = {}

		for v in flat(opts.out) do
			ignore_keys.out = true

			to_stream:write(' ')
			to_stream:write(escape(tostring(v), true))
		end

		if type(opts.out_implicit) == 'table' then
			ignore_keys.out_implicit = true

			to_stream:write(' |')
			for v in flat(opts.out_implicit) do
				to_stream:write(' ')
				to_stream:write(escape(tostring(v), true))
			end
		end

		to_stream:write(': ')
		to_stream:write(tostring(rule_name))

		if type(opts['in']) == 'table' then
			ignore_keys['in'] = true

			for v in flat(opts['in']) do
				to_stream:write(' ')
				to_stream:write(escape(tostring(v), true))
			end
		end

		if type(opts.in_implicit) == 'table' then
			ignore_keys.in_implicit = true

			to_stream:write(' |')
			for v in flat(opts.in_implicit) do
				to_stream:write(' ')
				to_stream:write(escape(tostring(v), true))
			end
		end

		if type(opts.in_order) == 'table' then
			ignore_keys.in_order = true

			to_stream:write(' ||')
			for v in flat(opts.in_order) do
				to_stream:write(' ')
				to_stream:write(escape(tostring(v), true))
			end
		end

		for k, v in pairs(opts) do
			if not ignore_keys[k] then
				to_stream:write('\n  ')
				to_stream:write(k)
				to_stream:write(' =')
				emit(v)
			end
		end
	end

	to_stream:write('\n\n# END OF BUILD SCRIPT\n')
end

function Ninja:add_rule(opts)
	assert(opts.name ~= nil, 'Ninja:add_rule() options must include `name` field')
	assert(opts.command ~= nil, 'Ninja:add_rule() options must include `command` field')
	assert(self.rules[opts.name] == nil, 'duplicate rule registered: ' .. opts.name)

	self.rules[opts.name] = opts

	for k, _ in pairs(opts) do
		assert(ninja_rule_keys[k], 'invalid Ninja rule option name: '..k)
	end

	return self
end

function Ninja:add_build(rule_name, opts)
	-- convert 'In' to 'in'
	-- this is a convenience since `in` is a keyword in
	-- lua and thus cannot be used as a key in a literal
	-- table.
	if opts.In ~= nil then
		assert(opts['in'] == nil, 'cannot specify both `In` and `in`')
		opts['in'] = opts.In
		opts.In = nil
	end

	local function sanitize_key(k)
		local v = opts[k]

		if v == nil then return end

		if isinstance(v, Path) then
			v = tostring(v)
		end

		if type(v) == 'string' then
			v = {v}
		end

		assert(type(v) == 'table')

		local t, i = {}, 1
		for nv in flat(v) do
			t[i] = tostring(nv)
			i = i + 1
		end

		opts[k] = t
	end

	if opts then
		sanitize_key('out')
		sanitize_key('out_implicit')
		sanitize_key('in')
		sanitize_key('in_implicit')
		sanitize_key('in_order')
	end

	assert(self.rules[rule_name] ~= nil, 'unknown rule: ' .. rule_name)
	assert(type(opts.out) == 'table', 'missing required option `out`, or it is not a table')
	assert(#(opts.out) > 0, 'must specify at least one `out` path (got empty table instead)')

	table.insert(self.builds, {rule=rule_name, opts=opts})

	return self
end

local function Ninjafile()
	local ninja = {
		rules = {},
		builds = {}
	}

	return setmetatable(ninja, {__index = Ninja})
end

local function oro_print(...)
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

local anonymous_rule_cursor = 1

local function make_rule_factory(on_rule, on_entry)
	local function Rule(rule_opts)
		assert(type(rule_opts) == 'table', 'rule options must be a table')
		assert(rule_opts.command ~= nil, 'Rule() options must include `command` field')

		if rule_opts.name == nil then
			rule_opts.name = '_R_' .. tostring(anonymous_rule_cursor)
			anonymous_rule_cursor = anonymous_rule_cursor + 1
		end

		on_rule(rule_opts)

		return function(entry_opts)
			assert(type(entry_opts) == 'table', 'build options must be a table')
			assert(entry_opts.out ~= nil, 'build options must include `out` field')

			on_entry(rule_opts.name, entry_opts)

			return entry_opts.out
		end
	end

	return Rule
end

local function pathstring(x, allow_base)
	-- TODO we kind of naively assume that a function
	-- TODO here is a path factory; we should probably
	-- TODO have a PathFactory metatable and isinstance()
	-- TODO check it.
	assert(allow_base or type(s) ~= 'function', 'cannot pass a path factory (`O` or `S`) to :path()')
	if type(x) == 'function' then return x('.')._base end
	return isinstance(x, Path) and x[prop] or x
end

function Path:path(s)
	if s == nil then
		return self._path
	else
		return setmetatable(
			{ _path = pathstring(s), _base = self._base },
			{ __index = Path, __tostring = Path.__tostring }
		)
	end
end

function Path:base(s)
	if s == nil then
		return self._base
	else
		return setmetatable(
			{ _path = self._path, _base = pathstring(s, true) },
			{ __index = Path, __tostring = Path.__tostring }
		)
	end
end

function Path:append(s)
	return self:path(self._path .. pathstring(s))
end

function Path:ext(s)
	local base, ext = Oro.path.splitext(self._path)
	if s == nil then
		return ext
	else
		return self:path(base .. s)
	end
end

function Path:__tostring()
	local path, base = self._path, self._base

	if #base == 0 then return path end

	return Oro.path.normalize(
		(Oro.path.has_dir_end(path) and Oro.path.ensure_dir_end or Oro.path.remove_dir_end)(
			Oro.path.join(base, path)
		)
	)
end

local function make_path_factory(from, retarget_to)
	assert(Oro.path.isabs(from))
	assert(Oro.path.isabs(retarget_to))

	-- strip common prefix
	local from_root, retg_root = nil, nil
	while #from > 0 and #retarget_to > 0 do
		-- yes, Oro.path.join('/', '/foo') results in '/foo'.
		from_root, from = Oro.path.splitroot(Oro.path.join('/', from))
		retg_root, retarget_to = Oro.path.splitroot(Oro.path.join('/', retarget_to))

		if from_root ~= retg_root then
			break
		end
	end

	-- Re-write difference in path depth with `..`'s.
	local joins = {}
	while #from > 0 do
		from_root, from = Oro.path.splitroot(Oro.path.join('/', from))
		joins[#joins + 1] = '..'
	end

	-- Construct the new base path
	local base = Oro.path.remove_dir_end(Oro.path.join(unpack(joins) or '', retarget_to))

	return function(path)
		-- Translate `S'/foo'` to `S'./foo'`
		if Oro.path.isabs(path) then
			-- this is a bit magic, sorry.
			-- basically, the lua-path function `splitroot`
			-- splits a path by
			path = (Oro.path.has_dir_end(path) and Oro.path.ensure_dir_end or Oro.path.remove_dir_end)(
				Oro.path.join(Oro.path.splitroot(path))
			)
		end

		return setmetatable(
			{
				_path = path,
				_base = base,
			},
			{
				__index = Path,
				__tostring = Path.__tostring
			}
		)
	end
end

local function make_env(source_dir, build_dir, on_rule, on_entry)
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

	return env
end

-- Initialize build script environment
print('(Re-)configuring project...\n')

local ninja = Ninjafile()

local env = make_env(
	Oro.path.dirname(Oro.path.abspath(Oro.build_script)),
	Oro.path.abspath(Oro.bin_dir),
	function(opts) ninja:add_rule(opts) end,
	function(rule_name, opts) ninja:add_build(rule_name, opts) end
)

local config_deps = {
	env.S(Oro.build_script),
	env.B'.oro-build'
}

-- Run build configuration script
local chunk, err = loadfile(Oro.build_script, 'bt', env)
assert(chunk ~= nil, err)
chunk()

-- Add default generation rule (so that any config files
-- are checked in order to re-config)
local ninja_out = Oro.bin_dir .. '/build.ninja'

ninja:add_rule {
	name = '_oro_build_regenerator',
	command = { 'cd', Oro.path.currentdir(), '&&', 'env', '_ORO_BUILD_REGEN=1', arg },
	description = { 'Reconfigure', Oro.bin_dir },
	generator = '1'
}

ninja:add_build('_oro_build_regenerator', {
	out = env.B'build.ninja',
	In = config_deps
})

-- Dump Ninja file to build directory
local ostream = io.open(ninja_out, 'wb')
ninja:write(ostream)
ostream:close()

-- Done!
print('\nOK, configured: ' .. Oro.path.abspath(Oro.bin_dir))
print()

if os.getenv('_ORO_BUILD_REGEN') == nil then
	print('You may now run `ninja` in that directory to build.')
end
