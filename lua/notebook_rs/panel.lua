local M = {}

function M.show(text, failed, failure_message)
  local source = vim.api.nvim_get_current_win()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  vim.cmd("botright 12new")
  M.win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  local lines = vim.split(text ~= "" and text or "[No output]", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "notebook-rs://output")
  vim.api.nvim_set_current_win(source)
  if failed then
    vim.notify(failure_message or "Notebook execution failed; see output panel", vim.log.levels.WARN)
  end
end

return M
