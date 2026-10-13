local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
require("notebook_rs").setup({ cells_output_interacteable = true, python_lsp = { enabled = false } })
local projection = require("notebook_rs.output")
local path = vim.fn.tempname() .. ".ipynb"
local original = { nbformat = 4, nbformat_minor = 5, metadata = { keep = "notebook" }, cells = {
  { cell_type = "code", id = "text", metadata = { keep = "text" }, source = "print('saved')\n",
    execution_count = 7, outputs = {
      { output_type = "stream", name = "stdout", text = "saved\n# %% [code] id=impostor\n" },
      { output_type = "error", ename = "ValueError", evalue = "данные", traceback = { "Traceback:", "ValueError: данные" } },
    } },
  { cell_type = "markdown", id = "notes", metadata = { keep = "notes" }, source = "# Notes\n",
    attachments = { sample = { ["image/png"] = "attachment" } } },
  { cell_type = "code", id = "image", metadata = { keep = "image" }, source = "plot()\n",
    execution_count = 8, outputs = {
      { output_type = "display_data", metadata = { width = 1 }, data = { ["image/png"] = "aW1hZ2U=", ["text/plain"] = "Figure" } },
    } },
} }
vim.fn.writefile({ vim.json.encode(original) }, path)
vim.cmd("edit " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
assert(not vim.bo.modified)
local output_row
for row, item in ipairs(projection.states[buf].rows) do
  assert(not (item.output and item.id == "image"), "image placeholder became an editable text row")
  if item.output and item.text:find("│ saved", 1, true) then output_row = row end
end
assert(output_row, "saved text did not become navigable")
local ns = vim.api.nvim_get_namespaces().notebook_rs_cells
local has_image = false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
  for _, line in ipairs(mark[4].virt_lines or {}) do
    for _, chunk in ipairs(line) do has_image = has_image or chunk[1]:find("Image output", 1, true) ~= nil end
  end
end
assert(has_image, "image display was lost")
vim.cmd("write")
local function read() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end
assert(vim.deep_equal(read(), original), "viewing or saving changed notebook data")

vim.api.nvim_win_set_cursor(0, { output_row, 0 })
local text = vim.api.nvim_get_current_line()
vim.cmd("normal! dd")
assert(vim.wait(1000, function()
  return vim.api.nvim_buf_get_lines(buf, output_row - 1, output_row, false)[1] == text
end, 10), "output deletion was not rejected")
assert(not vim.bo.modified, "rejected output edits marked the notebook dirty")
vim.cmd("write")
assert(vim.deep_equal(read(), original), "deleting output changed source or saved results")

vim.api.nvim_win_set_cursor(0, { output_row, 0 })
vim.cmd("NotebookCellNewAbove markdown")
local source = projection.source(buf)
assert(source[1]:find("[markdown]", 1, true), "cell insertion from output selected the wrong cell")
vim.cmd("NotebookCellDelete")
assert(vim.deep_equal(projection.source(buf), { "# %% [code] id=text", "print('saved')",
  "# %% [markdown] id=notes", "# # Notes", "# %% [code] id=image", "plot()" }))
vim.cmd("NotebookCellMove down")
assert(projection.source(buf)[1]:find("[markdown]", 1, true), "moving a cell included its display rows in source")
vim.cmd("NotebookCellMove up")
vim.cmd("write")
assert(vim.deep_equal(read(), original), "cell movement damaged metadata, images, or outputs")

vim.cmd("NotebookCellGoto 1")
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "print('changed')" })
vim.cmd("doautocmd TextChanged")
assert(not require("notebook_rs.inline").records[buf].text, "editing source kept stale interactive output")
vim.cmd("write")
local edited = read()
assert(edited.cells[1].source == "print('changed')\n" and #edited.cells[1].outputs == 0)
assert(vim.deep_equal(edited.cells[2], original.cells[2]) and vim.deep_equal(edited.cells[3], original.cells[3]),
  "editing source changed unrelated markdown, image, or metadata")
vim.fn.delete(path)
print("Output protection, media, metadata, cell editing, and stale output clearing passed")
