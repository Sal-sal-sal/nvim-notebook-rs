local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
require("notebook_rs").setup({ nootbook_result = "window" })

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# %% [code] id=first", "print('first')",
  "# %% [code] id=second", "print('second')",
  "# %% [code] id=third", "print('third')",
})
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  return require("notebook_rs.cells").states[buf]
    and require("notebook_rs.cells").states[buf].third == "ok"
end, 20), "third cell did not execute")
local results = require("notebook_rs.ui").results[buf]
assert(results.third and not results.second, "third-cell command selected another cell")

local panel = require("notebook_rs.panel")
assert(panel.win and vim.api.nvim_win_is_valid(panel.win))
vim.api.nvim_set_current_win(panel.win)
vim.api.nvim_win_close(vim.fn.bufwinid(buf), true)
assert(#vim.api.nvim_tabpage_list_wins(0) == 1, "panel is not the last window")
panel.show("replacement", false)
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "replacement",
  "output panel did not refresh as the last window")

vim.fn.delete(path)
print("Neovim regression test passed")
