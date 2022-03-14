--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Cross-platform `cp` rule
--

local Oro = require 'internal.oro'
local P = require 'internal.path'
local freeze = require 'internal.util.freeze'
local flatten = require 'internal.util.flatten'
local List = require 'internal.util.list'

local rule = {
	options = {
		command = {
			P.relpath(Oro.absbindir, Oro.absharnesspath),
			'--syscall',
			'cp',
			'$in',
			'$outleaf'
		},
		description = 'COPY $in -> $outleaf'
	}
}

local function make_rule(onrule, onbuild)
	return function(opts)
		if type(opts) ~= 'table' then
			error('options must be a table; got '..tostring(opts), 2)
		end

		onrule(rule)

		local outputs = flatten{opts.out}
		local inputs = flatten{opts}

		if #outputs ~= 1 then
			error('must specify exactly one `out` to oro.Rule.cp{}', 1)
		end

		local outleaf = outputs[1]

		if #inputs == 0 then
			error('must specify at least one input to oro.Rule.cp{}', 1)
		elseif #inputs > 1 then
			local base = outputs[1]
			outputs = List()

			for _, v in ipairs(inputs) do
				outputs[nil] = base:join(v:basename())
			end
		end

		opts = {
			in_implicit = opts.in_implicit,
			in_order = opts.in_order,
			out = outputs,
			outleaf = outleaf,

			inputs
		}

		onbuild {
			rule = rule,
			options = opts
		}

		return freeze{opts.out, opts.out_implicit}
	end
end

return make_rule
