local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.mapleader = " "
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local plugin = require("notebook_rs")
plugin.setup({ python_lsp = { enabled = false } })
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local output = require("notebook_rs.output")
local cells = require("notebook_rs.cells")
local inline = require("notebook_rs.inline")
local source = {
  "# %% [code] id=one", "print('one')", "print('more')",
  "# %% [markdown] id=two", "# Notes", "# Details",
  "# %% [raw] id=three", "# Raw", "# More raw",
}

local function active(first, last)
  local ns = vim.api.nvim_get_namespaces().notebook_rs_focus
  local range, arrow
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    if mark[4].hl_group == "NotebookRsActiveCell" then range = mark end
    if mark[4].sign_text then arrow = mark end
  end
  assert(range and range[2] == first - 1 and range[4].end_row == last,
    "active highlight does not cover exactly the current cell")
  assert(range[4].hl_eol and arrow, "active cell has no full-width tint or indicator")
end

for _, hidden in ipairs({ true, false }) do
  for _, interactive in ipairs({ true, false }) do
    plugin.setup({ nootbook_hidden_id_line = hidden, cells_output_interacteable = interactive })
    for deleted = 1, 3 do
      inline.records[buf] = {}
      output.replace(buf, source, true)
      cells.reset(buf)
      vim.cmd("NotebookCellGoto 1")
      vim.cmd("NotebookRun")
      assert(vim.wait(5000, function() return cells.states[buf].one == "ok" end, 20))
      vim.cmd("NotebookCellGoto " .. deleted)
      vim.api.nvim_feedkeys(" ccx", "xt", false)
      local target = deleted < 3 and deleted or deleted - 1
      local remaining = output.source(buf)
      local first = (target - 1) * 3 + 1
      local last = target * 3
      local cursor = output.display_row(buf, first + 1)
      assert(vim.api.nvim_win_get_cursor(0)[1] == cursor,
        "deletion landed on a marker or another cell")
      active(output.display_row(buf, first), output.display_row(buf, last))
      assert(#remaining == 6, "deletion removed another cell's source")
      vim.cmd("write")
      local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
      assert(#saved.cells == 2, "deletion was not saved")
      if deleted ~= 1 then
        assert(saved.cells[1].outputs[1].text == "one\nmore\n", "neighbor output was lost")
      end
      vim.cmd("NotebookCellGoto 1")
      active(1, output.display_row(buf, 4) - 1)
      vim.api.nvim_win_set_cursor(0, { output.display_row(buf, 6), 0 })
      vim.cmd("doautocmd CursorMoved")
      active(output.display_row(buf, 4), vim.api.nvim_buf_line_count(buf))
    end
  end
end

for _, source in ipairs({
  { "# %% [code] id=a", "# %% [code] id=b" },
  { "# %% [code] id=a", "", "# %% [code] id=b", "" },
}) do
  inline.records[buf] = {}
  output.replace(buf, source, true)
  cells.reset(buf)
  vim.cmd("NotebookCellGoto 1")
  vim.cmd("NotebookCellDelete")
  assert(vim.api.nvim_win_get_cursor(0)[1] == #source / 2, "empty-cell cursor is invalid")
  local before = output.source(buf)
  assert(not pcall(vim.cmd, "NotebookCellDelete"), "deleting the only cell must report an error")
  assert(vim.deep_equal(before, output.source(buf)), "deletion removed the only cell")
end
vim.fn.delete(path)
print("Neovim cell deletion and active highlight test passed")
