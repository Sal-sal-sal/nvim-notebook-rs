local M = {}

local function edge(border, index)
  if type(border) == "string" then return border ~= "none" and border ~= "" and 1 or 0 end
  if not border or #border == 0 then return 0 end
  local part = border[(index - 1) % #border + 1]
  if type(part) == "table" then part = part[1] end
  return part and part ~= "" and 1 or 0
end

function M.masks()
  local masks = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative ~= "" and not config.hide and not config.external then
      local pos = vim.api.nvim_win_get_position(win)
      local info = vim.fn.getwininfo(win)[1]
      masks[#masks + 1] = { id = win, zindex = config.zindex or 50,
        left = pos[2], top = pos[1],
        right = info.wincol - 1 + info.width + edge(config.border, 4),
        bottom = info.winrow - 1 + info.height + edge(config.border, 6) }
    end
  end
  if vim.fn.pumvisible() == 1 then
    local menu = vim.fn.pum_getpos()
    masks[#masks + 1] = { id = -1, zindex = 100, left = menu.col, top = menu.row,
      right = menu.col + menu.width + (menu.scrollbar and 1 or 0), bottom = menu.row + menu.height }
  end
  return masks
end

function M.covered(image, x, y, width, height)
  local bounds = image.bounds or {}
  local left, top = math.max(x, bounds.left or x), math.max(y, bounds.top or y)
  local right = math.min(x + width, bounds.right or (x + width))
  local bottom = math.min(y + height, bounds.bottom and bounds.bottom + 1 or (y + height))
  if left >= right or top >= bottom then return false end
  local zindex = 0
  if image.window and vim.api.nvim_win_is_valid(image.window) then
    zindex = vim.api.nvim_win_get_config(image.window).zindex or 0
  end
  for _, mask in ipairs(M.masks()) do
    if mask.id ~= image.window and mask.zindex > zindex
      and mask.left < right and mask.right > left and mask.top < bottom and mask.bottom > top then
      return true
    end
  end
  return false
end

function M.clear(image)
  local rect = image.rendered_geometry
  if image.is_rendered and rect and rect.width and M.covered(image, rect.x, rect.y, rect.width, rect.height) then
    image:clear(true)
  end
end

function M.attach(image)
  local state = image.global_state
  if not state or not state.backend then return end
  local render = state.backend.render
  local backend = vim.tbl_extend("force", state.backend, {
    render = function(current, x, y, width, height)
      if M.covered(current, x, y, width, height) then
        if current.is_rendered then current:clear(true) end
        return
      end
      return render(current, x, y, width, height)
    end,
  })
  image.global_state = vim.tbl_extend("force", state, { backend = backend })
end

function M.watch(changed, enabled)
  local previous
  vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace("notebook_rs_chart_overlap"), {
    on_start = function()
      if not enabled() then previous = nil; return false end
      -- which-key deliberately suppresses autocmds when creating its windows.
      local signature = vim.api.nvim_get_current_tabpage() .. ":" .. vim.json.encode(M.masks())
      if signature ~= previous then
        previous = signature
        vim.schedule(changed)
      end
      return false
    end,
  })
end

return M
