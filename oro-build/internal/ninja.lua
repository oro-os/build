--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- Ninja build script file manager
-- and code generator
--

local util = require 'internal.util'
local flat = require 'internal.flat'
local Path = (require 'internal.path').Path

local Set = util.Set
local isinstance = util.isinstance
local tablefunc = util.tablefunc

local Ninja = {}

local ninja_rule_keys = Set {
	'command', 'depfile', 'deps', 'msvc_deps_prefix',
	'description', 'dyndep', 'generator', 'in',
	'in_newline', 'out', 'restat', 'rspfile',
	'rspfile_content'
}

function Ninja:write(to_stream)
	to_stream:write('#\n# THIS IS A GENERATED BUILD CONFIGURATION')
	to_stream:write('\n# DO NOT MANUALLY EDIT!\n#')
	to_stream:write('\nninja_required_version = 1.1')

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
			to_stream:write('\n  ')
			to_stream:write(tostring(opt_name))
			to_stream:write(' =')
			emit(opt_val)
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

	if #self.defaults > 0 then
		to_stream:write('\n')

		for _, def_output in ipairs(self.defaults) do
			to_stream:write('\ndefault ')
			to_stream:write(escape(tostring(def_output)))
		end
	end

	to_stream:write('\n\n# END OF BUILD SCRIPT\n')
end

function Ninja:add_rule(name, opts)
	assert(opts.command ~= nil, 'Ninja:add_rule() options must include `command` field')
	assert(self.rules[name] == nil, 'duplicate rule registered: ' .. name)

	self.rules[name] = opts

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
			v = {tostring(v)}
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

function Ninja:add_default(output)
	self.defaults[#self.defaults + 1] = output
	return output
end

function Ninja:has_defaults()
	return #self.defaults > 0
end

local function Ninjafile()
	local ninja = {
		rules = {},
		builds = {},
		defaults = {}
	}

	return setmetatable(ninja, {__index = Ninja})
end

return tablefunc(
	Ninjafile,
	{ Ninja = Ninja }
)
