local gcc_variant = require 'lib.cc.variant.gcc'

local clang_variant = {
	flag_warn_everything = {'-Weverything'}
}

for k, v in pairs(gcc_variant) do
	if clang_variant[k] == nil then
		clang_variant[k] = v
	end
end

return clang_variant
