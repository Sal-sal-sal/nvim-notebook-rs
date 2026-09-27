local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.mapleader = " "
vim.g.notebook_rs_bin = vim.env.NOTEBOOK_RS_BIN or (root .. "/target/debug/nvim-notebook-rs")
require("notebook_rs").setup()

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# %% [code] id=first", "print('first')",
  "# %% [markdown] id=second", "# Notes",
  "# %% [code] id=third", "print('third')",
})
vim.cmd("write")

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function markers()
  local result = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local kind, id = line:match("^# %%%% %[(%a+)%] id=(%S+)")
    if kind then
      result[#result + 1] = { kind = kind, id = id }
    end
  end
  return result
end

local function assert_map(keys, description)
  local map = vim.fn.maparg(keys, "n", false, true)
  assert(not vim.tbl_isempty(map) and map.desc == description,
    keys .. " is missing or runs a different action")
end

assert_map(" cca", "Notebook: Add code cell above")
assert_map(" ccb", "Notebook: Add code cell below")
assert_map(" ccx", "Notebook: Delete cell")
assert_map(" ccB", "Colab: Use Colab backend")
assert_map(" ccX", "Colab: Stop session")

vim.api.nvim_win_set_cursor(0, { 4, 0 })
press(" cca")
local after_above = markers()
assert(#after_above == 4 and after_above[1].id == "first"
  and after_above[2].kind == "code" and after_above[3].id == "second"
  and after_above[4].id == "third", "above shortcut inserted in the wrong place")
assert(vim.api.nvim_win_get_cursor(0)[1] == 4, "cursor did not enter the new upper cell")

press(" ccb")
local after_below = markers()
assert(#after_below == 5 and after_below[2].id == after_above[2].id
  and after_below[3].kind == "code" and after_below[4].id == "second",
  "below shortcut inserted in the wrong place")
assert(vim.api.nvim_win_get_cursor(0)[1] == 6, "cursor did not enter the new lower cell")
vim.cmd("write")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(#saved.cells == 5 and saved.cells[2].cell_type == "code"
  and saved.cells[3].cell_type == "code" and saved.cells[4].id == "second",
  "inserted cell order was not saved to the notebook")

press(" ccx")
assert(#markers() == 4 and markers()[3].id == "second",
  "delete shortcut removed the wrong cell")
vim.cmd("NotebookCellGoto 2")
press(" ccx")
local restored = markers()
assert(#restored == 3 and restored[1].id == "first"
  and restored[2].id == "second" and restored[3].id == "third",
  "deleting inserted cells changed the original notebook")
vim.cmd("write")
local final = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(#final.cells == 3 and final.cells[2].source == "Notes\n"
  and final.cells[3].source == "print('third')\n", "saving changed original cell content")

vim.cmd("NotebookCellGoto 1")
press(" cca")
assert(markers()[2].id == "first", "above shortcut failed at the first cell")
vim.cmd("NotebookCellGoto 4")
press(" ccb")
assert(#markers() == 5 and markers()[4].id == "third",
  "below shortcut failed at the last cell")

vim.cmd("enew!")
assert(vim.tbl_isempty(vim.fn.maparg(" cca", "n", false, true)),
  "cell shortcuts leaked into a plain buffer")
vim.fn.delete(path)
print("Neovim cell shortcut test passed")
