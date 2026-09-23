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
  }) do
    command(name, function() ui.colab({ op = op }) end, {})
  end
end

return M
