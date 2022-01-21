--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Creates a build context. A single build configuration
-- equates to a single build context.
--
-- In the general case, each run of the build config step
-- will use exactly one context.
--

local Oro = require 'internal.oro'
local make_globals = require 'internal.globals'
local tablefunc = require 'internal.util.tablefunc'
local isinstance = require 'internal.util.isinstance'
local List = require 'internal.util.list'
local make_path_factory = require 'internal.path-factory'
local P = require 'internal.path'
local freeze = require 'internal.util.freeze'
local Ninjafile = require 'internal.ninja'

local Context = {}
local Module = {}

local function make_module(opts)
	local module = setmetatable(
		{
			root = opts.root or error 'missing opts.root',
			build_root = opts.build_root or error 'missing opts.build_root',
			context = opts.context or error 'missing opts.context',
			env = opts.env or error 'missing opts.env',
			config = opts.config or error 'missing opts.config',
			exports = {all = List()}
		},
		{
			__index = Module,
			__name = 'Module'
		}
	)

	assert(
		isinstance(module.context, Context),
		'opts.context must be a Context object'
	)

	assert(
		P.isabs(module.root),
		'opts.root must be absolute path: ' .. tostring(module.root)
	)

	assert(
		P.isabs(module.build_root),
		'opts.build_root must be absolute path: ' .. tostring(module.build_root)
	)

	-- Create factories after the absolute assertion above
	module.source_factory = make_path_factory(
		module.root,
		module.context.build_root
	)

	module.build_factory = make_path_factory(
		module.build_root,
		module.context.build_root
	)

	return module
end

local function make_context(opts)
	local ctx = setmetatable(
		{
			root = opts.source_directory or error 'missing opts.source_directory',
			build_root = opts.build_directory or error 'missing opts.build_directory',
			config = opts.config or error 'missing opts.config',
			env = opts.env or error 'missing opts.env',
			referenced_config = {},
			modules = {},
			rules = List(),
			rulemap = {},
			builds = List(),
			ninja = Ninjafile(),
			tags = 0
		},
		{
			__index = Context,
			__name = 'Context'
		}
	)

	-- Create the shared global object used for each scripting context
	ctx.script_globals = make_globals(ctx)

	-- Create the root module
	-- The root module is special since its config/env/etc.
	-- are inherited from the system's/command-line's env/config.
	-- and thus we want to track what is and is not referenced.
	ctx.root_module = make_module {
		root = ctx.root,
		build_root = ctx.build_root,
		context = ctx,
		env = setmetatable({}, {
			__index = function (_, k)
				return ctx.env[k]
			end
		}),
		config = setmetatable({}, {
			__index = function (_, k)
				ctx.referenced_config[k] = true
				return ctx.config[k]
			end
		})
	}

	ctx.current_module = ctx.root_module
	ctx.modules[ctx.root] = ctx.root_module

	return ctx
end

function Context:getenv(name)
	assert(self.current_module ~= nil)
	return self.current_module.env[name]
end

function Context:setenv(name, value)
	assert(self.current_module ~= nil)

	if type(name) ~= 'string' then
		error('environment variable names must be strings (got ' .. type(name) .. ')', 2)
	end

	if value ~= nil and type(value) ~= 'string' then
		error(
			'environment variable values must be nil or string (when setting `'
			.. name
			.. '` with value of type \''
			.. type(value)
			.. '\')',
			2
		)
	end

	self.current_module.env[name] = value
end

function Context:getconfig(name)
	assert(self.current_module ~= nil)
	return self.current_module.config[name]
end

function Context:setconfig(name, value)
	assert(self.current_module ~= nil)

	if type(name) ~= 'string' then
		error('config variable name must be string (got ' .. type(name) .. ')', 2)
	end

	self.current_module.config[name] = value
end

function Context:export(name, value)
	assert(self.current_module ~= nil)

	if type(name) ~= 'string' then
		error('export names must be strings (got ' .. type(name) .. ')', 2)
	end

	if name == 'all' then
		error('cannot override export \'all\'', 2)
	end

	self.current_module.exports[name] = value
end

function Context:getexport(name)
	assert(self.current_module ~= nil)
	return self.current_module.exports[name]
end

function Context:setcontext(module)
	local last_module = self.current_module
	self.current_module = module
	return last_module
end

function Context:print(...)
	assert(self.current_module ~= nil)
	-- TODO contextualize
	print(...)
end

function Context:importlocal(import, opts)
	assert(self.current_module ~= nil)

	local pathname, attempted = package.searchpath(
		import,
		(
			P.join(self.current_module.root, '?.oro')
			.. ';'
			.. P.join(self.current_module.root, '?/build.oro')
		)
	)

	if pathname == nil then
		error(
			'import not found: '
			.. tostring(import)
			.. '\n\n'
			.. attempted,
			2
		)
	end

	local module = self.modules[pathname]

	local source_root = P.dirname(pathname)

	local this = self
	local parent_module = self.current_module
	if module == nil then
		module = make_module {
			root = source_root,
			build_root = P.normalize(
				P.join(
					self.build_root,
					P.relpath(
						self.root,
						source_root
					)
				)
			),
			context = self,
			config = setmetatable({}, {
				__index = function (_, k)
					return parent_module.config[k]
				end
			}),
			env = setmetatable({}, {
				__index = function (_, k)
					return parent_module.env[k]
				end
			})
		}

		self.modules[pathname] = module

		module:dofile(pathname)
	end

	return module:result()
