--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Ninja build script file manager
-- and code generator
--

local flat = require 'internal.util.flat'
local Set = require 'internal.util.set'
local isnuclear = require 'internal.util.isnuclear'
local tablefunc = require 'internal.util.tablefunc'

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
	to_stream:write('\n\nninja_required_version = 1.1')

	-- NOTE: this emits the initial ' ' if a value is found.
	local function escape(v, colon)
		-- re-assign here to ignore second returned value
		v = v:gsub(colon and '[ \n:]' or '[ \n]', '$%0')
		return v
	end

	local function emit(v)
		if type(v) == 'table' and not isnuclear(v) then
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
		assert(opts['in'] == nil) -- checked in the `add_build` method
		assert(opts['In'] == nil)

		-- emit
		to_stream:write('\n\nbuild')
		local ignore_keys = {}

		if opts.out ~= nil then
			ignore_keys.out = true
			for v in flat(opts.out) do
				if v then
					to_stream:write(' ')
					to_stream:write(escape(tostring(v), true))
				end
			end
		end

		if opts.out_implicit ~= nil then
			ignore_keys.out_implicit = true
			to_stream:write(' |')
			for v in flat(opts.out_implicit) do
				if v then
					to_stream:write(' ')
					to_stream:write(escape(tostring(v), true))
				end
			end
		end

		to_stream:write(': ')
		to_stream:write(tostring(rule_name))

		for v in flat(opts) do
			if v then
				to_stream:write(' ')
				to_stream:write(escape(tostring(v), true))
			end
		end

		if opts.in_implicit ~= nil then
			ignore_keys.in_implicit = true
			to_stream:write(' |')
			for v in flat(opts.in_implicit) do
				if v then
					to_stream:write(' ')
					to_stream:write(escape(tostring(v), true))
				end
			end
		end

		if opts.in_order ~= nil then
			ignore_keys.in_order = true
			to_stream:write(' ||')
			for v in flat(opts.in_order) do
				if v then
					to_stream:write(' ')
					to_stream:write(escape(tostring(v), true))
				end
			end
		end

		for k, v in pairs(opts) do
			if type(k) == 'string' and not ignore_keys[k] then
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
	assert(self.rules[rule_name] ~= nil, 'unknown rule: ' .. rule_name)
	assert(
		opts['in'] == nil and opts['In'] == nil,
		'do not specify `in` or `In` directly; pass inputs as sequence items instead'
	)

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
