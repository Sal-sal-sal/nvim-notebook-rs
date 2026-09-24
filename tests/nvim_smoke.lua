local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = vim.env.NOTEBOOK_RS_BIN or (root .. "/target/debug/nvim-notebook-rs")
vim.env.NVIM_NOTEBOOK_COLAB = root .. "/tests/fake_colab.py"
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

assert(vim.bo.modified, "cell output did not mark notebook for saving")
vim.cmd("write")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(saved.cells[2].outputs[1].text:find("42", 1, true), "cell output was not saved")

vim.cmd("NotebookCellNew markdown")
assert(#vim.api.nvim_buf_get_lines(0, 0, -1, false) == 6)
vim.cmd("NotebookCellMove up")
assert(vim.api.nvim_buf_get_lines(0, 2, 3, false)[1]:find("markdown", 1, true))
vim.cmd("NotebookCellDelete")
vim.cmd("write")
local final = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(#final.cells == 2 and final.cells[2].source == "x + 2\n")

vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("NotebookCellNew code")
vim.api.nvim_buf_set_lines(0, 5, 6, false, { "import matplotlib.pyplot as plt; plt.plot([1, 2], [3, 4])" })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "notebook-rs://output" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("![Image output]", 1, true) ~= nil
    end
  end
  return false
end, 20), "local matplotlib image was not displayed")
vim.cmd("write")
local plotted = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
local has_image = false
for _, cell_output in ipairs(plotted.cells[3].outputs) do
  has_image = has_image or (cell_output.data and cell_output.data["image/png"]:len() > 100)
end
assert(has_image, "plot image was not saved to ipynb")
vim.cmd("NotebookCellDelete")
vim.cmd("write")

vim.cmd("NotebookColabConnect training")
assert(vim.wait(5000, function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "notebook-rs://output" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("status --session training", 1, true) ~= nil
    end
  end
  return false
end, 20), "Colab CLI connect did not complete")
vim.cmd("NotebookBackend colab")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "notebook-rs://output" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("remote:x + 2", 1, true) ~= nil
    end
  end
  return false
end, 20), "Colab CLI cell did not run")
vim.api.nvim_buf_set_lines(0, 3, 4, false, { "raise ValueError('bad cell')" })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "notebook-rs://output" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("ValueError: bad cell", 1, true) ~= nil
    end
  end
  return false
end, 20), "Colab CLI Python error was not shown")
vim.cmd("write")
local remote = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(remote.cells[2].outputs[1].output_type == "error")

vim.fn.delete(path)
print("Neovim notebook smoke test passed")
