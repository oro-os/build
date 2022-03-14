--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021-2022, Josh Junon
-- License TBD
--

--
-- Path factory for assisting with path manipulation
-- and resolution within scripting contexts
--

local flat = require 'internal.util.flat'
local unpack = require 'internal.util.unpack'
local tablefunc = require 'internal.util.tablefunc'
local isinstance = require 'internal.util.isinstance'
local List = require 'internal.util.list'
local P = require 'internal.path'
local typename = require 'internal.util.typename'

local Path = {}
local Path__mt = nil

local function pathstring(x, prop)
	if isinstance(x, Path) then
		return x[prop]
	end

	if type(x) ~= 'string' then
		error('path argument must either be another Path or a string', 2)
	end

	return x
end

function Path:path(s)
	if s == nil then
		return self._path
	else
		return setmetatable(
			{ _path = pathstring(s, '_path'), _base = self._base },
			Path__mt
		)
	end
end

function Path:base(s)
	if s == nil then
		return self._base
	else
		return setmetatable(
			{ _path = self._path, _base = pathstring(s, '_base') },
			Path__mt
		)
	end
end

function Path:basename(s)
	if s == nil then
		return P.basename(self._path)
	else
		return setmetatable(
			{
				_path = P.join(P.dirname(self._path), pathstring(s, '_path')),
				_base = self._base
			},
			Path__mt
		)
	end
end

function Path:append(s)
	return self:path(self._path .. pathstring(s, '_path'))
end

function Path:ext(s)
	local base, ext = P.splitext(self._path)
	if s == nil then
		return ext
	else
		if type(s) ~= 'string' then
			error('argument to :ext() must be a string; got '..typename(s), 1)
		end
		return self:path(base .. s)
	end
end

function Path:join(pth)
	if isinstance(pth, Path) then
		return self:path(P.join(self._path, pth._path))
	elseif type(pth) == 'string' or type(pth) == 'number' then
		return self:path(P.join(self._path, tostring(pth)))
	elseif type(pth) == 'table' then
		local cur = self
		for segment in flat(pth) do
			cur = cur:join(segment)
		end
		return cur
	else
		error('Path:join(path): path must either be a string, number or another Path instance: ' .. tostring(pth), 2)
	end
end

local function Path__tostring(self)
	local path, base = self._path, self._base

	if #base == 0 then return path end

	return P.normalize(
		(P.has_dir_end(path) and P.ensure_dir_end or P.remove_dir_end)(
			P.join(base, path)
		)
	)
end

local function make_path_factory(source_root, build_root)
	assert(source_root ~= nil and P.isabs(source_root))
	assert(build_root ~= nil and P.isabs(build_root))

	source_root = P.normalize(source_root)
	build_root = P.normalize(build_root)

	local base = P.relpath(build_root, source_root)

	local inner = function(path)
		assert(type(path) == 'string')

		-- Translate `S'/foo'` to `S'./foo'`
		if P.isabs(path) then
			path = (P.has_dir_end(path) and P.ensure_dir_end or P.remove_dir_end)(
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
		else
			error('invalid path type: '..tostring(type(path)), 2)
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
		Path = Path
	}
)
