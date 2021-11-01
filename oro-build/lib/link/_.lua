local configure_cc = require 'cc._configure'

local DEFAULT_COMPILER = {}

local exe_linker_cache = {}
local function link_exe_builder(opts)
	local linker_key = C'CC' or E'CC' or DEFAULT_COMPILER

	local exe_linker = exe_linker_cache[linker_key]
	if exe_linker == nil then
		local compiler = configure_cc()

		local new_linker = {}
		for k, v in pairs(compiler) do
			new_linker[k] = v
		end

		new_linker.rule = new_linker.rule:clone()
		new_linker.rule.description = (
			'LINK('
			.. Rule.escapeall(new_linker.compiler_command)
			.. ') $out'
		)

		exe_linker_cache[linker_key] = new_linker
		exe_linker = new_linker
	end

	local cflags = List(opts.ldflags)

	local release = opts.release
	local release_fast = false
	if release == nil then
		release = C'RELEASE'
		release_fast = opts.fast or tostring(release) == 'fast'
		release = release ~= nil and tostring(release) ~= '0'
	end

	if release then
		cflags[nil] = exe_linker.variant.ldflag_release

		if release_fast then
			cflags[nil] = exe_linker.variant.flag_release_fase
		else
			cflags[nil] = exe_linker.variant.flag_release
		end
	elseif not opts.nodebug then
		cflags[nil] = exe_linker.variant.flag_debug
	end

	return exe_linker.rule {
		In = opts,
		out = opts.out,
		cflags = cflags
	}
end

return {
	exe = link_exe_builder
}
