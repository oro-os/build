local DEFAULT_COMPILER = {} -- marker table, used as a key
local rule_cache = {}

local function configure_compiler(compiler_command, skip_prelude)
	compiler_command_args = Oro.split(tostring(compiler_command), ' \t\n')

	resolved_command = Oro.search_path(compiler_command_args[1], E'PATH' or '')
	if resolved_command == nil then
		error('failed to configure C compiler; no such executable (not on PATH): ' .. compiler_command_args[1])
	end

	compiler_command_args[1] = resolved_command

	if not skip_prelude then
		print('configuring C compiler: ' .. compiler_command)
	end

	local status, stdout, stderr = Oro.execute{
		raise=false,
		compiler_command_args[1],
		'--version'
	}

	if status ~= 0 then
		if stderr == nil or #stderr == 0 then
			stderr = '<no error output>'
		end
		print('    failure: exited ' .. tostring(status) .. ': ' .. stderr)
		error('C compiler configuration failed: ' .. compiler_command)
	end

	print('    ' .. stdout:gsub('\n', '\n    '):gsub('[\n \t]+$', ''))

	-- Attempt to detect which compiler suite it is
	local use_variant = 'gcc'

	if stdout:find('clang') ~= nil then
		print('\n    detected Clang')
		use_variant = 'clang'
	elseif stdout:find('gcc') ~= nil then
		print('\n    detected GCC')
	else
		print('\n    WARNING: could not detect compiler variant (falling back to GCC-like)')
	end

	local variant = require ('lib.cc.variant.'..use_variant)
	assert(variant ~= nil)

	local rule = Rule {
		command = {
			compiler_command_args,
			variant.flag_output('$out'),
			'$cflags',
			'$in'
		},
		description = 'CC(' .. Rule.escapeall(compiler_command) .. ') $out'
	}

	print('    OK')
	return {
		rule = rule,
		variant_name = use_variant,
		variant = variant
	}
end

local function detect_default_compiler()
	print('detecting system C compiler...')

	local to_test = {'cc', 'gcc', 'clang', 'tcc'}
	local resolved = nil

	local path = E'PATH'
	if path == nil then
		error('attempted to auto-detect system C compiler but PATH environment variable is not set')
	end

	for _, v in ipairs(to_test) do
		resolved = Oro.search_path(v, path)
		if resolved ~= nil then
			break
		end
	end

	if resolved == nil then
		error('could not detect C compiler; tried: '..table.concat(to_test, ', '))
	end

	print('    found:', resolved)
	print()
	return configure_compiler(resolved, true)
end

local function configure()
	local compiler_command = C'CC' or E'CC' or DEFAULT_COMPILER

	local rule = rule_cache[compiler_command]

	if rule == nil then
		if compiler_command == DEFAULT_COMPILER then
			rule = detect_default_compiler()
		else
			rule = configure_compiler(compiler_command)
		end

		rule_cache[compiler_command] = rule
	end

	assert(rule ~= nil)

	return rule
end

local function cc_builder(_, opts)
	local compiler = configure()

	local cflags = List(opts.cflags)
	local out = List()

	cflags[nil] = compiler.variant.flag_compile_object

	if not opts.noforce then
		cflags[nil] = compiler.variant.flag_force_c
	end

	if opts.werror then cflags[nil] = compiler.variant.flag_warn_error end

	if opts.warn ~= nil then
		if opts.warn == 'error' then
			cflags[nil] = compiler.variant.flag_warn_error
		elseif opts.warn == 'all' then
			cflags[nil] = compiler.variant.flag_warn_all
		elseif opts.warn == 'all+' then
			cflags[nil] = compiler.variant.flag_warn_all_plus
		elseif opts.warn == 'strict' then
			cflags[nil] = compiler.variant.flag_warn_strict
		elseif opts.warn == 'everything' then
			cflags[nil] = compiler.variant.flag_warn_everything
		elseif type(opts.warn) == 'table' then
			for _, name in ipairs(opts.warn) do
				cflags[nil] = compiler.variant.flag_warn(name)
			end
		end
	end

	for i, v in ipairs(opts) do
		local outfile = B(v):ext('.o', true)
		out[nil] = outfile
		compiler.rule {
			In = v,
			out = {outfile},
			cflags = cflags
		}
	end

	return out
end

local function switch_variant(tbl)
	local compiler = configure()
	return tbl[compiler.variant_name]
end

local function cc_builder_index(_, k)
	if k == 'select' then
		return switch_variant
	elseif k == 'id' then
		return configure().variant_name
	end

	return nil
end

return setmetatable({}, {
	__call = cc_builder,
	__index = cc_builder_index,
	__newindex = function () end
})
