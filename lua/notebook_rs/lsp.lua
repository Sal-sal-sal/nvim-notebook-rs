local M = {}

local function python_path(settings)
  return settings and settings.python and settings.python.pythonPath
end

function M.attach(buf)
  local options = require("notebook_rs.config").python_lsp
  if not options.enabled or not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].notebook_rs_path then
    return
  end
  local server = options.server
  if #vim.lsp.get_clients({ bufnr = buf, name = server }) > 0 then
    return
  end
  local native = vim.lsp.config and vim.lsp.config[server]
  local config = native and vim.deepcopy(native) or {}
  config.name = server
  config.cmd = options.cmd or config.cmd or { server .. "-langserver", "--stdio" }
  if type(config.cmd) == "table" and vim.fn.executable(config.cmd[1]) ~= 1 then
    return
  end
  config.root_dir = vim.fn.fnamemodify(vim.b[buf].notebook_rs_path, ":h")
  config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
    python = { analysis = {
      autoImportCompletions = true, useLibraryCodeForTypes = true, diagnosticMode = "openFilesOnly",
    } },
  })
  local interpreter = options.python_path or vim.env.NVIM_NOTEBOOK_PYTHON
  if interpreter then
    config.settings.python.pythonPath = interpreter
  end
  config.capabilities = config.capabilities or vim.lsp.protocol.make_client_capabilities()
  if package.loaded["blink.cmp"] then
    config.capabilities = require("blink.cmp").get_lsp_capabilities(config.capabilities)
  end
  vim.lsp.start(config, {
    bufnr = buf,
    reuse_client = function(client, requested)
      return client.name == requested.name and client.config.root_dir == requested.root_dir
        and python_path(client.config.settings) == python_path(requested.settings)
    end,
  })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("NotebookRsLsp", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "InsertEnter", "FileType" }, {
    group = group,
    callback = function(args) vim.schedule(function() M.attach(args.buf) end) end,
    desc = "Attach Python language services to notebook acwrite buffers",
  })
end

return M
