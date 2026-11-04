vim.opt.rtp:append(assert(vim.env.NOTEBOOK_RS_ROOT))
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
require("notebook_rs").setup({ python_lsp = { enabled = false } })

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/target", "p")
local path = dir .. "/target/actual.ipynb"
local link = dir .. "/alias.ipynb"
vim.cmd.NotebookNew(vim.fn.fnameescape(path))
vim.cmd.bwipeout()
assert(vim.uv.fs_symlink("target/actual.ipynb", link))
vim.cmd.edit(vim.fn.fnameescape(link))
vim.api.nvim_buf_set_lines(0, 1, -1, false, { "print(123)" })
vim.cmd.write()

assert(not vim.bo.modified, "writing through a symlink failed")
assert(vim.uv.fs_readlink(link) == "target/actual.ipynb", "writing replaced the symlink")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(saved.cells[1].source == "print(123)\n", "the symlink target was not updated")
vim.fn.delete(dir, "rf")
print("Saving through a relative symlink updates the target and preserves the link")
