--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Creates a single object that can be
-- re-used as a build script context's
-- `_G` (global) object.
--
-- This effectively builds up the scripting
-- context and all available build script
-- functionality / the build system API,
-- deferring any build config operations
-- to the passed in "cb" (callback) object.
--
-- This means the global object itself is
-- stateless.
--

local Oro = require 'internal.oro'
local iscallable = require 'internal.util.iscallable'
local tablefunc = require 'internal.util.tablefunc'
local make_require = require 'internal.globals.require'
local make_rule_factory = require 'internal.globals.rule'
local shallowclone = require 'internal.util.shallowclone'
local Set = require 'internal.util.set'
local List = require 'internal.util.list'
local typelib = require 'internal.globals.typelib'
local freeze = require 'internal.util.freeze'

local function make_proxy(cb, getter, setter)
	assert(iscallable(cb[getter]), 'missing callback: ' .. tostring(getter))
	assert(iscallable(cb[setter]), 'missing callback: ' .. tostring(setter))

	local target = setmetatable({}, {
		__index = function (_, k) return cb[getter](cb, k) end
	})

	-- We freeze here because freeze() doesn't re-freeze frozen
	-- objects, and since the script's context is frozen (recursively)
	-- we would normally not get to hit target's __newindex method.
	return freeze(
		target,
		function (k, v) return cb[setter](cb, k, v) end
	)
end

local function make_globals(cb)
	assert(cb ~= nil)

	-- Construct the global object
	local G = {}

	G._G = G

	G.rawget = rawget
	G.rawlen = rawlen
	G.rawequal = rawequal
	G.rawset = freeze.rawset or error 'missing freeze.rawset'
	G.next = next
	G.ipairs = ipairs
	G.pairs = pairs
	G.tostring = tostring
	G.tonumber = tonumber
	G.setmetatable = setmetatable
	G.getmetatable = getmetatable
	G.assert = assert
	G.error = error
	G.select = select
	G.pcall = pcall
	G.xpcall = xpcall

	G.type = tablefunc(
		type,
		{
			isnuclear = require 'internal.util.isnuclear',
			isinstance = require 'internal.util.isinstance',
			iscallable = iscallable
		}
	)

	G.math = math or error 'missing math'
	G.utf8 = utf8 or error 'missing utf8'

	G.string = require 'internal.globals.stringlib'
	G.table = require 'internal.globals.tablelib'

	G.E = make_proxy(cb, 'getenv', 'setenv')
	G.C = make_proxy(cb, 'getconfig', 'setconfig')

	assert(iscallable(cb.makesourcepath), 'missing callback: makesourcepath')
	assert(iscallable(cb.makebuildpath), 'missing callback: makebuildpath')
	G.S = function(...) return cb:makesourcepath(...) end
	G.B = function(...) return cb:makebuildpath(...) end

	assert(iscallable(cb.print), 'missing callback: print')
	G.print = function (...)
		cb:print(...)
	end

	assert(iscallable(cb.importlocal), 'missing callback: importlocal')
	assert(iscallable(cb.importstd), 'missing callback: importstd')
	G.require = make_require(
		function (...) return cb:importlocal(...) end,
		function (...) return cb:importstd(...) end
	)

	local oro = shallowclone(typelib)
	G.oro = oro

	oro.List = List
	oro.Set = Set
	oro.execute = Oro.execute

	function oro.searchpath(name, pathenv)
		return Oro.searchpath(name, pathenv or G.E.PATH)
	end

	oro.List = require 'internal.util.list'

	assert(iscallable(cb.definerule), 'missing callback: definerule')
	assert(iscallable(cb.definebuild), 'missing callback: definebuild')
	oro.Rule = make_rule_factory(
		function (...) return cb:definerule(...) end,
		function (...) return cb:definebuild(...) end
	)

	-- Add an unknown variable guard (to avoid pitfalls).
	assert(getmetatable(G) == nil) -- sanity check
	assert(iscallable(cb.getexport), 'missing callback: getexport')
	setmetatable(G, {
		__index = function (_, k)
			return (
				cb:getexport(k)
				-- We do 3 here since we want to skip *this* callsite as well
				-- as the frozen getter's callsite (since the globals will be
				-- frozen)
				or error('attempted to reference nil global value: ' .. tostring(k), 3)
			)
		end
	})

	-- Freeze global
	-- (see the freeze() function definition)
	assert(iscallable(cb.export), 'missing callback: export')
	return freeze(G, function (k, v)
		if rawget(G, k) ~= nil then
			error('cannot name export the same as a global value: ' .. tostring(k), 2)
		end

		return cb:export(k, v)
	end)
end

return make_globals
