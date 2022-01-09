--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Path class for assisting with path manipulation
-- and resolution
--

local util = require 'internal.util'
local flat = require 'internal.flat'

local unpack = util.unpack
local tablefunc = util.tablefunc
local isinstance = util.isinstance
local List = util.List

local Path = {}
local Path__mt = nil

local function pathstring(x, allow_base)
	-- TODO we kind of naively assume that a function
	-- TODO here is a path factory; we should probably
	-- TODO have a PathFactory metatable and isinstance()
	-- TODO check it.
	assert(allow_base or type(s) ~= 'function', 'cannot pass a path factory (`S` or `B`) to :path()')
	if type(x) == 'function' then return x('.')._base end
	return isinstance(x, Path) and x[prop] or x
end

function Path:path(s)
	if s == nil then
		return self._path
	else
		return setmetatable(
			{ _path = pathstring(s), _base = self._base },
			Path__mt
		)
	end
end

function Path:base(s)
	if s == nil then
		return self._base
	else
		return setmetatable(
			{ _path = self._path, _base = pathstring(s, true) },
			Path__mt
		)
	end
end

function Path:append(s)
	return self:path(self._path .. pathstring(s))
end

function Path:ext(s)
	local base, ext = Oro.path.splitext(self._path)
	if s == nil then
		return ext
	else
		return self:path(base .. s)
	end
end

function Path:join(pth)
	if isinstance(pth, Path) then
		return self:path(Oro.path.join(self._path, pth._path))
	elseif type(pth) == 'string' or type(pth) == 'number' then
		return self:path(Oro.path.join(self._path, tostring(pth)))
	elseif type(pth) == 'table' then
		local cur = self
		for segment in flat(pth) do
			cur = cur:join(segment)
		end
		return cur
	else
		error('Path:join(path): path must either be a string, number or another Path instance: ' .. tostring(pth))
	end
end

function Path__tostring(self)
	local path, base = self._path, self._base

	if #base == 0 then return path end

	return Oro.path.normalize(
		(Oro.path.has_dir_end(path) and Oro.path.ensure_dir_end or Oro.path.remove_dir_end)(
			Oro.path.join(base, path)
		)
	)
end

local function asabs(pth)
	if Oro.path.isabs(pth) then
		return pth
	else
		return Oro.path.join('/', pth)
	end
end

local function resolve(pth, to)
	if Oro.path.isabs(pth) then
		return pth
	else
		return Oro.path.normalize(
			Oro.path.join(
				to or Oro.path.currentdir(),
				pth
			)
		)
	end
end

local function asrel(pth)
	if Oro.path.isabs(pth) then
		if pth == '/' then return '' end
		return Oro.path.join(Oro.path.splitroot(pth))
	else
		return pth
	end
end

local function normalize(pth)
	return Oro.path.remove_dir_end(Oro.path.normalize(pth))
end

local function relpath(from, to)
	assert(Oro.path.isabs(from))
	assert(Oro.path.isabs(to))

	if from == to then
		return '.'
	end

	while true do
		local f_leaf, f_path = Oro.path.splitroot(from)
		local t_leaf, t_path = Oro.path.splitroot(to)

		if f_leaf == t_leaf then
			from = asabs(f_path)
			to = asabs(t_path)
		else
			break
		end
	end

	from = normalize(asrel(from))
	to = normalize(asrel(to))

	local joins = {}

	while true do
		if from == '' then
			break
		else
			joins[#joins + 1] = '..'
		end

		from = Oro.path.dirname(from)
	end

	joins[#joins + 1] = to

	return normalize(
		Oro.path.join((table.unpack or unpack)(joins))
	)
end

local function make_path_factory(source_root, build_root)
	assert(source_root ~= nil)
	assert(build_root ~= nil)

	source_root = normalize(source_root)
	build_root = normalize(build_root)

	local base = relpath(build_root, source_root)

	local inner = function(path)
		assert(type(path) == 'string')

		-- Translate `S'/foo'` to `S'./foo'`
		if Oro.path.isabs(path) then
			path = (Oro.path.has_dir_end(path) and Oro.path.ensure_dir_end or Oro.path.remove_dir_end)(
				asrel(path)
			)
		end

		return setmetatable(
			{
				_path = path,
				_base = base,
			},
			Path__mt
		)
	end

	return function(path)
		if type(path) == 'string' then
			return inner(path)
		elseif isinstance(path, Path) then
			return inner(path._path)
		elseif type(path) == 'table' then
			local nt = List()
			for pth in flat(path) do
				nt[nil] = inner(pth)
			end
			return nt;
		else
			error('invalid path type: '..tostring(type(path)))
		end
	end
end

Path__mt = {
	__index = Path,
	__name = 'Path', -- required to make object "nuclear"
	__tostring = Path__tostring
}

return tablefunc(
	make_path_factory,
	{
		Path = Path,
		asabs = asabs,
		asrel = asrel,
		relpath = relpath,
		normalize = normalize,
		resolve = resolve
	}
)
