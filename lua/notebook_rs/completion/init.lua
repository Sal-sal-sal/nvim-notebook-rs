local M = { results = {} }
local pending, seen, running = {}, {}, {}
local paths = require("notebook_rs.completion.paths")

local function imported(buf)
  local source = require("notebook_rs.output").source(buf)
  local lines = {}
  for _, line in ipairs(source) do
    if line:match("^%s*import%s+") or line:match("^%s*from%s+") then lines[#lines + 1] = line end
  end
  return table.concat(lines, "\n")
end

local function report(data, manual)
  local ready, failed = {}, {}
  for _, item in ipairs(data.modules or {}) do
    if item.status == "cached" and (manual or item.downloaded) then
      ready[#ready + 1] = item.module .. " " .. item.version
    elseif item.status == "unavailable" then
      failed[#failed + 1] = item.module .. ": " .. item.message
    end
  end
  if #ready > 0 then vim.notify("Library documentation ready: " .. table.concat(ready, ", ")) end
  if #failed > 0 then vim.notify(table.concat(failed, "\n"), vim.log.levels.WARN, { title = "Library documentation" }) end
  if manual and #ready == 0 and #failed == 0 then vim.notify("Imported libraries already have local documentation") end
end

function M.ensure(buf, manual)
  local options = require("notebook_rs.config").python_lsp
  if not options.enabled or not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].notebook_rs_path then return end
  if not manual and not options.documentation.auto_download then return end
  local source = imported(buf)
  if source == "" then return end
  local clients = vim.lsp.get_clients({ bufnr = buf, name = options.server })
  local request = paths.request(buf, clients[1] and clients[1].config or {})
  request.source, request.refresh = source, manual or false
  local key = request.profile .. vim.json.encode(request.packages) .. source
  if running[request.profile] then return end
  if not manual and seen[key] and vim.uv.now() - seen[key] < 300000 then return end
  seen[key], running[request.profile] = vim.uv.now(), true
  local ok, binary = pcall(require("notebook_rs.client").binary)
  if not ok then running[request.profile] = nil; return end
  vim.system({ binary, "library-docs" }, { stdin = vim.json.encode(request), text = true }, function(result)
    vim.schedule(function()
      running[request.profile] = nil
      if result.code ~= 0 then
        vim.notify(result.stderr or "Library documentation failed", vim.log.levels.WARN)
        return
      end
      local decoded, data = pcall(vim.json.decode, result.stdout)
      if not decoded then return end
      M.results[request.profile] = data
      report(data, manual)
      for _, notebook in ipairs(vim.api.nvim_list_bufs()) do
        if vim.b[notebook].notebook_rs_path then
          local attached = vim.lsp.get_clients({ bufnr = notebook, name = options.server })
          local current = paths.request(notebook, attached[1] and attached[1].config or {})
          if current.profile == request.profile then
            paths.refresh(notebook, true)
            M.schedule(notebook)
          end
        end
      end
      if vim.api.nvim_buf_is_valid(buf) and imported(buf) ~= source then M.schedule(buf) end
    end)
  end)
end

function M.schedule(buf)
  pending[buf] = (pending[buf] or 0) + 1
  local version = pending[buf]
  vim.defer_fn(function()
    if pending[buf] == version then M.ensure(buf, false) end
  end, 1200)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("NotebookRsLibraryDocs", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group, callback = function(args) M.schedule(args.buf) end,
  })
  vim.api.nvim_create_user_command("NotebookLibraryDocs", function() M.ensure(vim.api.nvim_get_current_buf(), true) end, {})
end

return M
