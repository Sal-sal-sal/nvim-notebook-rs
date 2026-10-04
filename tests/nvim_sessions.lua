local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local cli = vim.fn.tempname()
vim.fn.writefile({
  "#!/usr/bin/env python3",
  "import os, runpy, sys",
  "if sys.argv[1] == 'sessions':",
  "    print(os.environ.get('SESSION_LIST', ''))",
  "    sys.exit(int(os.environ.get('SESSION_EXIT', '0')))",
  "runpy.run_path(os.environ['FAKE_COLAB'], run_name='__main__')",
}, cli)
vim.fn.setfperm(cli, "rwx------")
vim.env.NVIM_NOTEBOOK_COLAB = cli
vim.env.FAKE_COLAB = root .. "/tests/fake_colab.py"
vim.env.SESSION_LIST = "[training] | Hardware: T4\n[other] | Hardware: CPU"
vim.env.NVIM_NOTEBOOK_COLAB_CA_BUNDLE = nil
require("notebook_rs").setup()
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local notebook = vim.api.nvim_get_current_buf()
local selected = false
vim.ui.select = function(items, opts, callback)
  assert(#items == 3 and items[1].name == "training" and items[3].kind == "new")
  assert(opts.format_item(items[1]) == "Connect to training")
  selected = true
  callback(items[1])
end
vim.cmd("NotebookColabNew unused T4")
local status = require("notebook_rs.status")
assert(vim.wait(5000, function() return selected and status.state == "connected" end, 20))
assert(status.session == "training" and vim.b[notebook].notebook_rs_backend == "colab")

selected = false
vim.ui.select = function(items, _, callback)
  selected = true
  callback(items[#items])
end
vim.api.nvim_set_current_buf(notebook)
vim.cmd("NotebookColabNew fresh T4")
assert(vim.wait(5000, function() return selected and status.session == "fresh" end, 20))
assert(status.state == "connected")

selected = false
vim.ui.select = function(_, _, callback)
  selected = true
  callback(nil)
end
vim.cmd("NotebookColabNew cancelled")
assert(vim.wait(5000, function() return selected end, 20))
assert(status.session == "fresh", "cancelling changed the selected session")

vim.fn.delete(path)
vim.fn.delete(cli)
print("Neovim session reuse, creation, and cancellation passed")
