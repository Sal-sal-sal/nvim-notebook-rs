local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.mapleader = " "
vim.g.notebook_rs_bin = vim.env.NOTEBOOK_RS_BIN or (root .. "/target/debug/nvim-notebook-rs")
require("notebook_rs").setup()

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# %% [code] id=one", "x = 40",
  "# %% [code] id=two", "print(x + 2)",
  "# %% [markdown] id=three", "# Notes",
  "# %% [code] id=four", "print('last')",
})
vim.cmd("doautocmd TextChanged")

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function row()
  return vim.api.nvim_win_get_cursor(0)[1]
end

local function output_contains(word)
  for _, item in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(item) == "notebook-rs://output" then
      local lines = vim.api.nvim_buf_get_lines(item, 0, -1, false)
      return table.concat(lines, "\n"):find(word, 1, true) ~= nil
    end
  end
  return false
end

vim.api.nvim_win_set_cursor(0, { 2, 0 })
press(" jc")
assert(row() == 4, "next cell shortcut did not reach cell 2")
press(" jc")
assert(row() == 6, "next cell shortcut did not include Markdown")
press(" kc")
assert(row() == 4, "previous cell shortcut did not reach cell 2")
press(" 1b")
assert(row() == 2, "numeric shortcut did not reach cell 1")
vim.cmd("NotebookCellGoto 4")
assert(row() == 8, "goto command did not reach cell 4")
press(" jc")
assert(row() == 8, "next cell at end moved the cursor")
vim.cmd("NotebookCellGoto 99")
assert(row() == 8, "invalid cell number moved the cursor")
vim.cmd("NotebookCellPrev")
assert(row() == 6, "previous cell command did not reach Markdown")
vim.cmd("NotebookCellNext")
assert(row() == 8, "next cell command did not return to cell 4")

press(" 1b")
press(" rr")
assert(vim.wait(5000, function()
  return require("notebook_rs.cells").states[buf].one == "ok"
end, 20), "run shortcut did not execute the first cell")
press(" 2b")
press(" rc")
assert(vim.wait(5000, function() return output_contains("42") end, 20),
  "current-cell shortcut did not run Python with shared state")
press(" ra")
assert(vim.wait(5000, function() return output_contains("last") end, 20),
  "run-all shortcut did not execute the last code cell")

vim.cmd("NotebookCellNew code")
press(" 5b")
assert(row() == 10, "new cell did not get a numeric shortcut")
vim.cmd("NotebookCellDelete")
assert(vim.tbl_isempty(vim.fn.maparg(" 5b", "n", false, true)),
  "deleted cell kept a stale numeric shortcut")

local many = {}
for number = 1, 12 do
  many[#many + 1] = ("# %%%% [code] id=cell-%d"):format(number)
  many[#many + 1] = ("print(%d)"):format(number)
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, many)
vim.cmd("doautocmd TextChanged")
press(" 10b")
assert(row() == 20, "multi-digit shortcut did not reach cell 10")
press(" 12b")
assert(row() == 24, "multi-digit shortcut did not reach cell 12")

vim.cmd("enew!")
assert(vim.tbl_isempty(vim.fn.maparg(" jc", "n", false, true)),
  "notebook navigation leaked into a plain buffer")
vim.fn.delete(path)
print("Neovim navigation test passed")
