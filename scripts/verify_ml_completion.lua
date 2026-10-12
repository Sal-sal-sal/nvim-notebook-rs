-- Run with the user's Neovim config and an analysis environment containing ML libraries.
local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
require("lazy").load({ plugins = { "nvim-notebook-rs" } })
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
assert(vim.wait(20000, function()
  local clients = vim.lsp.get_clients({ bufnr = buf, name = "pyright" })
  return #clients == 1 and clients[1].initialized
end, 50), "Python LSP did not attach")
local probes = {
  { "import torch", "torch.", "tensor" },
  { "from torch import nn", "nn.", "Linear" },
  { "import torch", "torch.optim.", "Adam" },
  { "import tensorflow as tf", "tf.", "constant" },
  { "import tensorflow as tf", "tf.keras.layers.", "Dense" },
  { "import numpy as np", "np.", "array" },
  { "import pandas as pd", "pd.", "DataFrame" },
}
for _, probe in ipairs(probes) do
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# %% [code] id=probe", probe[1], probe[2] })
  local response = vim.lsp.buf_request_sync(buf, "textDocument/completion", {
    textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 2, character = #probe[2] },
  }, 30000)
  local names = {}
  for _, reply in pairs(response or {}) do
    for _, item in ipairs(reply.result and (reply.result.items or reply.result) or {}) do
      names[#names + 1] = item.label
    end
  end
  assert(vim.tbl_contains(names, probe[3]), probe[2] .. probe[3] .. " completion missing")
  print(probe[2] .. probe[3] .. ": passed (" .. #names .. " suggestions)")
end
vim.fn.delete(path)
