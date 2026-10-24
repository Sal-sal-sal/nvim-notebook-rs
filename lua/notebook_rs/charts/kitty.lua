local M = {}

-- image.nvim handles geometry and conversion; explicit cell dimensions keep
-- Kitty placements correct on Retina screens and clip them to the window.
function M.attach(image)
  local state = image.global_state
  if not state or not state.options or state.options.backend ~= "kitty" then return end
  local helpers = require("image/backends/kitty/helpers")
  local term = require("image/utils/term")
  local transmitted
  local base = state.backend
  local backend = { features = { crop = true } }
  backend.clear = function(id, shallow)
    transmitted = nil
    base.clear(id, shallow)
  end
  backend.render = function(current, x, y, width, height)
    local size = term.get_size()
    if not size then return end
    local bounds = current.bounds
    local left, top = math.max(x, bounds.left), math.max(y, bounds.top)
    local right = math.min(x + width, bounds.right)
    local bottom = math.min(y + height, bounds.bottom + 1)
    local columns, rows = right - left, bottom - top
    if columns <= 0 or rows <= 0 then return end
    if transmitted ~= current.cropped_path then
      local ssh = vim.env.SSH_CLIENT ~= nil or vim.env.SSH_TTY ~= nil
      helpers.write_graphics({ action = "t", image_id = current.internal_id,
        transmit_format = 100, transmit_medium = ssh and "d" or "f",
        tty = ssh and term.get_tty() or nil, display_cursor_policy = 1, quiet = 2 },
        current.cropped_path, state.options.kitty_direct_chunk_size)
      transmitted = current.cropped_path
    end
    helpers.write_graphics_at({ action = "p", image_id = current.internal_id,
      placement_id = current.internal_id, quiet = 2, display_zindex = -1,
      display_cursor_policy = 1, display_columns = columns, display_rows = rows,
      display_x = (left - x) * size.cell_width, display_y = (top - y) * size.cell_height,
      display_width = columns * size.cell_width, display_height = rows * size.cell_height,
    }, left + 1, top + 1)
    state.images[current.id] = current
    current.is_rendered = true
  end
  image.global_state = vim.tbl_extend("force", state, { backend = backend })
end

return M
