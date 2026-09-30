local client = require("notebook_rs.client")
local icon = require("notebook_rs.status_icon")
local M = { state = "disconnected", session = nil, last_check = 0, checking = false }

local function redraw()
  if package.loaded.lualine then
    package.loaded.lualine.refresh({ place = { "statusline" } })
  else
    vim.cmd("redrawstatus")
  end
end

function M.set(state, session)
  M.state = state
  M.session = type(session) == "string" and session or nil
  M.last_check = vim.uv.now()
  vim.schedule(redraw)
end

function M.component()
  if not vim.b.notebook_rs_path then
    return ""
  end
  local text = icon.render(M.state)
  if M.session then
    text = text .. " [" .. M.session .. "]"
  end
  return text .. " · run: " .. (vim.b.notebook_rs_backend or "local")
end

function M.color()
  local group = ({ connected = "DiagnosticOk", connecting = "DiagnosticWarn",
    disconnected = "DiagnosticError", error = "DiagnosticError" })[M.state]
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  return hl.fg and { fg = ("#%06x"):format(hl.fg) } or nil
end

function M.execution_result(data)
  if data.success then
    M.set("connected", M.session)
    return
  end
  for _, result in ipairs(data.results or {}) do
    for _, output in ipairs(result.outputs or {}) do
      if output.output_type == "error" then
        M.set("connected", M.session)
        return
      end
    end
  end
  M.set("error", M.session)
end

function M.check(force)
  if M.state ~= "connected" or M.checking or not vim.b.notebook_rs_path then
    return
  end
  if not force and vim.uv.now() - M.last_check < 300000 then
    return
  end
  M.checking = true
  client.request({ op = "colab_status" }, function(response)
    M.checking = false
    if response.ok and response.data.success then
      M.set("connected", response.data.session)
    else
      M.set("error", M.session)
    end
  end)
end

return M
