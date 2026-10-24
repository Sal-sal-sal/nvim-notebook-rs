local M = {}
local active = {}
local failed = {}

function M.available(path)
  if path and failed[path] then return false end
  if #vim.api.nvim_list_uis() == 0 then return false end
  local ok, api = pcall(require, "image")
  return ok and type(api.from_file) == "function" and (not api.is_enabled or api.is_enabled())
end

local function clear(key)
  local image = active[key]
  if image then pcall(image.clear, image) end
  active[key] = nil
end

function M.release(buf)
  for key, image in pairs(active) do
    if image.buffer == buf then clear(key) end
  end
end

function M.sync(buf, slots)
  local wanted = {}
  local retry_layout = false
  if M.available() then
    local api = require("image")
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      if vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
        local info = vim.fn.getwininfo(win)[1]
        for index, slot in ipairs(slots) do
          local key = ("notebook-rs:%d:%d:%d"):format(buf, win, index)
          wanted[key] = true
          local image = active[key]
          if image and image.original_path ~= slot.path then clear(key); image = nil end
          local width = math.max(1, math.min(100, info.width - info.textoff - 2))
          if not image then
            local ok, created = pcall(api.from_file, slot.path, {
              id = key, namespace = "notebook-rs", window = win, buffer = buf,
              x = 0, y = slot.row, width = width, height = slot.height,
              inline = false, with_virtual_padding = false,
              max_width_window_percentage = 100, max_height_window_percentage = 100,
            })
            if ok and created then
              image = created
              ok = pcall(require("notebook_rs.charts.kitty").attach, image)
            end
            if not ok or not image then
              failed[slot.path], retry_layout = true, true
              if image then pcall(image.clear, image); image = nil end
            end
            active[key] = image
          end
          if image then
            local row, offset = require("notebook_rs.charts.geometry").anchor(buf, win, slot)
            image.render_offset_top = offset
            local ok = pcall(image.render, image, { x = 0, y = row, width = width, height = slot.height })
            if not ok then
              failed[slot.path], retry_layout = true, true
              clear(key)
            end
          end
        end
      end
    end
  end
  for key, image in pairs(active) do
    if image.buffer == buf and not wanted[key] then clear(key) end
  end
  return retry_layout
end

return M
