local M = {}
local buf
local origin
local namespace = vim.api.nvim_create_namespace("notebook_rs_colab_journal")

local function window()
  if vim.api.nvim_get_current_buf() ~= buf then origin = vim.api.nvim_get_current_win() end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local wins = vim.fn.win_findbuf(buf)
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
        vim.api.nvim_set_current_win(win)
        return win
      end
    end
  else
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "notebook-rs://colab-journal")
    vim.bo[buf].buftype, vim.bo[buf].bufhidden = "nofile", "hide"
    vim.bo[buf].swapfile, vim.bo[buf].filetype = false, "log"
  end
  vim.cmd("botright " .. math.max(10, math.floor(vim.o.lines / 2)) .. "split")
  vim.api.nvim_win_set_buf(0, buf)
  return vim.api.nvim_get_current_win()
end

function M.show(data, refresh)
  local win = window()
  local previous = vim.api.nvim_win_get_cursor(win)
  local lines, folds, headings = require("notebook_rs.journal.format").render(data)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable, vim.bo[buf].modified = false, false
  vim.wo[win].wrap, vim.wo[win].number, vim.wo[win].relativenumber = false, false, false
  vim.wo[win].list = false
  vim.wo[win].signcolumn, vim.wo[win].foldcolumn = "no", "1"
  vim.wo[win].foldmethod, vim.wo[win].foldenable = "manual", true
  vim.wo[win].foldtext = "getline(v:foldstart)"
  vim.cmd("silent! normal! zE")
  for _, fold in ipairs(folds) do vim.cmd(("%d,%dfold"):format(fold[1], fold[2])) end
  if folds[1] then
    vim.api.nvim_win_set_cursor(win, { folds[1][1], 0 })
    vim.cmd("normal! zo")
  end
  if previous[1] > 1 then vim.api.nvim_win_set_cursor(win, { math.min(previous[1], #lines), 0 }) end
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, namespace, 0, 0, { line_hl_group = "Title" })
  for _, heading in ipairs(headings) do
    local color = ({ OK = "DiagnosticOk", ERROR = "DiagnosticError", RUNNING = "DiagnosticWarn",
      INTERRUPTED = "DiagnosticWarn" })[heading.state]
    vim.api.nvim_buf_set_extmark(buf, namespace, heading.row, 0, { line_hl_group = color })
  end
  vim.keymap.set("n", "<CR>", "za", { buffer = buf, desc = "Journal: fold/unfold request" })
  vim.keymap.set("n", "r", refresh, { buffer = buf, desc = "Journal: refresh" })
  vim.keymap.set("n", "q", function()
    vim.cmd.close()
    if origin and vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end
  end, { buffer = buf, desc = "Journal: close" })
end

return M
