--  __   __   __
-- /  \ |__) /  \
-- \__/ |  \ \__/
--
-- ORO BUILD GENERATOR
-- Copyright (c) 2021, Josh Junon
-- License TBD
--

--
-- Path class for assisting with path manipulation
-- and resolution
--

local util = require 'internal.util'

local unpack = util.unpack
local tablefunc = util.tablefunc

local Path = {}

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
			{ __index = Path, __tostring = Path.__tostring }
		)
	end
end

function Path:base(s)
	if s == nil then
		return self._base
	else
		return setmetatable(
			{ _path = self._path, _base = pathstring(s, true) },
			{ __index = Path, __tostring = Path.__tostring }
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

function Path:__tostring()
	local path, base = self._path, self._base

	if #base == 0 then return path end

	return Oro.path.normalize(
		(Oro.path.has_dir_end(path) and Oro.path.ensure_dir_end or Oro.path.remove_dir_end)(
			Oro.path.join(base, path)
		)
	)
end

local function make_path_factory(from, retarget_to)
	assert(Oro.path.isabs(from))
	assert(Oro.path.isabs(retarget_to))

	-- strip common prefix
	local from_root, retg_root = nil, nil
	while #from > 0 and #retarget_to > 0 do
		-- yes, Oro.path.join('/', '/foo') results in '/foo'.
		from_root, from = Oro.path.splitroot(Oro.path.join('/', from))
		retg_root, retarget_to = Oro.path.splitroot(Oro.path.join('/', retarget_to))

		if from_root ~= retg_root then
			break
		end
	end

	-- Re-write difference in path depth with `..`'s.
	local joins = {}
	while #from > 0 do
		from_root, from = Oro.path.splitroot(Oro.path.join('/', from))
		joins[#joins + 1] = '..'
	end

	-- Construct the new base path
	local base = Oro.path.remove_dir_end(Oro.path.join(unpack(joins) or '', retarget_to))

	local inner = function(path)
		-- Translate `S'/foo'` to `S'./foo'`
		if Oro.path.isabs(path) then
			-- this is a bit magic, sorry.
			-- basically, the lua-path function `splitroot`
			-- splits a path by
			path = (Oro.path.has_dir_end(path) and Oro.path.ensure_dir_end or Oro.path.remove_dir_end)(
				Oro.path.join(Oro.path.splitroot(path))
			)
		end

		return setmetatable(
			{
				_path = path,
				_base = base,
			},
			{
				__index = Path,
				__tostring = Path.__tostring
			}
		)
	end

	return function(path)
		if type(path) == 'string' or isinstance(path, Path) then
			return inner(path)
		elseif type(path) == 'table' then
			local nt = {}
			for i = 1, #path do
				nt[i] = inner(path[i])
			end
			return nt;
		else
			error('invalid path type: '..tostring(type(path)))
		end
	end
end

return tablefunc(
	make_path_factory,
	{ Path = Path }
)
