local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
vim.env.NVIM_NOTEBOOK_COLAB = root .. "/tests/fake_colab.py"
vim.env.NVIM_NOTEBOOK_COLAB_CA_BUNDLE = nil
require("notebook_rs").setup()

local first = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(first))
local notebook = vim.api.nvim_get_current_buf()
local window = vim.api.nvim_get_current_win()
assert(vim.b[notebook].notebook_rs_backend == "local")

vim.cmd("NotebookColabConnect training")
assert(vim.wait(5000, function()
  return require("notebook_rs.status").state ~= "connecting"
end, 20), "connection timed out")
assert(require("notebook_rs.status").state == "connected")
assert(vim.b[notebook].notebook_rs_backend == "colab",
  "a connected notebook must run cells on Colab")
assert(require("notebook_rs.status").component():find("run: colab", 1, true))

vim.api.nvim_set_current_win(window)
vim.cmd("NotebookBackend local")
assert(vim.b[notebook].notebook_rs_backend == "local")
assert(require("notebook_rs.status").component():find("run: local", 1, true))

local second = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(second))
assert(vim.b.notebook_rs_backend == "colab",
  "notebooks opened during a Colab connection should use Colab")
vim.fn.delete(first)
vim.fn.delete(second)
print("Neovim backend routing test passed")
