--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- GCC C/C++ compiler variant information
--

local gcc_variant = {
	flag_compile_object = '-c',
	flag_force_c = '-xc',
	flag_warn_error = '-Werror',
	flag_warn_all = '-Wall',
	flag_warn_all_plus = {'-Wall', '-Wextra', '-Wshadow', '-Wstrict-prototypes'},
	flag_warn_strict = {'-Werror', '-Wall', '-Wextra', '-Wshadow', '-Wstrict-prototypes'},
	-- GCC doesn't have -Weverything so we just do all+
	flag_warn_everything = {'-Wall', '-Wextra', '-Wshadow', '-Wstrict-prototypes'},
	flag_debug = {'-g3', '-O0'},
	flag_release = {'-g0', '-O3', '-DNDEBUG'},
	flag_release_fast = {'-g0', '-O3', '-ffast-math', '-DNDEBUG'},
	flag_preprocess_only = '-E',
	flag_preprocess_only_nodebug = {'-E', '-P'},

	ldflag_release = '-s'
}

function gcc_variant.flag_output(out)
	return {'-o', out}
end

function gcc_variant.flag_warn(name)
	return '-W' .. tostring(name)
end

function gcc_variant.flag_define(name, value)
	if value == nil then
		return '-D' .. tostring(name)
	else
		return '-D' .. tostring(name) .. '=' .. tostring(value)
	end
end

return gcc_variant
