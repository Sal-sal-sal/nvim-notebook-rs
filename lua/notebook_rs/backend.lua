local M = {}

function M.select(buf, name, notify)
  if name ~= "local" and name ~= "colab" then
    error("backend must be local or colab")
  end
  vim.b[buf].notebook_rs_backend = name
  vim.cmd("redrawstatus")
  if notify then
    vim.notify("Notebook backend: " .. name)
  end
end

function M.attach(buf)
  local connected = require("notebook_rs.status").state == "connected"
  M.select(buf, connected and "colab" or "local")
end

function M.connected(buf)
  if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].notebook_rs_path then
    M.select(buf, "colab")
  end
end

return M
