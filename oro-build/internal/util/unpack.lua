--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- table.unpack(), depending on the environment
--
-- This probably isn't needed, especially since
-- we control the environment. But it's a good
-- defensive stub if the Lua library is ever
-- changed/upgraded.
--

return table.unpack or unpack or error('no unpack!')
