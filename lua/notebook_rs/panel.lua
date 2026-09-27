local M = {}

function M.show(text, failed, failure_message)
  local buf
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    buf = vim.api.nvim_win_get_buf(M.win)
    vim.bo[buf].modifiable = true
  else
    local source = vim.api.nvim_get_current_win()
    vim.cmd("botright 12new")
    M.win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_name(buf, "notebook-rs://output")
    vim.api.nvim_set_current_win(source)
  end
  local lines = vim.split(text ~= "" and text or "[No output]", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if failed then
    vim.notify(failure_message or "Notebook execution failed; see output panel", vim.log.levels.WARN)
  end
end

return M
