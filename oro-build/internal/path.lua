--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Path manipulation and query utilities
--

require 'path.fs'

local unpack = require 'internal.util.unpack'
local List = require 'internal.util.list'

local P = setmetatable({}, {
	__index = (require 'path').new('/')
})

local real_join = P.join
function P.join(...)
	-- Annoyingly, the builtin `join` function
	-- treats empty strings as valid paths.
	-- This causes P.join(maybezerolength, 'foo')
	-- as '/foo', which wreaks havoc on the path
	-- library - namely, when using P.dirname(),
	-- which returns an empty first leaf for
	-- non-nested relative paths.
	local leafs = List()

	for _, v in ipairs{...} do
		if v ~= nil then
			local vs = tostring(v)
			if #vs > 0 then
				leafs[nil] = vs
			end
		end
	end

	return real_join(unpack(leafs))
end

local real_normalize = P.normalize
function P.normalize(pth)
	return P.remove_dir_end(real_normalize(pth))
end

function P.asabs(pth)
	if P.isabs(pth) then
		return pth
	else
		return P.join('/', pth)
	end
end

function P.asrel(pth)
	if P.isabs(pth) then
		if pth == '/' then return '' end
		return P.join(P.splitroot(pth))
	else
		return pth
	end
end

function P.relpath(from, to)
	assert(P.isabs(from))
	assert(P.isabs(to))

	from = P.normalize(from)
	to = P.normalize(to)

	if from == to then
		return '.'
	end

	while true do
		local f_leaf, f_path = P.splitroot(from)
		local t_leaf, t_path = P.splitroot(to)

		if f_leaf == t_leaf then
			from = P.asabs(f_path)
			to = P.asabs(t_path)
		else
			break
		end
	end

	from = P.normalize(P.asrel(from))
	to = P.normalize(P.asrel(to))

	local joins = {}

	while true do
		if from == '' then
			break
		else
			joins[#joins + 1] = '..'
		end

		from = P.dirname(from)
	end

	joins[#joins + 1] = to

	return P.normalize(
		P.join(unpack(joins))
	)
end

function P.resolve(pth, to)
	if P.isabs(pth) then
		return pth
	else
		return P.normalize(
			P.join(
				to or P.currentdir(),
				pth
			)
		)
	end
end

return P
