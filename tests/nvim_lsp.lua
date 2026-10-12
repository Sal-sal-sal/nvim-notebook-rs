local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local server = vim.fn.exepath("pyright-langserver")
if server == "" then server = vim.fn.stdpath("data") .. "/mason/bin/pyright-langserver" end
if vim.fn.executable(server) ~= 1 then
  print("Python LSP check skipped: install pyright-langserver")
  return
end
require("notebook_rs").setup({ python_lsp = {
  cmd = { server, "--stdio" }, python_path = vim.env.NVIM_NOTEBOOK_PYTHON,
} })
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# %% [code] id=lsp", "import math", "math." })
assert(vim.bo[buf].buftype == "acwrite")
assert(vim.wait(20000, function()
  local clients = vim.lsp.get_clients({ bufnr = buf, name = "pyright" })
  return #clients == 1 and clients[1].initialized
end, 50), "Pyright did not attach to the notebook")
local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 2, character = 5 } }
local replies = vim.lsp.buf_request_sync(buf, "textDocument/completion", params, 15000)
local found = false
for _, reply in pairs(replies or {}) do
  for _, item in ipairs(reply.result and (reply.result.items or reply.result) or {}) do
    found = found or item.label == "sqrt"
  end
end
assert(found, "math.sqrt completion was missing from the notebook")
vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "math.sqrt(" })
params.position.character = 10
local signatures = vim.lsp.buf_request_sync(buf, "textDocument/signatureHelp", params, 15000)
local signature = false
for _, reply in pairs(signatures or {}) do
  signature = signature or (reply.result and #(reply.result.signatures or {}) > 0)
end
assert(signature, "notebook parameter hints were missing")
vim.fn.delete(path)
print("Neovim notebook completion and parameter hints passed")
