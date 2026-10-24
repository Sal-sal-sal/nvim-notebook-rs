vim.opt.rtp:append(assert(vim.env.NOTEBOOK_RS_ROOT))
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
package.loaded.image = { from_file = function(path, opts)
  return { original_path = path, buffer = opts.buffer, render = function() end, clear = function() end }
end }
vim.api.nvim_list_uis = function() return { {} } end
local plugin = require('notebook_rs')
plugin.setup({ cells_output_interacteable = true, python_lsp = { enabled = false } })
local config = require('notebook_rs.config')
assert(config.notebook.output.head == 30, 'default head is not 30')
local function lines(first, last)
  local result = {}
  for i = first, last do result[#result + 1] = ('line %02d\n'):format(i) end
  return table.concat(result)
end
local png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUA' ..
  'AaX2RUAAAAAASUVORK5CYII='
local original = { nbformat = 4, nbformat_minor = 5, metadata = { keep = true }, cells = {
  { cell_type = 'code', id = 'long', source = 'print("long")\n', metadata = { keep = 1 },
    execution_count = 2, outputs = {
      { output_type = 'stream', name = 'stdout', text = lines(1, 17) },
      { output_type = 'stream', name = 'stdout', text = { lines(18, 25) } },
      { output_type = 'stream', name = 'stderr', text = lines(26, 35) },
      { output_type = 'execute_result', execution_count = 2, metadata = {}, data = { ['text/plain'] = lines(36, 45) } },
      { output_type = 'error', ename = 'Error', evalue = 'oops', traceback = { lines(46, 50) } },
      { output_type = 'display_data', metadata = {}, data = { ['image/png'] = png, ['text/plain'] = '<Figure>' } },
    } },
  { cell_type = 'code', id = 'short', source = 'print("short")\n', metadata = {}, execution_count = 1,
    outputs = { { output_type = 'stream', name = 'stdout', text = lines(1, 3) } } },
} }
local path = vim.fn.tempname() .. '.ipynb'
vim.fn.writefile({ vim.json.encode(original) }, path)
vim.cmd('edit ' .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local output = require('notebook_rs.output')
local source = output.source(buf)
local function displayed(id)
  local result = {}
  for _, row in ipairs(output.states[buf].rows) do
    if row.output and row.id == id then result[#result + 1] = row.text:gsub('^.- │ ', '│ ') end
  end
  return table.concat(result, '\n')
end
local function check(limit, hidden)
  local text = displayed('long')
  local _, count = text:gsub('│ line %d+', '')
  assert(count == limit, 'limit was applied per output instead of per cell: ' .. count)
  assert(text:find('line 01', 1, true) and text:find(('line %02d'):format(limit), 1, true))
  if hidden > 0 then
    assert(text:find(hidden .. ' more lines (notebook.output.head)', 1, true), 'missing truncation count')
    assert(not text:find(('line %02d'):format(limit + 1), 1, true), 'tail leaked into output')
  else
    assert(not text:find('more lines', 1, true), 'unlimited output has a truncation notice')
  end
  assert(displayed('short'):find('line 03', 1, true), 'limit leaked between cells')
  assert(#require('notebook_rs.charts').slots[buf] == 1, 'text limit hid an image')
  assert(vim.deep_equal(output.source(buf), source), 'head setting changed source')
  assert(not vim.bo.modified, 'display settings marked the notebook modified')
  vim.cmd('write')
  assert(vim.deep_equal(original, vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))),
    'head setting discarded saved output, image bytes, or metadata')
end
check(30, 20)
for _, head in ipairs({ 5, false, 30 }) do
  plugin.setup({ notebook = { output = { head = head } } })
  check(head or 50, head and 50 - head or 0)
end
plugin.setup({ notebook = {} })
assert(config.notebook.output.head == 30, 'partial setup reset the head')
plugin.setup({ cells_output_interacteable = false })
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))
local virtual = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_get_namespaces().notebook_rs_cells,
  0, -1, { details = true })) do
  for _, row in ipairs(mark[4].virt_lines or {}) do
    for _, chunk in ipairs(row) do virtual[#virtual + 1] = chunk[1] end
  end
end
local rendered = table.concat(virtual, '\n')
assert(rendered:find('line 30', 1, true) and not rendered:find('line 31', 1, true), 'virtual head differs')
assert(rendered:find('20 more lines', 1, true), 'virtual truncation count differs')
local progress = require('notebook_rs.output.text').rows({
  { output_type = 'stream', name = 'stdout', text = '0%\r50%\r100%\nnext\nlast\n' },
})
assert(#progress == 4 and progress[2].text == '│ 100%', 'head broke progress normalization')
for _, head in ipairs({ 0, -1, 1.5, '30', true, {}, math.huge }) do
  assert(not pcall(plugin.setup, { notebook = { output = { head = head } } }), 'invalid head accepted')
  assert(config.notebook.output.head == 30, 'invalid head changed the setting')
end
assert(not pcall(plugin.setup, { notebook = false }))
assert(not pcall(plugin.setup, { notebook = { output = false } }))
vim.cmd('bwipeout!')
vim.fn.delete(path)
print('Per-cell output heads, both display modes, raw preservation, images, streams, and validation passed')
