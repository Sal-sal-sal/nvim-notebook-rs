local M = { slots = {} }
local cache = require("notebook_rs.charts.cache")
local renderer = require("notebook_rs.charts.renderer")
local pending = {}

function M.begin(buf)
  M.slots[buf] = {}
end

function M.append(buf, output, virtual, row, number)
  local path = cache.file(buf, output)
  if not path then return false end
  local config = require("notebook_rs.config")
  local enabled = config.image_output and renderer.available(path)
  local label = enabled and "CHART" or "Image output saved in notebook"
  virtual[#virtual + 1] = { { ("├─ %s %d · :NotebookOpenChart %d ─"):format(label, number, number),
    "NotebookRsOutput" } }
  if enabled then
    local height = config.image_max_height
    local slots = M.slots[buf]
    slots[#slots + 1] = { path = path, row = row, offset = #virtual, height = height }
    for _ = 1, height do virtual[#virtual + 1] = { { " ", "Normal" } } end
    virtual[#virtual + 1] = { { " ", "Normal" } }
  end
  return true
end

function M.finish(buf)
  if pending[buf] then return end
  pending[buf] = true
  vim.schedule(function()
    pending[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.cmd.redraw()
    if renderer.sync(buf, M.slots[buf] or {}) then require("notebook_rs.cells").render(buf) end
  end)
end

function M.open(number)
  local buf = vim.api.nvim_get_current_buf()
  local id
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, vim.api.nvim_win_get_cursor(0)[1], false)) do
    local kind, found = require("notebook_rs.markers").parse(line)
    if kind then id = found end
  end
  local record = (require("notebook_rs.inline").records[buf] or {})[id]
  local paths = {}
  local count = 0
  for _, output in ipairs(record and record.outputs or {}) do
    if (output.data or {})["image/png"] or (output.data or {})["image/jpeg"] then
      count = count + 1
      paths[count] = cache.file(buf, output)
    end
  end
  local index = number == "" and 1 or tonumber(number)
  if not index or index < 1 or index % 1 ~= 0 then
    vim.notify("Chart number must be a positive integer", vim.log.levels.WARN)
    return
  end
  local path = paths[index]
  if not path then
    vim.notify("No chart in the current cell; run the plotting cell first", vim.log.levels.WARN)
    return
  end
  vim.ui.open(path)
end

local group = vim.api.nvim_create_augroup("NotebookRsCharts", { clear = true })
require("notebook_rs.charts.overlap").watch(function()
  for buf in pairs(M.slots) do M.finish(buf) end
end, function()
  for _, slots in pairs(M.slots) do if #slots > 0 then return true end end
  return false
end)
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "WinClosed", "TabEnter", "WinResized", "WinScrolled" }, {
  group = group,
  callback = function()
    for buf in pairs(M.slots) do M.finish(buf) end
  end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(args)
    renderer.release(args.buf)
    cache.release(args.buf)
    M.slots[args.buf], pending[args.buf] = nil, nil
  end,
})

return M
