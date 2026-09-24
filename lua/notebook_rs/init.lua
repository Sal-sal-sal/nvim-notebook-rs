local M = {}

function M.setup()
  if vim.g.notebook_rs_loaded then
    return
  end
  vim.g.notebook_rs_loaded = true
  local ui = require("notebook_rs.ui")
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
