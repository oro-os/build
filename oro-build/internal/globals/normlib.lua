--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- A set of option normalization rules for
-- assisting with error-checking options
-- passed to rule builders.
--

local flat = require 'internal.util.flat'

local ERRSCOPE = 2

local function singleopt_(opts, name, scopeoff)
	local res = nil

	for v in flat{opts[name]} do
		if res ~= nil then
			error('cannot specify more than one `'..tostring(name)..'`', ERRSCOPE + scopeoff)
		end

		res = v
	end

	return res
end

local function singleopt(opts, name)
	return singleopt_(opts, name, 0)
end

local function single(opts, name)
	local res = singleopt_(opts, name, 1)

	if res == nil then
		error('must specify exactly one `'..tostring(name)..'`', ERRSCOPE)
	end

	return res
end

local function singleinputopt_(opts, scopeoff)
	local res = nil

	for v in flat{opts} do
		if res ~= nil then
			error('cannot specify more than one input', ERRSCOPE + scopeoff)
		end

		res = v
	end

	return res
end

local function singleinputopt(opts)
	return singleinputopt_(opts, 0)
end

local function singleinput(opts)
	local res = singleinputopt_(opts, 1)

	if res == nil then
		error('must specify exactly one input', ERRSCOPE)
	end

	return res
end

return {
	single = single,
	singleopt = singleopt,
	singleinput = singleinput,
	singleinputopt = singleinputopt
}
