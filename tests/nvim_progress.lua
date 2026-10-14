local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local plugin = require("notebook_rs")
plugin.setup({ cells_output_interacteable = true, python_lsp = { enabled = false } })
local path = vim.fn.tempname() .. ".ipynb"
local outputs = {}
for _, size in ipairs({ "9.91M", "28.9k", "1.65M", "4.54k" }) do
  for _, percent in ipairs({ 0, 2, 7, 27, 74, 100 }) do
    outputs[#outputs + 1] = { output_type = "stream", name = "stderr",
      text = { ("\r%3d%%|████| %s"):format(percent, size) } }
  end
  outputs[#outputs + 1] = { output_type = "stream", name = "stderr", text = "\n" }
end
outputs[#outputs + 1] = { output_type = "execute_result", execution_count = 7, metadata = {},
  data = { ["text/plain"] = "Dataset MNIST\n    Number of datapoints: 60000\n    Split: Train" } }
local original = { nbformat = 4, nbformat_minor = 5, metadata = { keep = "metadata" }, cells = {
  { cell_type = "code", id = "progress", metadata = { keep = "cell" }, source = "download_data()\n",
    execution_count = 7, outputs = outputs },
} }
vim.fn.writefile({ vim.json.encode(original) }, path)
vim.cmd("NotebookOpen " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local function shown()
  local lines = {}
  for _, row in ipairs(require("notebook_rs.output").states[buf].rows) do
    if row.output then lines[#lines + 1] = row.text:sub(#require("notebook_rs.output").states[buf].prefix + 1) end
  end
  return lines
end
local expected = { "├─ OUTPUT ─", "│ 100%|████| 9.91M", "│ 100%|████| 28.9k", "│ 100%|████| 1.65M",
  "│ 100%|████| 4.54k", "├─ RESULT ─", "│ Dataset MNIST", "│     Number of datapoints: 60000", "│     Split: Train" }
assert(vim.deep_equal(shown(), expected), "fragmented download progress is duplicated or has raw controls")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("normal! yy")
assert(vim.fn.getreg('"') == "100%|████| 9.91M\n", "progress yank includes internal prefixes or controls")
vim.cmd("write")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(vim.deep_equal(saved, original), "rendering or saving rewrote notebook stream chunks")
vim.cmd("edit!")
assert(vim.deep_equal(shown(), expected), "progress changed after reopening")
plugin.setup({ cells_output_interacteable = false })
local virtual = {}
local ns = vim.api.nvim_get_namespaces().notebook_rs_cells
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
  for _, row in ipairs(mark[4].virt_lines or {}) do
    if row[1][1]:sub(1, #"├─") == "├─" or row[1][1]:sub(1, #"│") == "│" then virtual[#virtual + 1] = row[1][1] end
  end
end
assert(vim.deep_equal(virtual, expected), "virtual output handles progress differently")

local local_path = vim.fn.tempname() .. ".ipynb"
plugin.setup({ cells_output_interacteable = true })
vim.cmd("NotebookNew " .. vim.fn.fnameescape(local_path))
local run_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(run_buf, 0, -1, false, {
  "# %% [code] id=live-progress", "import sys", "for size in (3, 11, 101):",
  "    for percent in (0, 50, 100):", "        sys.stderr.write(f'\\r{percent:3}%|{size}')",
  "    sys.stderr.write('\\n')", "print('Dataset ready')",
})
vim.cmd("NotebookRun")
local function complete()
  return require("notebook_rs.cells").states[run_buf]["live-progress"] == "ok"
end
assert(vim.wait(5000, complete, 20), "real Python progress execution failed")
local raw = require("notebook_rs.ui").results[run_buf]["live-progress"].outputs[1].text
assert(raw:find("\r", 1, true), "execution lost original carriage return data")
plugin.setup({ nootbook_result = "window" })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function()
  local win = require("notebook_rs.panel").win
  return win and vim.api.nvim_win_is_valid(win)
end, 20), "window output was not opened")
local panel = require("notebook_rs.panel")
local panel_text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(panel.win), 0, -1, false), "\n")
assert(panel_text == "100%|3\n100%|11\n100%|101\nDataset ready\n", "output panel duplicated progress frames")
for _, file in ipairs({ path, local_path }) do vim.fn.delete(file) end
print("Neovim saved progress, virtual output, real Python, yank, and output panel passed")
