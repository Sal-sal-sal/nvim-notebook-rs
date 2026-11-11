local M = {}

function M.request(buf, config)
  local options = require("notebook_rs.config").python_lsp
  local docs = options.documentation
  local python = options.python_path or (config.settings or {}).python
    and config.settings.python.pythonPath or vim.env.NVIM_NOTEBOOK_PYTHON or vim.fn.exepath("python3")
  local root = vim.fn.fnamemodify(vim.b[buf].notebook_rs_path, ":h")
  local cache = docs.cache or (vim.fn.stdpath("cache") .. "/notebook-rs/library-docs")
  local profile = cache .. "/profiles/" .. vim.fn.sha256(python .. "\n" .. root):sub(1, 24)
  vim.fn.mkdir(profile, "p")
  return { python = python, root = root, cache = cache, profile = profile,
    packages = docs.packages, max_download_mb = docs.max_download_mb }
end

function M.configure(config, buf)
  local request = M.request(buf, config)
  config.settings = config.settings or {}
  config.settings.python = config.settings.python or {}
  config.settings.python.analysis = config.settings.python.analysis or {}
  local analysis = config.settings.python.analysis
  analysis.extraPaths = analysis.extraPaths or {}
  if not vim.tbl_contains(analysis.extraPaths, request.profile) then
    analysis.extraPaths[#analysis.extraPaths + 1] = request.profile
  end
  return request
end

function M.refresh(buf, force)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.name == require("notebook_rs.config").python_lsp.server then
      local previous = vim.json.encode(((client.config.settings or {}).python or {}).analysis or {})
      M.configure(client.config, buf)
      if force or previous ~= vim.json.encode(client.config.settings.python.analysis) then
        local params = { settings = client.config.settings }
        if vim.fn.has("nvim-0.11") == 1 then client:notify("workspace/didChangeConfiguration", params)
        else client.notify("workspace/didChangeConfiguration", params) end
      end
    end
  end
end

return M
