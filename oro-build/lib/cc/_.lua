--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- Main CC compiler configurator and builder
--

local configure = require 'cc._configure'

local function cc_builder(_, opts)
	local compiler = configure()

	local cflags = List(opts.cflags)
	local out = List()

	cflags[nil] = compiler.variant.flag_compile_object

	if not opts.noforce then
		cflags[nil] = compiler.variant.flag_force_c
	end

	local release = opts.release
	local release_fast = false
	if release == nil then
		release = C'RELEASE'
		release_fast = opts.fast or tostring(release) == 'fast'
		release = release ~= nil and tostring(release) ~= '0'
	end

	if release then
		if release_fast then
			cflags[nil] = compiler.variant.flag_release_fast
		else
			cflags[nil] = compiler.variant.flag_release
		end
	elseif not opts.nodebug then
		cflags[nil] = compiler.variant.flag_debug
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

	for v in table.flat(opts) do
		local outfile = B(v):append('.o')
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
