local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.mapleader = " "
vim.g.notebook_rs_bin = vim.env.NOTEBOOK_RS_BIN or (root .. "/target/debug/nvim-notebook-rs")
vim.env.NVIM_NOTEBOOK_COLAB = root .. "/tests/fake_colab.py"
require("notebook_rs").setup()

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# %% [code] id=one", "raise ValueError('local boom')",
  "# %% [code] id=two", "raise TypeError('second boom')",
})
vim.cmd("write")

local function inline_text(at_row)
  local result = {}
  local namespace = vim.api.nvim_get_namespaces().notebook_rs_cells
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })) do
    if not at_row or mark[2] == at_row then
      for _, line in ipairs(mark[4].virt_lines or {}) do
        for _, chunk in ipairs(line) do
          result[#result + 1] = chunk[1]
        end
      end
    end
  end
  return table.concat(result, "\n")
end

vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  return require("notebook_rs.cells").states[buf].one == "error"
end, 20), "local Python error did not complete")
assert(inline_text(1):find("ValueError: local boom", 1, true),
  "local traceback is missing below its cell")

vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  return require("notebook_rs.cells").states[buf].two == "error"
end, 20), "second Python error did not complete")
assert(inline_text(3):find("TypeError: second boom", 1, true),
  "second traceback is missing below its cell")
vim.cmd("write")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(saved.cells[1].outputs[1].output_type == "error")
assert(saved.cells[1].outputs[1].ename == "ValueError")
assert(saved.cells[2].outputs[1].ename == "TypeError")
assert(saved.cells[1].source == "raise ValueError('local boom')\n",
  "virtual traceback changed the Python source")
vim.cmd("edit!")
assert(inline_text():find("ValueError: local boom", 1, true),
  "saved traceback did not return after reopening")
assert(inline_text():find("TypeError: second boom", 1, true),
  "second saved traceback did not return after reopening")
assert(not vim.bo.modified, "rendering saved errors modified the notebook")

vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "print('fixed')" })
vim.cmd("doautocmd TextChanged")
assert(not inline_text():find("ValueError: local boom", 1, true),
  "edited cell kept a stale traceback")
assert(inline_text():find("TypeError: second boom", 1, true),
  "editing another cell cleared this cell's traceback")
vim.cmd("write")
vim.cmd("edit!")
assert(not inline_text():find("ValueError: local boom", 1, true),
  "stale traceback returned after saving an edit")
assert(inline_text():find("TypeError: second boom", 1, true),
  "unchanged cell lost its saved traceback")
vim.api.nvim_buf_set_lines(buf, 4, 4, false, { "" })
vim.cmd("doautocmd TextChanged")
assert(not inline_text():find("TypeError: second boom", 1, true),
  "adding a blank line kept a stale traceback")
vim.cmd("write")
vim.cmd("edit!")
local cleared = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(vim.tbl_isempty(cleared.cells[2].outputs), "saved notebook kept a stale traceback")

local chosen = false
for _, suffix in ipairs({ "l", "n", "c", "s", "p", "r", "u", "x", "b", "L", "i", "f", "U", "D" }) do
  assert(not vim.tbl_isempty(vim.fn.maparg(" cc" .. suffix, "n", false, true)),
    "Colab action shortcut is missing: " .. suffix)
end
local original_select, original_input = vim.ui.select, vim.ui.input
vim.ui.select = function(items, opts, callback)
  assert(opts.prompt:find("Colab", 1, true))
  for _, item in ipairs(items) do
    if item.key == "c" then
      chosen = true
      callback(item)
      return
    end
  end
  error("connection action is missing")
end
vim.ui.input = function(_, callback) callback("training") end
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end
press(" cc")
assert(chosen, "<leader>cc did not open the Colab actions")
assert(vim.wait(5000, function() return require("notebook_rs.status").state == "connected" end, 20),
  "Colab connection menu did not connect through the CLI")
vim.ui.select, vim.ui.input = original_select, original_input
press(" ccb")
assert(vim.b.notebook_rs_backend == "colab", "Colab backend shortcut did not work")
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "raise ValueError('remote boom')" })
vim.cmd("doautocmd TextChanged")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  return inline_text():find("ValueError: bad cell", 1, true) ~= nil
end, 20), "Colab CLI traceback is missing below its cell")
press(" ccx")
assert(vim.wait(5000, function() return require("notebook_rs.status").state == "disconnected" end, 20),
  "Colab stop shortcut did not disconnect")
press(" ccL")
assert(vim.b.notebook_rs_backend == "local", "local backend shortcut did not work")

vim.fn.delete(path)
print("Neovim inline error test passed")
