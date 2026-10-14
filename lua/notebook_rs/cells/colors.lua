local M = { code = "NotebookRsCode", markdown = "NotebookRsMarkdown", raw = "NotebookRsRaw" }
local cache = {}

function M.setup()
  for group, target in pairs({ NotebookRsCode = "DiagnosticInfo", NotebookRsMarkdown = "DiagnosticHint",
    NotebookRsRaw = "DiagnosticWarn", NotebookRsRunning = "DiagnosticWarn", NotebookRsFailed = "DiagnosticError" }) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
  cache = {}
end

function M.active(base)
  local color = require("notebook_rs.config").borer_highlight_colore
  if color == "auto" then
    local foreground = vim.api.nvim_get_hl(0, { name = base, link = false }).fg
      or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg or 0xe0e2ea
    local channels = {}
    for _, divisor in ipairs({ 65536, 256, 1 }) do
      local channel = math.floor(foreground / divisor) % 256
      channels[#channels + 1] = math.floor(channel + (255 - channel) * 0.2 + 0.5)
    end
    color = ("#%02x%02x%02x"):format(unpack(channels))
  end
  local group = "NotebookRsActiveBorder" .. base
  if cache[group] ~= color then
    vim.api.nvim_set_hl(0, group, { fg = color })
    cache[group] = color
  end
  return group
end

M.setup()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("NotebookRsCellColors", { clear = true }),
  callback = function()
    M.setup()
    local cells = package.loaded["notebook_rs.cells"]
    if not cells then return end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.b[buf].notebook_rs_path then cells.render(buf) end
    end
  end,
})
return M
