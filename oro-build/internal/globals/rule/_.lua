--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Top-level `Rule{}` constructor
--

local freeze = require 'internal.util.freeze'
local flat = require 'internal.util.flat'
local List = require 'internal.util.list'
local Set = require 'internal.util.set'
local shallowclone = require 'internal.util.shallowclone'
local tablefunc = require 'internal.util.tablefunc'
local Path = (require 'internal.path-factory').Path
local isinstance = require 'internal.util.isinstance'

-- https://ninja-build.org/manual.html
local allowed_rule_keys = Set {
	'command', 'depfile', 'deps',
	'msvc_deps_prefix', 'description',
	'dyndep', 'generator',
	'restat', 'rspfile', 'rspfile_content'
}

local Rule = {}
local Build = {}

local function flatten_to_strings(list, newlist)
	if newlist == nil then newlist = {} end
	local i = #newlist
	for v in flat(list) do
		i = i + 1
		if isinstance(v, Path) then
			newlist[i] = v
		else
			newlist[i] = tostring(v)
		end
	end
	return newlist
end

function Rule:clone(opts)
	local new_opts = shallowclone(self.options)

	assert(
		type(opts) == 'table',
		'Rule options (first parameter, or braced invocation) must be table; got ' .. type(opts)
	)

	for k,v in pairs(opts) do
		if not allowed_rule_keys[k] then
			error('invalid Rule{} option: ' .. tostring(k), 2)
		end

		new_opts[k] = flatten_to_strings(v)
	end

	return self.constructor(new_opts)
end

local function make_rule_generator(onrule, onbuild)
	local function make_rule(opts)
		assert(
			type(opts) == 'table',
			'Rule options (first parameter, or braced invocation) must be table; got ' .. type(opts)
		)

		local rule = nil

		local sane_opts = {}

		for k,v in pairs(opts) do
			if not allowed_rule_keys[k] then
				error('invalid Rule{} option: ' .. tostring(k), 2)
			end

			sane_opts[k] = flatten_to_strings(v)
		end

		local function make_build(opts)
			assert(
				type(opts) == 'table',
				'Build options (first parameter, or braced invocation) must be table; got ' .. type(opts)
			)

			-- Guarantee that `out` exists for the build object's
			-- __index and __len metamethods.
			local sane_opts = {out = {}}
			local inputs = List()

			for k,v in pairs(opts) do
				local kt = type(k)

				if kt == 'string' then
					sane_opts[k] = flatten_to_strings(v)
				elseif kt ~= 'number' then
					error('build keys must be strings (or sequential numbers); got ' .. kt, 2)
				end
			end

			for v in flat(opts) do
				if isinstance(v, Path) then
					inputs[nil] = v
				elseif isinstance(v, Build) then
					inputs[nil] = v.options.out
				else
					error(
						'unexpected sequential value; expected Path (from `S` or `B`) or a Build object; got '
						.. type(v),
						2
					)
				end
			end

			inputs = flatten_to_strings(inputs, sane_opts)

			local build = setmetatable(
				{
					options = sane_opts,
					rule = rule
				},
				{
					__index = function(_, k)
						if type(k) == 'number' then
							return sane_opts.out[k]
						end
						return Build[k]
					end,
					__len = function() return #sane_opts.out end
					-- NOTE: Builds are NOT nuclear! This would break flat() calls.
					-- NOTE: Please do NOT add a __name here!
					-- __name = 'Build'
				}
			)

			onbuild(build)

			return freeze(build)
		end

		rule = setmetatable(
			{
				options = sane_opts,
				constructor = make_rule
			},
			{
				__index = Rule,
				__name = 'Rule',
				__call = function (_, ...) return make_build(...) end
			}
		)

		onrule(rule)

		return freeze(rule)
	end

	local function builtin(importpath)
		local factory = require(importpath)
		return factory(onrule, onbuild)
	end

	return tablefunc(
		make_rule,
		{
			escapeall = require 'internal.globals.rule.escapeall',
			escape = require 'internal.globals.rule.escape',
			touch = builtin 'internal.globals.rule.touch',
			pass = builtin 'internal.globals.rule.pass',
			fail = builtin 'internal.globals.rule.fail',
			echo = builtin 'internal.globals.rule.echo',
			cp = builtin 'internal.globals.rule.cp'
		}
	)
end

return tablefunc(
	make_rule_generator,
	{
		Rule = Rule,
		Build = Build
	}
)
