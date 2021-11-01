--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- Clang C/C++ compiler variant information,
-- based primarily on the GCC compiler variant
--

local gcc_variant = require 'cc._variant.gcc'

local clang_variant = {
	flag_warn_everything = {'-Weverything'}
}

for k, v in pairs(gcc_variant) do
	if clang_variant[k] == nil then
		clang_variant[k] = v
	end
end

return clang_variant
