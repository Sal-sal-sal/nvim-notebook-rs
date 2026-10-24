local M = {}

function M.anchor(buf, win, slot)
  local row, offset = slot.row, slot.offset
  local first = vim.fn.screenpos(win, row + 1, 1)
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  if first.row == 0 and view.topline == row + 2 and view.topfill > 0 then
    -- Virtual lines belong to the following screen row in Neovim's viewport.
    -- Anchor there while partially scrolled, preserving this image's own slot.
    row = view.topline - 1
    local fill = vim.api.nvim_win_text_height(win, { start_row = row, end_row = row }).fill
    local position = vim.fn.screenpos(win, row + 1, 1)
    offset = slot.offset - fill + (position.row == 0 and view.topfill or -1)
  else
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local last = vim.fn.screenpos(win, row + 1, math.max(1, #line))
    if first.row > 0 and last.row > 0 then offset = offset + math.max(0, last.row - first.row) end
  end
  return row, offset
end

return M
