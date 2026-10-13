local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local plugin = require("notebook_rs")
plugin.setup({ cells_output_interacteable = true, python_lsp = { enabled = false } })
local projection = require("notebook_rs.output")
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local source = { "# %% [code] id=long", "for i in range(100): print('Output line', i)",
  "# %% [code] id=next", "print('next cell')" }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  local state = require("notebook_rs.cells").states[buf]
  return state and state.long == "ok"
end, 20), "long cell did not finish")
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "execution moved the cursor")
vim.cmd("normal! jj")
assert(vim.api.nvim_get_current_line():find("Output line 0", 1, true), "j skipped the output")
vim.cmd("normal! 30j")
assert(vim.api.nvim_get_current_line():find("Output line 30", 1, true), "j did not traverse output lines")
vim.fn.search("Output line 50", "W")
assert(vim.api.nvim_get_current_line():find("Output line 50", 1, true), "output is not searchable")
vim.cmd("normal! yy")
assert(vim.fn.getreg('"') == "Output line 50\n", "yank included display markup")
local cursor = vim.api.nvim_win_get_cursor(0)[1]
vim.cmd("normal! zt")
local before = vim.fn.winsaveview()
require("notebook_rs.cells").render(buf)
assert(vim.api.nvim_win_get_cursor(0)[1] == cursor, "redraw moved the output cursor")
assert(vim.fn.winsaveview().topline == before.topline, "redraw moved the output viewport")
require("notebook_rs.ui").results[buf].long = nil
vim.cmd("NotebookRun")
assert(vim.wait(5000, function() return require("notebook_rs.ui").results[buf].long ~= nil end, 20),
  "running from output did not execute its source cell")
assert(not require("notebook_rs.ui").results[buf].next, "running from output selected the following cell")
assert(vim.api.nvim_win_get_cursor(0)[1] == cursor, "rerunning moved the reader to the bottom")
vim.cmd("NotebookCellNext")
assert(vim.api.nvim_get_current_line() == source[4], "next-cell jump landed inside output")
vim.cmd("NotebookCellPrev")
assert(vim.api.nvim_get_current_line() == source[2], "previous-cell jump missed source")
vim.cmd("NotebookCellGoto 2")
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  return require("notebook_rs.ui").results[buf].next ~= nil
end, 20), "second cell did not execute")
assert(require("notebook_rs.ui").results[buf].next.outputs[1].text == "next cell\n",
  "output text was executed as Python")
vim.cmd("write")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(saved.cells[1].source == source[2] .. "\n" and saved.cells[2].source == source[4] .. "\n")
assert(saved.cells[1].outputs[1].text:find("Output line 99", 1, true))
assert(not vim.bo.modified, "saving left the notebook dirty")
vim.cmd("edit!")
assert(not vim.bo.modified, "materializing saved output marked the notebook modified")
assert(vim.api.nvim_buf_line_count(0) > 100, "saved text output was not restored as lines")
plugin.setup({ cells_output_interacteable = false })
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), source), "disabling interaction changed source")
local ns = vim.api.nvim_get_namespaces().notebook_rs_cells
local virtual = false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
  virtual = virtual or #(mark[4].virt_lines or {}) > 100
end
assert(virtual, "disabled mode lost virtual output")
plugin.setup({ cells_output_interacteable = true, nootbook_result = "window" })
assert(vim.deep_equal(projection.source(buf), source) and vim.api.nvim_buf_line_count(0) == #source)
plugin.setup({ nootbook_result = "hidden" })
assert(vim.api.nvim_buf_line_count(0) == #source)
plugin.setup({ nootbook_result = "nootbook" })
assert(vim.api.nvim_buf_line_count(0) > 100, "enabling interaction did not rebuild open buffers")
assert(not pcall(plugin.setup, { cells_output_interacteable = "yes" }), "invalid option was accepted")
assert(require("notebook_rs.config").cells_output_interacteable, "invalid config changed the active mode")
vim.fn.delete(path)
print("Inline output navigation, search, yank, save, and configuration passed")
