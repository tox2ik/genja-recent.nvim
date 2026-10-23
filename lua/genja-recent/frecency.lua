-- genja-recent.frecency: score = (views + edits * edit_weight) * recency weight (zoxide style).

local M = {}

local HOUR = 3600
local DAY = 24 * HOUR
local WEEK = 7 * DAY

---Recency weight of a use `age` seconds ago: x4 within an hour, x2 within a day,
---x0.5 within a week, x0.25 older.
---@param age number seconds
---@return number
function M.recency(age)
	if age < HOUR then
		return 4
	end
	if age < DAY then
		return 2
	end
	if age < WEEK then
		return 0.5
	end
	return 0.25
end

---Frecency score of one entry.
---@param views integer
---@param edits integer
---@param last integer unix time of the last use
---@param now integer unix time
---@param edit_weight number an edit counts this many views
---@return number
function M.score(views, edits, last, now, edit_weight)
	return (views + edits * edit_weight) * M.recency(now - last)
end

return M
