-- genja-recent: recent files with own rules, ranked by frecency.
--   Records a view on BufWinEnter and an edit on BufWritePost, for real files only.
--   Data: one line per file, `path<TAB>views<TAB>edits<TAB>last` (unix time), in `file`.
--   Written on VimLeavePre and every `flush_minutes`; several nvims merge their counts.
--   list({ root? }) returns the paths, best first; the picker lives in the user's config.

local SRC = 'genja-recent/init.lua: '

local M = {}

---@class genja-recent.Opts
---@field file? string data file (default: stdpath('data')/genja-recent.txt)
---@field edit_weight? number an edit counts this many views (default 2)
---@field skip_patterns? string[] Lua patterns on the normalized lowercase path; matches are not recorded
---@field skip_dirs? string[] files under these dirs are not recorded (default: temp dir, stdpath('data'))
---@field flush_minutes? integer write interval (default 5)
---@field max_entries? integer kept in the file, best first (default 2000)

---@type genja-recent.Opts
M.config = {
	file = vim.fn.stdpath('data') .. '/genja-recent.txt',
	edit_weight = 2,
	skip_patterns = { '/%.git/' },
	skip_dirs = { vim.uv.os_tmpdir(), vim.fn.stdpath('data') },
	flush_minutes = 5,
	max_entries = 2000,
}

---@class genja-recent.Entry
---@field path string
---@field views integer
---@field edits integer
---@field last integer

---@type table<string, genja-recent.Entry> by key (lowercase path on Windows)
local entries = {}
---@type table<string, genja-recent.Entry> uses since the last write, merged into the file then
local pending = {}
local loaded = false
---@type uv.uv_timer_t|nil flushes every `flush_minutes`
local timer = nil
local is_win = vim.fn.has('win32') == 1

---Lookup key for `path`: case-insensitive on Windows.
---@param path string normalized
---@return string
local function key_of(path)
	return (is_win and path:lower() or path)
end

---Entries from the data file.
---@return table<string, genja-recent.Entry>
local function read_file()
	local result = {}
	local file = M.config.file
	if not file or vim.fn.filereadable(file) == 0 then
		return result
	end
	for _, line in ipairs(vim.fn.readfile(file)) do
		local path, views, edits, last = line:match('^(.-)\t(%d+)\t(%d+)\t(%d+)$')
		if path then
			result[key_of(path)] = {
				path = path,
				views = tonumber(views),
				edits = tonumber(edits),
				last = tonumber(last),
			}
		end
	end
	return result
end

local function load()
	if loaded then
		return
	end
	entries = read_file()
	loaded = true
end

---Should `path` be recorded?
---@param path string normalized
---@return boolean
local function wanted(path)
	local low = path:lower()
	for _, pattern in ipairs(M.config.skip_patterns or {}) do
		if low:find(pattern) then
			return false
		end
	end
	for _, dir in ipairs(M.config.skip_dirs or {}) do
		local d = vim.fs.normalize(dir):lower()
		if d ~= '' and vim.startswith(low, d .. '/') then
			return false
		end
	end
	return true
end

---Add one use to `tbl[key]`.
---@param tbl table<string, genja-recent.Entry>
---@param key string
---@param path string
---@param kind 'view'|'edit'
---@param now integer
local function bump(tbl, key, path, kind, now)
	tbl[key] = tbl[key] or { path = path, views = 0, edits = 0, last = 0 }
	local e = tbl[key]
	if kind == 'edit' then
		e.edits = e.edits + 1
	else
		e.views = e.views + 1
	end
	e.last = now
end

---Record a view or an edit of buffer `buf`.
---@param buf integer
---@param kind 'view'|'edit'
function M.record(buf, kind)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then
		return
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == '' or name:match('^%a%a+://') then
		return
	end
	local path = vim.fs.normalize(name)
	if not wanted(path) then
		return
	end
	load()
	local now = os.time()
	local key = key_of(path)
	bump(entries, key, path, kind, now)
	bump(pending, key, path, kind, now)
end

---Score of `e` now.
---@param e genja-recent.Entry
---@param now integer
---@return number
local function score(e, now)
	return require('genja-recent.frecency').score(e.views, e.edits, e.last, now, M.config.edit_weight)
end

---Entries sorted best first.
---@param tbl table<string, genja-recent.Entry>
---@return genja-recent.Entry[]
local function sorted(tbl)
	local now = os.time()
	local list = vim.tbl_values(tbl)
	local scores = {}
	for _, e in ipairs(list) do
		scores[e] = score(e, now)
	end
	table.sort(list, function(a, b)
		if scores[a] ~= scores[b] then
			return scores[a] > scores[b]
		end
		return a.last > b.last
	end)
	return list
end

---Write the data file: the file as it is now plus this session's uses (other nvims may have written).
function M.flush()
	if vim.tbl_isempty(pending) or not M.config.file then
		return
	end
	local merged = read_file()
	for key, p in pairs(pending) do
		local e = merged[key]
		if not e then
			merged[key] = p
		else
			e.views = e.views + p.views
			e.edits = e.edits + p.edits
			e.last = math.max(e.last, p.last)
		end
	end
	local lines = {}
	for i, e in ipairs(sorted(merged)) do
		if i > M.config.max_entries then
			break
		end
		table.insert(lines, e.path .. '\t' .. e.views .. '\t' .. e.edits .. '\t' .. e.last)
	end
	vim.fn.mkdir(vim.fs.dirname(M.config.file), 'p')
	if vim.fn.writefile(lines, M.config.file) ~= 0 then
		vim.notify(SRC .. 'could not write ' .. M.config.file, vim.log.levels.WARN)
		return
	end
	pending = {}
	entries = merged
end

---Is `path` inside `root`?
---@param path string normalized
---@param root string normalized
---@return boolean
local function under(path, root)
	return vim.startswith(key_of(path), key_of(root):gsub('/$', '') .. '/')
end

---Recent files, best first; only existing ones.
---@param opts? { root?: string } only files under root
---@return string[]
function M.list(opts)
	opts = opts or {}
	load()
	local root = opts.root and vim.fs.normalize(opts.root)
	local paths = {}
	for _, e in ipairs(sorted(entries)) do
		if (not root or under(e.path, root)) and vim.uv.fs_stat(e.path) then
			table.insert(paths, e.path)
		end
	end
	return paths
end

---@param opts? genja-recent.Opts
function M.setup(opts)
	M.config = vim.tbl_deep_extend('force', M.config, opts or {})
	local group = vim.api.nvim_create_augroup('genja_recent', { clear = true })
	vim.api.nvim_create_autocmd('BufWinEnter', {
		group = group,
		callback = function(ev) M.record(ev.buf, 'view') end,
	})
	vim.api.nvim_create_autocmd('BufWritePost', {
		group = group,
		callback = function(ev) M.record(ev.buf, 'edit') end,
	})
	vim.api.nvim_create_autocmd('VimLeavePre', {
		group = group,
		callback = function() M.flush() end,
	})
	if timer then
		timer:close() -- setup() again: one timer, not two
	end
	timer = assert(vim.uv.new_timer())
	local ms = M.config.flush_minutes * 60 * 1000
	timer:start(ms, ms, vim.schedule_wrap(M.flush))
	-- the buffer shown before the plugin loaded (VeryLazy)
	M.record(vim.api.nvim_get_current_buf(), 'view')
end

return M
