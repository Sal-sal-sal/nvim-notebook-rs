local layout = require("notebook_rs.output.layout")
local namespace = vim.api.nvim_create_namespace("notebook_rs_output_text")
local M = {}

local function capture(buf, rows)
  local views = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    views[#views + 1] = { win = win, view = view, cursor = rows[view.lnum], top = rows[view.topline] }
  end
  return views
end

local function restore(buf, rows, views)
  for _, saved in ipairs(views) do
    if vim.api.nvim_win_is_valid(saved.win) and vim.api.nvim_win_get_buf(saved.win) == buf then
      local view = saved.view
      view.lnum = layout.locate(rows, saved.cursor)
      view.topline = layout.locate(rows, saved.top)
      view.col = math.min(view.col, #rows[view.lnum].text)
      vim.api.nvim_win_call(saved.win, function() vim.fn.winrestview(view) end)
    end
  end
end

function M.apply(buf, state, rows)
  local lines = vim.tbl_map(function(row) return row.text end, rows)
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local views = capture(buf, state.rows)
  state.busy = true
  if not vim.deep_equal(lines, current) then
    vim.api.nvim_buf_call(buf, function() vim.cmd("silent! undojoin") end)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  state.rows = rows
  state.busy, state.blocked = false, false
  vim.bo[buf].modified = state.modified
  restore(buf, rows, views)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  if vim.tbl_contains(vim.tbl_map(function(row) return row.output or false end, rows), true) then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.wo[win].conceallevel = math.max(2, vim.wo[win].conceallevel)
      vim.wo[win].concealcursor = "nivc"
    end
  end
  for row, item in ipairs(rows) do
    if item.output then
      vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, 0, {
        end_col = #item.text, hl_group = item.color, hl_eol = true, priority = 110,
      })
      vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, 0, {
        end_col = #state.prefix, conceal = "", priority = 120,
      })
    end
  end
end

return M
