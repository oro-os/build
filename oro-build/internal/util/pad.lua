--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Pad a string (either left or right)
-- with n * char
--

local function lpad(str, len, chr)
	return string.rep(chr or ' ', len - #str) .. str
end

local function rpad(str, len, chr)
	return str .. string.rep(chr or ' ', len - #str)
end

return {
	left = lpad,
	right = rpad
}
