--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Common CC compiler configurator, used by
-- most tools that work with the C/C++ compilers
-- on a system.
--

local DEFAULT_COMPILER = {} -- marker table, used as a key
local rule_cache = {}

local function configure_compiler(compiler_command, skip_prelude)
	local compiler_command_args = string.split(tostring(compiler_command), ' \t\n')

	local resolved_command = oro.searchpath(compiler_command_args[1], E.PATH or '')
	if resolved_command == nil then
		error(
			'failed to configure C compiler; no such executable (not on PATH): '
			.. compiler_command_args[1],
			2
		)
	end

	compiler_command_args[1] = resolved_command

	if not skip_prelude then
		print('configuring C compiler: ' .. compiler_command)
	end

	local status, stdout, stderr = oro.execute{
		raise=false,
		compiler_command_args[1],
		'--version'
	}

	if status ~= 0 then
		if stderr == nil or #stderr == 0 then
			stderr = '<no error output>'
		end
		print('\tfailure: exited ' .. tostring(status) .. ': ' .. stderr)
		error(
			'C compiler configuration failed: '
			.. compiler_command,
			2
		)
	end

	print('\t>> ' .. stdout:gsub('[\n \t]+$', ''):gsub('\n', '\n\t>> '))

	-- Attempt to detect which compiler suite it is
	local use_variant = 'gcc'

	if stdout:find('clang') ~= nil then
		print('\tdetected Clang')
		use_variant = 'clang'
	elseif stdout:find('gcc') ~= nil then
		print('\tdetected GCC')
	else
		print('\tWARNING: could not detect compiler variant (falling back to GCC-like)')
	end

	local variant = require ('cc._variant.'..use_variant)
	assert(variant ~= nil)

	local rule = oro.Rule {
		command = {
			-- Guarantee that the depfile exists.
			-- This is to appease Ninja in cases
			-- where the compiler decides not to
			-- initialize a depfile because none
			-- of its inputs are "sources".
			oro.syscall 'init-depfile',
			'$out',
			'&&',
			compiler_command_args,
			variant.flag_output('$out'),
			variant.flag_dep_output('$out.d'),
			'$cflags',
			'$in'
		},
		depfile = '$out.d',
		description = 'CC(' .. oro.Rule.escapeall(compiler_command) .. ') $out'
	}

	print('\tOK')
	return {
		rule = rule,
		variant_name = use_variant,
		variant = variant,
		compiler_command = compiler_command
	}
end

local function detect_default_compiler()
	print('detecting system C compiler...')

	local to_test = {'cc', 'gcc', 'clang', 'tcc'}
	local resolved = nil

	local path = E.PATH
	if path == nil then
		error(
			'attempted to auto-detect system C compiler but PATH environment variable is not set',
			2
		)
	end

	for _, v in ipairs(to_test) do
		resolved = oro.searchpath(v, path)
		if resolved ~= nil then
			break
		end
	end

	if resolved == nil then
		error(
			'could not detect C compiler; tried: '
			.. table.concat(to_test, ', '),
			2
		)
	end

	print('\tfound:', resolved)
	return configure_compiler(resolved, true)
end

local function configure()
	local compiler_command = C.CC or E.CC or DEFAULT_COMPILER

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

return configure
