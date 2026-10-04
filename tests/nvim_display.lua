local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local plugin = require("notebook_rs")
plugin.setup()
local config = require("notebook_rs.config")
assert(config.nootbook_hidden_id_line and config.nootbook_result == "nootbook")

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# %% [code] id=first", "print('first')",
  "# %% [code] id=second", "print('second')",
  "# %% [code] id=third", "print('third')",
})
require("notebook_rs.cells").render(buf)

local function inline_text()
  local chunks = {}
  local ns = vim.api.nvim_get_namespaces().notebook_rs_cells
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      for _, chunk in ipairs(line) do
        chunks[#chunks + 1] = chunk[1]
      end
    end
  end
  return table.concat(chunks, "\n")
end

local function marker_count()
  local ns = vim.api.nvim_get_namespaces().notebook_rs_markers
  return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
end

assert(marker_count() == 3 and vim.wo.conceallevel >= 2, "marker lines were not concealed")
if vim.fn.has("nvim-0.11") == 1 then
  local ns = vim.api.nvim_get_namespaces().notebook_rs_markers
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  assert(marks[3][4].conceal_lines == "", "whole-line conceal is missing")
end
local border_row = vim.fn.has("nvim-0.11") == 1 and 5 or 4
assert(vim.api.nvim_win_text_height(0, { start_row = border_row, end_row = border_row }).all > 1,
  "concealing the marker also hid the cell border")
assert(vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1] == "# %% [code] id=third",
  "concealing a marker changed the Python source")

vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  return inline_text():find("third", 1, true) ~= nil
end, 20), "default notebook output is not inline")
assert(not require("notebook_rs.ui").results[buf].second, "third cell ran the second cell")
assert(not require("notebook_rs.panel").win, "default run opened an output window")
vim.cmd("write")
vim.cmd("edit!")
assert(inline_text():find("third", 1, true), "saved notebook output was not restored")

plugin.setup({ nootbook_result = "window", nootbook_hidden_id_line = false })
assert(marker_count() == 0, "disabling marker conceal did not reveal marker lines")
assert(not inline_text():find("├─ OUTPUT", 1, true), "window mode kept inline output")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  local win = require("notebook_rs.panel").win
  return win and vim.api.nvim_win_is_valid(win)
    and table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
      :find("second", 1, true) ~= nil
end, 20), "window mode did not show the result")

local panel = require("notebook_rs.panel")
vim.api.nvim_win_close(panel.win, true)
plugin.setup({ nootbook_result = "hidden", nootbook_hidden_id_line = true })
assert(marker_count() == 3, "marker conceal did not reactivate")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  return require("notebook_rs.cells").states[buf].first == "ok"
end, 20), "hidden mode did not execute the cell")
assert(not inline_text():find("├─ OUTPUT", 1, true), "hidden mode kept inline output")
assert(not vim.api.nvim_win_is_valid(panel.win), "hidden mode opened a panel")

assert(not pcall(plugin.setup, { nootbook_result = "other" }))
assert(not pcall(plugin.setup, { nootbook_hidden_id_line = "true" }))
assert(config.nootbook_result == "hidden" and config.nootbook_hidden_id_line)

for _, case in ipairs({
  { row = 1, marker = "# %% [code] id=" },
  { row = 3, marker = "# %% [unknown] id=bad" },
  { row = 5, marker = "# %% [code] }d=bad" },
  { row = 3, marker = "# %% [code]  id=bad" },
}) do
  local original = vim.api.nvim_buf_get_lines(buf, case.row - 1, case.row, false)[1]
  vim.api.nvim_buf_set_lines(buf, case.row - 1, case.row, false, { case.marker })
  require("notebook_rs.cells").render(buf)
  assert(inline_text():find("INVALID CELL MARKER", 1, true),
    "bad marker is not visible at line " .. case.row)
  local ok, err = pcall(require("notebook_rs.client").once, {
    op = "run", lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    line = case.row + 1, all = false, backend = "local", path = path,
  })
  assert(not ok and tostring(err):find("invalid cell marker on line " .. case.row, 1, true),
    "bad marker was accepted at line " .. case.row)
  vim.api.nvim_buf_set_lines(buf, case.row - 1, case.row, false, { original })
end
vim.fn.delete(path)
print("Neovim display settings test passed")
