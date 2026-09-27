local client = require("notebook_rs.client")
local cells = require("notebook_rs.cells")
local guard = require("notebook_rs.guard")
local panel = require("notebook_rs.panel")
local status = require("notebook_rs.status")
local M = { results = {}, artifacts = {} }

local function report(response)
  if not response.ok then
    vim.notify(response.error, vim.log.levels.ERROR, { title = "Notebook" })
    return false
  end
  return true
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
  guard.check(buf, path)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  client.once({ op = "save", path = path, lines = lines, results = vim.tbl_values(M.results[buf] or {}) })
  guard.saved(buf, path)
  M.results[buf] = {}
  vim.bo[buf].modified = false
  vim.notify("Saved " .. vim.fn.fnamemodify(path, ":~"))
end

function M.attach(buf, path, is_new)
  local absolute = vim.fn.fnamemodify(path, ":p")
  local data = is_new and { lines = { "# %% [code] id=cell-1" } }
    or client.once({ op = "open", path = absolute })
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "python"
  vim.b[buf].notebook_rs_path = absolute
  vim.b[buf].notebook_rs_backend = "local"
  guard.open(buf, absolute)
  M.results[buf] = {}
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, data.lines)
  vim.bo[buf].modified = false
  require("notebook_rs.inline").attach(buf, data.errors)
  cells.render(buf)
  local group = vim.api.nvim_create_augroup("NotebookRsBuffer" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = function()
      local ok, err = pcall(save, buf)
      if not ok then
        vim.notify(err, vim.log.levels.ERROR, { title = "Notebook" })
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      M.results[buf] = nil
      require("notebook_rs.inline").release(buf)
      guard.release(buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function() cells.reset(buf) end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
    group = group,
    buffer = buf,
    callback = function() cells.focus(buf) end,
  })
end

function M.open(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  if not vim.uv.fs_stat(absolute) then
    error("notebook does not exist: " .. absolute .. "; use :NotebookNew")
  end
  vim.cmd.edit(vim.fn.fnameescape(absolute))
end

function M.new(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  client.once({ op = "new", path = absolute })
  M.open(absolute)
end

function M.edit(action, kind)
  local buf = notebook_buffer()
  local data = client.once({
    op = "edit",
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    row = vim.api.nvim_win_get_cursor(0)[1],
    action = action,
    kind = kind,
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, data.lines)
  vim.api.nvim_win_set_cursor(0, { data.cursor, 0 })
  cells.reset(buf)
  require("notebook_rs.navigation").refresh(buf)
end

function M.run(all)
  local buf = notebook_buffer()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local backend = vim.b[buf].notebook_rs_backend or "local"
  cells.begin(buf, lines, line, all)
  client.request({ op = "run", lines = lines, line = line, all = all, backend = backend,
    path = vim.b[buf].notebook_rs_path }, function(response)
    if report(response) then
      if vim.api.nvim_buf_is_valid(buf) then
        require("notebook_rs.inline").update(buf, response.data.results or {})
        cells.finish(buf, response.data.results or {}, response.data.success)
        for _, result in ipairs(response.data.results or {}) do
          M.results[buf][result.id] = result
          vim.bo[buf].modified = true
        end
      end
      M.artifacts = response.data.artifacts or {}
      panel.show(response.data.output, not response.data.success)
      if backend == "colab" then
        status.execution_result(response.data)
      end
    elseif vim.api.nvim_buf_is_valid(buf) then
      cells.finish(buf, {}, false)
      if backend == "colab" then
        status.set("error", status.session)
      end
    end
  end)
end

function M.restart_local()
  local buf = notebook_buffer()
  client.request({ op = "restart_local", path = vim.b[buf].notebook_rs_path }, function(response)
    if report(response) then
      vim.notify("Local Python kernel restarted")
    end
  end)
end

function M.open_artifact(index)
  local path = M.artifacts[tonumber(index) or #M.artifacts]
  if not path then
    vim.notify("No image or HTML output from the latest run", vim.log.levels.WARN)
    return
  end
  vim.ui.open(path)
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
  if payload.op == "colab_new" or payload.op == "colab_connect" or payload.op == "colab_status" then
    status.set("connecting", status.session)
  end
  client.request(payload, function(response)
    if not response.ok or not response.data.success then
      local selected = response.ok and response.data.session
      status.set("error", type(selected) == "string" and selected or status.session)
    elseif payload.op == "colab_stop" then
      status.set("disconnected")
    elseif type(response.data.session) == "string" then
      status.set("connected", response.data.session)
    end
    if report(response) then
      panel.show(response.data.output, not response.data.success,
        "Colab command failed; see output panel")
      if response.data.success and type(response.data.session) == "string" then
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
