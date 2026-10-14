local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local plugin = require("notebook_rs")
plugin.setup({ python_lsp = { enabled = false } })
local config = require("notebook_rs.config")
assert(config.notebook_highlight_current == true and config.borer_highlight_colore == "auto")
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local source = { "# %% [code] id=one", "print(1)", "print(2)",
  "# %% [markdown] id=two", "# Notes", "# More notes", "# %% [raw] id=three", "# Raw" }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.cmd("doautocmd TextChanged")
local cells = require("notebook_rs.cells")

local function borders()
  local result = {}
  local ns = vim.api.nvim_get_namespaces().notebook_rs_cells
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    assert(not mark[4].line_hl_group and not mark[4].hl_group, "border painted source text")
    local lines = mark[4].virt_lines or {}
    local color = lines[#lines] and lines[#lines][1][2]
    if color and color:match("^NotebookRsActiveBorder") then
      result[#result + 1] = { row = mark[2], color = color, above = mark[4].virt_lines_above }
    end
  end
  return result
end

local function check(enabled, foreground)
  local active = borders()
  assert(#active == (enabled and 2 or 0), "active borders did not follow the enable setting")
  local ns = vim.api.nvim_get_namespaces().notebook_rs_focus
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  assert(#marks == (enabled and 1 or 0), "active arrow did not follow the enable setting")
  for _, mark in ipairs(marks) do
    assert(not mark[4].hl_group and not mark[4].line_hl_group and not mark[4].end_row,
      "active indicator highlighted cell contents")
  end
  for _, border in ipairs(active) do
    local highlight = vim.api.nvim_get_hl(0, { name = border.color, link = false })
    assert(not highlight.bg, "active border color adds a background")
    if foreground then assert(highlight.fg == foreground, "custom border color was ignored") end
  end
  assert(vim.deep_equal(require("notebook_rs.output").source(buf), source), "highlight changed source")
  return active
end

vim.api.nvim_set_hl(0, "NotebookRsCode", { fg = "#607080" })
vim.cmd("NotebookCellGoto 1")
local automatic = check(true)
for _, border in ipairs(automatic) do
  assert(vim.api.nvim_get_hl(0, { name = border.color, link = false }).fg > 0x607080,
    "automatic border is not lighter than the theme color")
end
plugin.setup({ borer_highlight_colore = "#AABBCC" })
for cell = 1, 3 do
  vim.cmd("NotebookCellGoto " .. cell)
  check(true, 0xaabbcc)
end
plugin.setup({ notebook_highlight_current = false })
vim.cmd("NotebookCellPrev")
check(false)
plugin.setup({ notebook_highlight_current = true })
check(true, 0xaabbcc)
vim.cmd("NotebookCellGoto 1")
cells.begin(buf, source, 2, false)
check(true, 0xaabbcc)
cells.finish(buf, { { id = "one" } }, false)
check(true, 0xaabbcc)
vim.cmd("NotebookCellNext")
check(true, 0xaabbcc)
plugin.setup({ borer_highlight_colore = "auto" })
vim.cmd("colorscheme default")
check(true)
for _, invalid in ipairs({ "red", "#123", "#GGGGGG", false, 1 }) do
  assert(not pcall(plugin.setup, { notebook_highlight_current = false, borer_highlight_colore = invalid }))
  assert(config.notebook_highlight_current == true and config.borer_highlight_colore == "auto")
end
assert(not pcall(plugin.setup, { notebook_highlight_current = 1 }))
check(true)
vim.fn.delete(path)
print("Neovim border-only focus, live settings, colors, statuses, and theme refresh passed")
