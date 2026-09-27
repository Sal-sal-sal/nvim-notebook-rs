local M = {}

local STATES = {
  connected = { icon = "●", label = "Colab connected" },
  disconnected = { icon = "○", label = "Colab disconnected" },
  connecting = { icon = "◌", label = "Colab connecting" },
  error = { icon = "!", label = "Colab error" },
}

local function render(state, options)
  local entry = assert(STATES[state], "unknown Colab status: " .. tostring(state))
  options = options or {}
  local icon = (options.icons and options.icons[state]) or entry.icon
  if options.icon_only then
    return icon
  end
  local label = (options.labels and options.labels[state]) or entry.label
  return icon .. " " .. label
end

M.render = render
M.connected = function(options) return render("connected", options) end
M.disconnected = function(options) return render("disconnected", options) end
M.connecting = function(options) return render("connecting", options) end
M.error = function(options) return render("error", options) end

return M
