local root = assert(vim.env.NOTEBOOK_RS_ROOT)
local executable = assert(vim.env.NVIM_NOTEBOOK_COLAB)
local session = vim.env.NOTEBOOK_RS_SESSION or "nvim"
assert(vim.fn.executable(executable) == 1, "Colab CLI is unavailable")
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
require("notebook_rs").setup()

local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# %% [code] id=torch-import", "import torch",
})
vim.cmd("NotebookColabConnect " .. session)
assert(vim.wait(30000, function()
  return require("notebook_rs.status").state ~= "connecting"
end, 50), "Colab connection check timed out")
if require("notebook_rs.status").state ~= "connected" then
  local win = require("notebook_rs.panel").win
  local output = win and vim.api.nvim_win_is_valid(win)
    and table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n") or ""
  error("Colab session did not pass its live kernel check: " .. output:sub(-1800))
end

assert(vim.b[buf].notebook_rs_backend == "colab", "Colab connection kept the local backend")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(90000, function()
  local state = require("notebook_rs.cells").states[buf]
  return state and (state["torch-import"] == "ok" or state["torch-import"] == "error")
end, 50), "import torch did not finish")
local result = require("notebook_rs.ui").results[buf]["torch-import"]
assert(require("notebook_rs.cells").states[buf]["torch-import"] == "ok"
  and result and result.source == "import torch\n"
  and #(result.outputs or {}) == 0, "import torch failed on the Colab kernel")
vim.fn.delete(path)
print("Live Colab cell passed: import torch")
