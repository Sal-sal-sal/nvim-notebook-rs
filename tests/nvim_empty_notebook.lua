local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
require("notebook_rs").setup()

local path = vim.fn.tempname() .. ".ipynb"
vim.fn.writefile({}, path)
assert(vim.fn.getfsize(path) == 0)
vim.cmd("edit " .. vim.fn.fnameescape(path))
assert(vim.b.notebook_rs_path == path and vim.bo.buftype == "acwrite",
  "zero-byte notebook did not open as an editable notebook")
assert(vim.bo.modified, "zero-byte notebook should require saving")
assert(vim.fn.getfsize(path) == 0, "opening overwrote the original empty file")
vim.api.nvim_buf_set_lines(0, 1, -1, false, { "print(42)" })
vim.cmd("write")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(saved.nbformat == 4 and saved.cells[1].source == "print(42)\n")
assert(not vim.bo.modified)

local explicit = vim.fn.tempname() .. ".ipynb"
vim.fn.writefile({}, explicit)
vim.cmd("NotebookNew " .. vim.fn.fnameescape(explicit))
local created = vim.json.decode(table.concat(vim.fn.readfile(explicit), "\n"))
assert(created.nbformat == 4 and #created.cells == 1)

vim.fn.delete(path)
vim.fn.delete(explicit)
print("Neovim empty notebook test passed")
