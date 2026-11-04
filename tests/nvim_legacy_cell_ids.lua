vim.opt.rtp:append(assert(vim.env.NOTEBOOK_RS_ROOT))
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
require("notebook_rs").setup({ python_lsp = { enabled = false } })

local path = vim.fn.tempname() .. ".ipynb"
local function cell(id, label)
  return {
    cell_type = "code", id = id, metadata = { tag = label },
    source = "print('" .. label .. "')", execution_count = 2,
    outputs = { { output_type = "stream", name = "stdout", text = label .. "\n" } },
  }
end

local original = {
  nbformat = 4, nbformat_minor = 4, metadata = { project = "legacy" },
  cells = { cell(nil, "first"), cell(nil, "second"), cell("cell-1", "explicit") },
}
vim.fn.writefile({ vim.json.encode(original) }, path)
vim.cmd.edit(vim.fn.fnameescape(path))
vim.cmd.NotebookCellGoto("2")
vim.cmd.NotebookCellMove("up")
vim.cmd.write()

local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(saved.nbformat == 4 and saved.nbformat_minor == 5)
assert(vim.deep_equal(saved.metadata, original.metadata))
local ids = {}
for index, before in ipairs({ original.cells[2], original.cells[1], original.cells[3] }) do
  local after = saved.cells[index]
  assert(type(after.id) == "string" and not ids[after.id], "cell IDs must be unique")
  ids[after.id] = true
  local expected = vim.deepcopy(before)
  expected.id = before.id or after.id
  assert(vim.deep_equal(after, expected), "moving a legacy cell changed its data")
end
vim.cmd.bwipeout()
vim.cmd.edit(vim.fn.fnameescape(path))
vim.cmd.write()
assert(vim.deep_equal(saved, vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))),
  "legacy cell IDs changed after reopening")
vim.fn.delete(path)
print("Legacy cells preserve their identity, metadata, and results after moving and saving")
