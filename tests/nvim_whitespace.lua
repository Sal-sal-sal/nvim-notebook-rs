local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
require("notebook_rs").setup({ python_lsp = { enabled = false }, cells_output_interacteable = true })

for _, suffix in ipairs({ "", " ", "\t", "  \t  " }) do
  local path = vim.fn.tempname() .. ".ipynb"
  vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  local lines = {
    "# %% [code] id=first" .. suffix, "print('first', end=' ')  ",
    "# %% [markdown] id=notes" .. suffix, "# Notes  ",
    "# %% [raw] id=raw" .. suffix, "# Raw  ",
    "# %% [code] id=last" .. suffix, "print('second')  ",
  }
  require("notebook_rs.output").replace(buf, lines, true)
  require("notebook_rs.cells").reset(buf)
  require("notebook_rs.navigation").refresh(buf)
  vim.cmd("NotebookCellGoto 4")
  assert(vim.api.nvim_win_get_cursor(0)[1] == 8, "trailing whitespace hid a cell boundary")
  vim.cmd("NotebookRun")
  assert(vim.wait(5000, function()
    local states = require("notebook_rs.cells").states[buf]
    return states and states.last == "ok"
  end, 20), "the cell with trailing whitespace did not run")
  local results = require("notebook_rs.ui").results[buf]
  assert(results.last and not results.first, "running one cell selected another cell")
  assert(results.last.source == "print('second')  \n", "Python source whitespace was changed")
  local visible = false
  for _, row in ipairs(require("notebook_rs.output").states[buf].rows) do
    visible = visible or (row.output and row.id == "last")
  end
  assert(visible, "interactive output lost the cell with trailing marker whitespace")
  local run = require("notebook_rs.client").once({
    op = "run", path = path, lines = lines, line = 2, all = true, backend = "local",
  })
  assert(run.success and run.output == "[Cell 1]\nfirst \n[Cell 2]\nsecond\n",
    "output formatting changed spaces or added an extra newline")
  vim.cmd("write")
  local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  assert(#saved.cells == 4 and saved.cells[4].id == "last")
  assert(saved.cells[4].source == "print('second')  \n")
  vim.fn.delete(path)
end
print("Neovim trailing whitespace, cell selection, and output formatting passed")
