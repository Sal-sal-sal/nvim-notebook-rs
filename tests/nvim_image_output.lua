local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
vim.env.NVIM_NOTEBOOK_COLAB = root .. "/tests/fake_colab.py"
vim.env.NVIM_NOTEBOOK_COLAB_CA_BUNDLE = nil
require("notebook_rs").setup({ cells_output_interacteable = true, python_lsp = { enabled = false } })
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.cmd("NotebookColabConnect images")
assert(vim.wait(5000, function() return require("notebook_rs.status").state == "connected" end, 20))
for _, name in ipairs({ "wrapped", "array" }) do
  require("notebook_rs.output").replace(buf, { "# %% [code] id=" .. name, "plot_" .. name .. "()" }, true)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("NotebookRun")
  assert(vim.wait(5000, function()
    local state = require("notebook_rs.cells").states[buf]
    return state and (state[name] == "ok" or state[name] == "error")
  end, 20))
  assert(require("notebook_rs.cells").states[buf][name] == "ok", "image " .. name .. " failed to render")
  local artifact = assert(require("notebook_rs.ui").artifacts[1], "decoded image artifact missing")
  local image = assert(io.open(artifact, "rb")); local bytes = image:read("*a"); image:close()
  assert(bytes:sub(1, 8) == "\137PNG\r\n\26\n" and #bytes > 60, "image bytes were damaged")
  vim.cmd("write")
  local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  local encoded = saved.cells[1].outputs[1].data["image/png"]
  assert(name == "wrapped" and type(encoded) == "string" and encoded:find("\n", 1, true)
    or name == "array" and type(encoded) == "table", "saved MIME data was modified")
end
local notice
local notify = vim.notify
vim.notify = function(message) notice = tostring(message) end
require("notebook_rs.output").replace(buf, { "# %% [code] id=invalid", "plot_invalid()" }, true)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookRun")
assert(vim.wait(5000, function() return notice and notice:find("decoding image/png", 1, true) end, 20),
  "invalid image characters were silently accepted")
assert(not require("notebook_rs.ui").results[buf].invalid)
vim.notify = notify
vim.fn.delete(path)
print("Multiline and array image output rendered and saved intact")
