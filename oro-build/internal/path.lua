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

local P = setmetatable({}, {
	__index = (require 'path').new('/')
})

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
