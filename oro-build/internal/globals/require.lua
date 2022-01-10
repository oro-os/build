--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Creates a top-level `require()`
-- handler that works similar to
-- lua's but also allows parameters
-- to augment/override the child module.
--

local function make_require(onlocal, onstdlib)
	local function module_require(opts, ...)
		local import = nil

		if #{...} ~= 0 then
			error(
				'require() takes exactly 1 argument; got '
				.. tostring(#{...}),
				2
			)
		end

		if type(opts) == 'string' then
			import = opts
			opts = {}
		elseif type(opts) == 'table' then
			if #opts ~= 1 then
				error(
					'require{} (with an options argument or curly-brace invocation) takes exactly one positional argument; got '
					.. tostring(#opts),
					2
				)
			end

			if type(opts[1]) ~= 'string' then
				error(
					'require{} (with an options argument or curly-brace invocation) must have a string as first parameter; got '
					.. type(opts[1]),
					2
				)
			end

			import = opts[1]
			opts[1] = nil
		else
			error(
				'require() takes either a single string or a table (or curly-brace invocation, e.g. `require{}`); got '
				.. type(opts),
				2
			)
		end

		if #import == 0 then
			error('imported name cannot be empty', 2)
		end

		if string.sub(import, 1, 1) == '.' then
			import = string.sub(import, 2)

			if #import == 0 then
				error('cannot re-import current directory (i.e. `require "."`)', 2)
			end

			return onlocal(import, opts)
		else
			return onstdlib(import, opts)
		end
	end

	return module_require
end

return make_require
