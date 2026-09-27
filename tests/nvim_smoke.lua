local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = vim.env.NOTEBOOK_RS_BIN or (root .. "/target/debug/nvim-notebook-rs")
vim.env.NVIM_NOTEBOOK_COLAB = root .. "/tests/fake_colab.py"
require("notebook_rs").setup({ nootbook_result = "window" })

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
assert(vim.b.notebook_rs_path == path)
assert(vim.api.nvim_buf_get_name(0):match("%.ipynb$"), "notebook must keep its real filename")
local lines = { "# %% [code] id=one", "x = 40", "# %% [code] id=two", "x + 2" }
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.cmd("write")
local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(data.cells[1].source == "x = 40\n")
local namespace = vim.api.nvim_get_namespaces().notebook_rs_cells
local function border_contains(word)
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      for _, chunk in ipairs(line) do
        if chunk[1]:find(word, 1, true) then
          return true
        end
      end
    end
  end
  return false
end

vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(border_contains("RUNNING"), "running cell is not highlighted")
assert(vim.wait(5000, function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "notebook-rs://output" then
      return true
    end
  end
  return false
end, 20), "first cell did not return")
assert(border_contains("DONE"), "completed cell is not highlighted")

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
local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
assert(#marks == 6 and marks[1][4].virt_lines, "cell borders were not drawn")
local function has_gap(size)
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
    if #mark[4].virt_lines == size + 1 then
      return true
    end
  end
  return false
end
assert(has_gap(2), "two-line gap is missing")
require("notebook_rs").setup({ distance_between_cells = 1 })
assert(has_gap(1), "cell gap setting was not applied")
require("notebook_rs").setup({ distance_between_cells = 2 })
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
local status = require("notebook_rs.status")
assert(status.state == "connected" and status.component():find("training", 1, true),
  "statusline did not show connected Colab session")
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
assert(border_contains("ERROR"), "failed cell is not highlighted")
assert(vim.wait(5000, function() return status.state == "connected" end, 20),
  "Python cell error incorrectly disconnected Colab")
vim.cmd("write")
local remote = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(remote.cells[2].outputs[1].output_type == "error")
vim.cmd("NotebookColabStop")
assert(vim.wait(5000, function() return status.state == "disconnected" end, 20),
  "statusline did not show disconnected Colab session")
vim.wait(100)
assert(status.session == nil and not vim.v.errmsg:find("attempt to concatenate field", 1, true),
  "stopping Colab caused a status callback error")

local direct = vim.fn.tempname() .. ".ipynb"
vim.fn.writefile(vim.fn.readfile(path), direct)
vim.cmd("edit " .. vim.fn.fnameescape(direct))
assert(vim.b.notebook_rs_path == direct, "plain :edit did not open notebook cells")
assert(vim.bo.buftype == "acwrite" and vim.bo.filetype == "python")
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) == 4)
vim.api.nvim_buf_set_lines(0, 1, 2, false, { "print('local edit')" })
vim.fn.writefile({ " " }, direct, "a")
local external_size = vim.fn.getfsize(direct)
pcall(vim.cmd, "write")
assert(vim.bo.modified and vim.fn.getfsize(direct) == external_size,
  "saving overwrote a notebook changed by another process")

local invalid = vim.fn.tempname() .. ".ipynb"
vim.fn.writefile({ "not notebook JSON" }, invalid)
vim.cmd("edit! " .. vim.fn.fnameescape(invalid))
assert(vim.bo.buftype == "nofile" and not vim.bo.modifiable,
  "invalid notebook did not open in a safe read-only view")
pcall(vim.cmd, "write")
assert(vim.fn.readfile(invalid)[1] == "not notebook JSON", "invalid notebook was overwritten")

local direct_new = vim.fn.tempname() .. ".ipynb"
vim.cmd("edit! " .. vim.fn.fnameescape(direct_new))
assert(vim.b.notebook_rs_path == direct_new and vim.bo.buftype == "acwrite")
vim.cmd("write")
assert(vim.json.decode(table.concat(vim.fn.readfile(direct_new), "\n")).nbformat == 4,
  "plain :edit did not create a valid notebook")

vim.fn.delete(path)
vim.fn.delete(direct)
vim.fn.delete(invalid)
vim.fn.delete(direct_new)
print("Neovim notebook smoke test passed")
