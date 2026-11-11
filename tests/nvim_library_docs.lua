local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local server = vim.fn.exepath('pyright-langserver')
if server == '' then server = vim.fn.stdpath('data') .. '/mason/bin/pyright-langserver' end
assert(vim.fn.executable(server) == 1, 'Pyright is required for documentation E2E')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local python = vim.env.NVIM_NOTEBOOK_PYTHON or vim.fn.exepath('python3')
local index = vim.fn.jobstart({ python, root .. '/tests/completion/server.py', directory })
assert(index > 0 and vim.wait(5000, function() return vim.fn.filereadable(directory .. '/port') == 1 end, 20))
vim.env.NVIM_NOTEBOOK_DOCS_INDEX = vim.fn.readfile(directory .. '/port')[1]
local plugin = require('notebook_rs')
plugin.setup({ python_lsp = { python_path = python, cmd = { server, '--stdio' },
  documentation = { cache = directory .. '/cache' } } })
local old = vim.deepcopy(require('notebook_rs.config').python_lsp.documentation)
assert(not pcall(plugin.setup, { python_lsp = { documentation = { max_download_mb = 0 } } }))
assert(vim.deep_equal(old, require('notebook_rs.config').python_lsp.documentation), 'bad setting changed active config')
local path = directory .. '/documentation.ipynb'
vim.cmd('NotebookNew ' .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '# %% [code] id=docs', 'from tiny_docs import pipeline', 'pipeline(',
})
local docs = require('notebook_rs.completion')
local profile = require('notebook_rs.completion.paths').request(buf, {}).profile
assert(vim.wait(20000, function()
  local data = docs.results[profile]
  return data and data.modules[1] and data.modules[1].status == 'cached'
end, 50), 'typing an import did not automatically fetch documentation')
assert(docs.results[profile].modules[1].downloaded, 'first fetch did not download a documentation wheel')
assert(vim.wait(20000, function()
  local clients = vim.lsp.get_clients({ bufnr = buf, name = 'pyright' })
  return #clients == 1 and clients[1].initialized
end, 50), 'Pyright did not attach')
local function request(method, line, character)
  return vim.lsp.buf_request_sync(buf, method, { textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = line, character = character } }, 5000) or {}
end
local signature
assert(vim.wait(15000, function()
  for _, reply in pairs(request('textDocument/signatureHelp', 2, 9)) do
    signature = reply.result and reply.result.signatures and reply.result.signatures[1]
    if signature and signature.label:find('model', 1, true) then return true end
  end
end, 100), 'downloaded interfaces did not provide pipeline parameter hints')
local documented = false
for _, reply in pairs(request('textDocument/hover', 1, 29)) do
  local contents = reply.result and reply.result.contents
  documented = documented or (contents and vim.inspect(contents):find('Build a documented pipeline', 1, true))
end
assert(documented, 'hover lost the upstream docstring')
vim.api.nvim_buf_set_lines(buf, 2, -1, false, { 'pipe = pipeline("text-generation")', 'pipe.' })
local generated = false
for _, reply in pairs(request('textDocument/completion', 3, 5)) do
  for _, item in ipairs(reply.result and (reply.result.items or reply.result) or {}) do
    generated = generated or item.label == 'generate'
  end
end
assert(generated, 'typed pipeline result did not expose its methods')
local not_installed = vim.system({ python, '-I', '-c',
  'import importlib.util; assert importlib.util.find_spec("tiny_docs") is None' }):wait()
assert(not_installed.code == 0, 'documentation setup installed the runtime library')
assert(vim.fn.glob(profile .. '/tiny_docs/*.py') == '', 'runtime implementation remained in documentation cache')
assert(vim.fn.glob(profile .. '/tiny_docs/*.safetensors') == '', 'model weights were extracted')
local before = #vim.json.decode(table.concat(vim.fn.readfile(directory .. '/requests.json'), '\n'))
docs.ensure(buf, false)
assert(#vim.json.decode(table.concat(vim.fn.readfile(directory .. '/requests.json'), '\n')) == before,
  'warm cache made another network request')
docs.results[profile] = nil
vim.cmd('NotebookLibraryDocs')
assert(vim.wait(10000, function() return docs.results[profile] ~= nil end, 50), 'manual refresh did not finish')
assert(#vim.json.decode(table.concat(vim.fn.readfile(directory .. '/requests.json'), '\n')) > before)
local config = { settings = { python = { analysis = { extraPaths = { '/custom/typing' } } } } }
require('notebook_rs.completion.paths').configure(config, buf)
assert(config.settings.python.analysis.extraPaths[1] == '/custom/typing', 'custom analysis paths were overwritten')
plugin.setup({ python_lsp = { documentation = { auto_download = false } } })
vim.api.nvim_buf_set_lines(buf, 1, -1, false, { 'import never_download_this' })
before = #vim.json.decode(table.concat(vim.fn.readfile(directory .. '/requests.json'), '\n'))
docs.ensure(buf, false)
assert(#vim.json.decode(table.concat(vim.fn.readfile(directory .. '/requests.json'), '\n')) == before)
vim.fn.jobstop(index)
vim.cmd('bwipeout!')
vim.fn.delete(directory, 'rf')
print('Automatic lightweight library docs: real Pyright signatures, hover, typed results, cache, and no runtime install passed')
