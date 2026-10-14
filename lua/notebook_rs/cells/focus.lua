local colors = require("notebook_rs.cells.colors")
local borders = vim.api.nvim_create_namespace("notebook_rs_cells")
local namespace = vim.api.nvim_create_namespace("notebook_rs_focus")
local active = {}
local M = {}

local function paint(buf, decoration, color)
  local opts = vim.deepcopy(decoration.opts)
  opts.id = decoration.id
  local lines = opts.virt_lines
  lines[#lines][1][2] = color
  vim.api.nvim_buf_set_extmark(buf, borders, decoration.row, 0, opts)
end

local function restore(buf, frame)
  paint(buf, frame.top, frame.top.color)
  paint(buf, frame.bottom, frame.bottom.color)
end

function M.reset(buf)
  active[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1) end
end

function M.update(buf, frames)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  local selected
  if vim.api.nvim_get_current_buf() == buf then
    require("notebook_rs.output").cursor(buf)
    if require("notebook_rs.config").notebook_highlight_current then
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      for _, frame in ipairs(frames) do
        if cursor >= frame.first and cursor <= frame.last then selected = frame; break end
      end
    end
  end
  if active[buf] and active[buf] ~= selected then restore(buf, active[buf]) end
  if selected then
    local top = colors.active(selected.top.color)
    local bottom = colors.active(selected.bottom.color)
    if active[buf] ~= selected then
      paint(buf, selected.top, top)
      paint(buf, selected.bottom, bottom)
    end
    vim.api.nvim_buf_set_extmark(buf, namespace, selected.top.row, 0, {
      sign_text = "▶", sign_hl_group = top, priority = 60,
    })
  end
  active[buf] = selected
end
return M
