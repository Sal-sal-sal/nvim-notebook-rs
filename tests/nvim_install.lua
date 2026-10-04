local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:prepend(root)
vim.g.notebook_rs_bin = nil
vim.cmd("runtime plugin/notebook_rs.lua")
assert(vim.fn.exists(":NotebookOpen") == 2, "plugin did not register commands")
assert(require("notebook_rs.client").binary() == assert(vim.env.NOTEBOOK_RS_BIN),
  "plugin did not discover the compiled release worker")

local docs = vim.fn.tempname()
vim.fn.mkdir(docs .. "/doc", "p")
for _, file in ipairs(vim.fn.glob(root .. "/doc/*.txt", false, true)) do
  vim.fn.writefile(vim.fn.readfile(file), docs .. "/doc/" .. vim.fn.fnamemodify(file, ":t"))
end
vim.cmd("helptags " .. vim.fn.fnameescape(docs .. "/doc"))
vim.opt.rtp:append(docs)
for _, tag in ipairs({ "nvim-notebook-rs", "notebook-rs-install", "notebook-rs-commands",
  "notebook-rs-options", "notebook-rs-keys", "notebook-rs-colab" }) do
  vim.cmd("help " .. tag)
end
vim.cmd("only")

local example = root .. "/examples/local.ipynb"
local original = vim.fn.readfile(example)
local path = vim.fn.tempname() .. ".ipynb"
vim.fn.writefile(original, path)
vim.cmd("edit " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.cmd("NotebookRunAll")
assert(vim.wait(5000, function()
  return require("notebook_rs.ui").results[buf]["local-result"] ~= nil
end, 20), "example did not finish")
vim.cmd("write")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(saved.cells[3].outputs[1].text == "12\n")
assert(saved.cells[2].execution_count == vim.NIL and saved.cells[3].execution_count == vim.NIL)
assert(vim.deep_equal(original, vim.fn.readfile(example)), "example source was modified")
vim.fn.delete(path)
vim.fn.delete(docs, "rf")
print("Plugin autoload, binary discovery, help tags, and local example passed")
