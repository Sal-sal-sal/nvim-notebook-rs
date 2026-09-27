local M = {}

local function attach_safely(ui, args, is_new)
  local ok, err = pcall(ui.attach, args.buf, args.file, is_new)
  if ok then
    return
  end
  local buf = args.buf
  vim.api.nvim_create_augroup("NotebookRsBuffer" .. buf, { clear = true })
  vim.b[buf].notebook_rs_path = nil
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "text"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "Notebook could not be opened:",
    tostring(err),
    "The original file was not changed. Fix or convert it before reopening.",
  })
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.notify("Notebook open failed; original file is unchanged", vim.log.levels.WARN)
end

function M.setup(opts)
  if opts and opts.distance_between_cells ~= nil then
    local distance = opts.distance_between_cells
    assert(type(distance) == "number" and distance >= 0 and distance % 1 == 0,
      "distance_between_cells must be a non-negative integer")
    local cells = require("notebook_rs.cells")
    cells.distance_between_cells = distance
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.b[buf].notebook_rs_path then
        cells.render(buf)
      end
    end
  end
  if vim.g.notebook_rs_loaded then
    return
  end
  vim.g.notebook_rs_loaded = true
  local ui = require("notebook_rs.ui")
  local group = vim.api.nvim_create_augroup("NotebookRsFiles", { clear = true })
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "*.ipynb",
    callback = function(args) attach_safely(ui, args, vim.uv.fs_stat(args.file) == nil) end,
    desc = "Open Jupyter notebook cells with nvim-notebook-rs",
  })
  vim.api.nvim_create_autocmd("BufNewFile", {
    group = group,
    pattern = "*.ipynb",
    callback = function(args) attach_safely(ui, args, true) end,
    desc = "Create a Jupyter notebook buffer with nvim-notebook-rs",
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "FocusGained" }, {
    group = group,
    callback = function() require("notebook_rs.status").check() end,
    desc = "Refresh selected Colab session status",
  })
  local command = vim.api.nvim_create_user_command
  command("NotebookOpen", function(opts) ui.open(opts.args) end, { nargs = 1, complete = "file" })
  command("NotebookNew", function(opts) ui.new(opts.args) end, { nargs = 1, complete = "file" })
  command("NotebookRun", function() ui.run(false) end, {})
  command("NotebookRunAll", function() ui.run(true) end, {})
  command("NotebookRestart", ui.restart_local, {})
  command("NotebookCellNew", function(opts) ui.edit("insert", opts.args ~= "" and opts.args or "code") end, {
    nargs = "?",
    complete = function() return { "code", "markdown", "raw" } end,
  })
  command("NotebookCellDelete", function() ui.edit("delete") end, {})
  command("NotebookCellMove", function(opts) ui.edit(opts.args) end, {
    nargs = 1,
    complete = function() return { "up", "down" } end,
  })
  command("NotebookOpenArtifact", function(opts) ui.open_artifact(opts.args) end, { nargs = "?" })
  command("NotebookBackend", function(opts) ui.backend(opts.args) end, {
    nargs = 1,
    complete = function() return { "local", "colab" } end,
  })
  command("NotebookColabLogin", ui.login, {})
  command("NotebookColabNew", function(opts)
    ui.colab({ op = "colab_new", session = opts.fargs[1] or "nvim", gpu = opts.fargs[2] })
  end, { nargs = "*" })
  command("NotebookColabConnect", function(opts)
    ui.colab({ op = "colab_connect", session = opts.args })
  end, { nargs = 1 })
  for name, op in pairs({
    NotebookColabStatus = "colab_status",
    NotebookColabStop = "colab_stop",
    NotebookColabSessions = "colab_sessions",
    NotebookColabRestart = "colab_restart",
    NotebookColabURL = "colab_url",
  }) do
    command(name, function() ui.colab({ op = op }) end, {})
  end
  command("NotebookColabInstall", function(opts)
    ui.colab({ op = "colab_install", packages = opts.fargs })
  end, { nargs = "+" })
  command("NotebookColabUpload", function(opts)
    assert(#opts.fargs == 2, "Usage: NotebookColabUpload LOCAL REMOTE")
    ui.colab({ op = "colab_upload", ["local"] = vim.fn.fnamemodify(opts.fargs[1], ":p"), remote = opts.fargs[2] })
  end, { nargs = "+", complete = "file" })
  command("NotebookColabDownload", function(opts)
    assert(#opts.fargs == 2, "Usage: NotebookColabDownload REMOTE LOCAL")
    ui.colab({ op = "colab_download", remote = opts.fargs[1], ["local"] = vim.fn.fnamemodify(opts.fargs[2], ":p") })
  end, { nargs = "+" })
  command("NotebookColabList", function(opts)
    ui.colab({ op = "colab_list", path = opts.args ~= "" and opts.args or nil })
  end, { nargs = "?" })
end

return M
