local client = require("notebook_rs.client")
local M = {}

local function report(response)
  if not response.ok then
    vim.notify(response.error, vim.log.levels.ERROR, { title = "Notebook" })
    return false
  end
  return true
end

local function output(text, failed)
  local source = vim.api.nvim_get_current_win()
  if M.output_win and vim.api.nvim_win_is_valid(M.output_win) then
    vim.api.nvim_win_close(M.output_win, true)
  end
  vim.cmd("botright 12new")
  M.output_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "text"
  local lines = vim.split(text ~= "" and text or "[No output]", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "notebook-rs://output")
  vim.api.nvim_set_current_win(source)
  if failed then
    vim.notify("Notebook execution failed; see output panel", vim.log.levels.ERROR)
  end
end

local function notebook_buffer()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.b[buf].notebook_rs_path then
    error("open a notebook with :NotebookOpen first")
  end
  return buf
end

local function save(buf)
  local path = vim.b[buf].notebook_rs_path
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  client.once({ op = "save", path = path, lines = lines })
  vim.bo[buf].modified = false
  vim.notify("Saved " .. vim.fn.fnamemodify(path, ":~"))
end

function M.open(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  local data = client.once({ op = "open", path = absolute })
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "notebook-rs://" .. absolute)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "python"
  vim.b[buf].notebook_rs_path = absolute
  vim.b[buf].notebook_rs_backend = "local"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, data.lines)
  vim.bo[buf].modified = false
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local ok, err = pcall(save, buf)
      if not ok then
        vim.notify(err, vim.log.levels.ERROR, { title = "Notebook" })
      end
    end,
  })
end

function M.new(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  client.once({ op = "new", path = absolute })
  M.open(absolute)
end

function M.run(all)
  local buf = notebook_buffer()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local backend = vim.b[buf].notebook_rs_backend or "local"
  client.request({ op = "run", lines = lines, line = line, all = all, backend = backend }, function(response)
    if report(response) then
      output(response.data.output, not response.data.success)
    end
  end)
end

function M.backend(name)
  if name ~= "local" and name ~= "colab" then
    error("backend must be local or colab")
  end
  local buf = notebook_buffer()
  vim.b[buf].notebook_rs_backend = name
  vim.notify("Notebook backend: " .. name)
end

function M.colab(payload)
  client.request(payload, function(response)
    if report(response) then
      output(response.data.output, not response.data.success)
      if response.data.success and response.data.session then
        vim.notify("Colab session: " .. response.data.session)
      end
    end
  end)
end

function M.login()
  local executable = vim.env.NVIM_NOTEBOOK_COLAB or "colab"
  vim.cmd("botright 12new")
  vim.fn.termopen({ executable, "sessions" })
  vim.cmd("startinsert")
end

return M