end

function Context:importstd(import, opts)
	local libdir = P.join(Oro.absrootdir, 'lib')

	local pathname, attempted = package.searchpath(
		import,
		(
			P.join(libdir, '?.lua')
			.. ';'
			.. P.join(libdir, '?/_.lua')
		)
	)

	if pathname == nil then
		error(
			'no such standard import: '
			.. tostring(import)
			.. '\n\n'
			.. attempted,
			2
		)
	end

	local module = self.modules[pathname]

	local source_root = P.dirname(pathname)

	local this = self
	if module == nil then
		module = make_module {
			root = source_root,
			build_root = P.normalize(
				P.join(
					P.join(self.build_root, '.oro/lib'),
					P.relpath(
						libdir,
						source_root
					)
				)
			),
			context = self,
			-- Standard libraries pull from the 'global' config/env
			-- when executing the top level. Exported functions are
			-- still executed in whichever context they're invoked from.
			--
			-- This is to prevent side-effects or strange behavior based
			-- on order-of-imports changes or unruly dependencies.
			config = setmetatable({}, {
				__index = function (_, k)
					this.referenced_config[k] = true
					return this.config[k]
				end
			}),
			env = setmetatable({}, {
				__index = function (_, k)
					return this.env[k]
				end
			})
		}

		self.modules[pathname] = module

		module:dofile(pathname)
	end

	return module:result()
end

function Context:definerule(rule)
	local id = tostring(#self.rules)

	self.rules[nil] = rule
	self.rulemap[rule] = id

	self.ninja:add_rule(
		'R'..id,
		rule.options
	)
end

function Context:definebuild(build)
	assert(build.rule ~= nil)
	local ruleid = self.rulemap[build.rule]
	assert(ruleid ~= nil)

	self.builds[nil] = build

	self.ninja:add_build(
		'R'..ruleid,
		build.options
	)
end

function Context:makephony(arguments, deps)
	assert(self.current_module ~= nil)

	if self.phony_proxy == nil then
		self.phony_proxy = {
			options = {
				command = '$command',
				description = 'RUN $command'
			}
		}

		self:definerule(self.phony_proxy)
	end

	local tagid = self.tags
	self.tags = self.tags + 1
	-- We cheat a bit here. But it works.
	local tagpath = self.script_globals.B('PHONY.' .. tostring(tagid))

	self:definebuild {
		rule = self.phony_proxy,
		options = {
			in_implicit = {deps},
			command = {arguments},
			out_implicit = {tagpath}
		}
	}

	return freeze({tagpath})
end

function Context:makesourcepath(...)
	assert(self.current_module ~= nil)
	return self.current_module.source_factory(...)
end

function Context:makebuildpath(...)
	assert(self.current_module ~= nil)
	return self.current_module.build_factory(...)
end

function Module:dofile(pathname)
	assert(P.isabs(pathname), 'must be absolute: ' .. tostring(pathname))

	local chunk, err = loadfile(pathname, 'bt', self.context.script_globals)
	assert(chunk ~= nil, err)

	local previous_module = self.context:setcontext(self)
	local rets = {chunk()}
	self.context:setcontext(previous_module)

	if #rets == 1 then
		self.default_export = rets[1]
	elseif #rets > 1 then
		error(
			tostring(pathname)
			.. ': cannot return more than one default value from build scripts (got '
			.. tostring(#rets)
			.. ')',
			2
		)
	end
end

function Module:result()
	local this = self
	local exportmap = setmetatable({}, {
		__index = function(_, k)
			local export = this.exports[k]
			if export == nil then
				error('no such export: ' .. k, 3)
			end
			return export
		end,
		__pairs = function() return pairs(this.exports) end,
		-- Yep, this is intentional. We allow child module exports.
		-- This is kind of where the line is drawn between "sandbox things"
		-- and "let the developer shoot themselves in the foot if they
		-- really want to". I'm not going to act like I'm smarter than you
		-- (at least, not in every scenario). Use with care, please. I WILL
		-- break you in later releases if this feature ends up being a mistake.
		__newindex = function (_, k, v)
			if k == 'all' then
				error('cannot override child \'all\' export', 3)
			end
			self.exports[k] = v
		end,
		__name = 'ModuleResult'
	})

	if self.default_export == nil then
		return freeze(exportmap, true)
	else
		return freeze(self.default_export), freeze(exportmap, true)
	end
end

return tablefunc(
	make_context,
	{
		Context = Context,
		Module = Module
	}
)
