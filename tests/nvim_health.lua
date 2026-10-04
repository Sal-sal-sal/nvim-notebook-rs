local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
vim.env.NVIM_NOTEBOOK_PYTHON = vim.fn.exepath("python3")
vim.env.NVIM_NOTEBOOK_COLAB = root .. "/tests/fake_colab.py"
vim.env.NVIM_NOTEBOOK_COLAB_CA_BUNDLE = nil
require("notebook_rs").setup()
vim.cmd("checkhealth notebook_rs")
local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(report:find("Rust worker:", 1, true) and report:find("Python:", 1, true))
assert(not report:find("ERROR", 1, true), report)

vim.env.NVIM_NOTEBOOK_PYTHON = "/missing/notebook-python"
vim.env.NVIM_NOTEBOOK_COLAB = "/missing/colab-cli"
vim.env.NVIM_NOTEBOOK_COLAB_CA_BUNDLE = "/missing/ca-bundle.pem"
vim.cmd("checkhealth notebook_rs")
report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(report:find("Python not found:", 1, true), report)
assert(report:find("needed only for Colab", 1, true), report)
assert(report:find("Colab CA bundle is not readable", 1, true), report)
print("Neovim installation diagnostics passed")
