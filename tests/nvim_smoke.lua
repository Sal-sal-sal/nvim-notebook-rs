local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = vim.env.NOTEBOOK_RS_BIN or (root .. "/target/debug/nvim-notebook-rs")
require("notebook_rs").setup()

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
assert(vim.b.notebook_rs_path == path)
local lines = { "# %% [code] id=one", "x = 40", "# %% [code] id=two", "x + 2" }
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.cmd("write")
local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(data.cells[1].source == "x = 40\n")

vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "notebook-rs://output" then
      return true
    end
  end
  return false
end, 20), "first cell did not return")

vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "notebook-rs://output" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("42", 1, true) ~= nil
    end
  end
  return false
end, 20), "second cell did not retain Python state")

vim.fn.delete(path)
print("Neovim notebook smoke test passed")
