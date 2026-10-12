local M = {}

local function executable(label, path, required, advice)
  if vim.fn.executable(path) == 1 then
    vim.health.ok(label .. ": " .. path)
  elseif required then
    vim.health.error(label .. " not found: " .. path)
  else
    vim.health.warn(label .. " not found: " .. path .. " (" .. (advice or "needed only for Colab") .. ")")
  end
end

function M.check()
  vim.health.start("nvim-notebook-rs")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10 or newer")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end
  local ok, binary = pcall(require("notebook_rs.client").binary)
  if ok then
    vim.health.ok("Rust worker: " .. binary)
  else
    vim.health.error(tostring(binary), { "Run cargo build --release --locked in the plugin directory" })
  end
  executable("Python", vim.env.NVIM_NOTEBOOK_PYTHON or "python3", true)
  executable("Colab CLI", vim.env.NVIM_NOTEBOOK_COLAB or "colab", false)
  local lsp = require("notebook_rs.config").python_lsp
  if lsp.enabled then
    local command = lsp.cmd and lsp.cmd[1] or (lsp.server .. "-langserver")
    executable("Python language server", command, false, "install Pyright for notebook completion")
    if lsp.python_path then executable("Python analysis interpreter", lsp.python_path, true) end
  end
  local bundle = vim.env.NVIM_NOTEBOOK_COLAB_CA_BUNDLE
  if bundle and bundle ~= "" then
    if vim.fn.filereadable(bundle) == 1 then
      vim.health.ok("Colab CA bundle is readable")
    else
      vim.health.error("Colab CA bundle is not readable: " .. bundle)
    end
  end
end

return M
