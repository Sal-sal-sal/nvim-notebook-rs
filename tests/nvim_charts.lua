local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local shown, cleared = {}, 0
package.loaded.image = {
  is_enabled = function() return true end,
  from_file = function(path, opts)
    local image = { original_path = path, buffer = opts.buffer, window = opts.window }
    function image:render(geometry)
      self.geometry = geometry
      shown[opts.id] = self
    end
    function image:clear() shown[opts.id] = nil; cleared = cleared + 1 end
    return image
  end,
}
local list_uis = vim.api.nvim_list_uis
vim.api.nvim_list_uis = function() return { {} } end
require('notebook_rs').setup({ cells_output_interacteable = true, image_max_height = 12,
  python_lsp = { enabled = false } })
local path = vim.fn.tempname() .. '.ipynb'
vim.cmd('NotebookNew ' .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
require('notebook_rs.output').replace(buf, {
  '# %% [code] id=plot', 'import matplotlib.pyplot as plt', 'plt.plot(range(10))',
  '# %% [code] id=assigned', 'print("hello world")', 's = plt.plot([3, 1, 4])',
  '# %% [code] id=multiple', 'plt.figure()', 'plt.plot([2, 4])',
  'plt.figure()', 'plt.plot([4, 2])',
}, true)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('NotebookRunAll')
local ui = require('notebook_rs.ui')
assert(vim.wait(30000, function() return ui.results[buf].multiple ~= nil end, 20), 'plot execution timed out')
local charts = require('notebook_rs.charts')
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 4 end, 20), 'PNG outputs did not reach renderer')
assert(#charts.slots[buf] == 4, 'one or more generated figures were lost')
local a, b = charts.slots[buf][3], charts.slots[buf][4]
assert(a.row == b.row and a.offset + a.height < b.offset, 'multiple figures overlap')
for _, slot in ipairs(charts.slots[buf]) do
  local file = assert(io.open(slot.path, 'rb'))
  assert(file:read(8) == '\137PNG\r\n\26\n', 'renderer received damaged PNG')
  file:close()
end
vim.cmd('write')
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
assert(saved.cells[1].outputs[1].text:find('Line2D', 1, true), 'plot result text was discarded')
local encoded = saved.cells[1].outputs[2].data['image/png']
saved.cells[1].outputs[2].data['image/png'] = { encoded:sub(1, 100) .. '\n', encoded:sub(101) }
saved.cells[1].metadata.keep = 'image metadata'
vim.fn.writefile({ vim.json.encode(saved) }, path)
local old_paths = vim.tbl_map(function(slot) return slot.path end, charts.slots[buf])
vim.cmd('bwipeout!')
assert(vim.tbl_count(shown) == 0, 'closed notebook left graphics behind')
for _, file in ipairs(old_paths) do assert(not vim.uv.fs_stat(file), 'closed notebook leaked image cache') end
vim.cmd('edit ' .. vim.fn.fnameescape(path))
buf = vim.api.nvim_get_current_buf()
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 4 end, 20), 'saved figures were not restored')
assert(not vim.bo.modified, 'viewing images modified notebook')
vim.cmd('write')
assert(vim.deep_equal(saved, vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))),
  'opening/saving changed MIME data or metadata')
vim.cmd('vsplit')
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 8 end, 20), 'split lacks its own charts')
vim.cmd('close')
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 4 end, 20), 'closed split left graphics behind')
local opened
local open = vim.ui.open
vim.ui.open = function(file) opened = file end
vim.cmd('NotebookCellGoto 3')
vim.cmd('NotebookOpenChart 2')
assert(opened == charts.slots[buf][4].path, 'chart opener picked another cell or image')
vim.ui.open = open
require('notebook_rs').setup({ image_output = false })
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 0 end, 20), 'disabled images remained visible')
assert(#charts.slots[buf] == 0, 'disabled images kept blank padding')
require('notebook_rs').setup({ image_output = true })
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 4 end, 20))
vim.api.nvim_list_uis = function() return {} end
require('notebook_rs.cells').render(buf)
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 0 end, 20), 'headless rendering did not fall back')
assert(#charts.slots[buf] == 0, 'missing image renderer kept empty chart space')
vim.api.nvim_list_uis = function() return { {} } end
require('notebook_rs.cells').render(buf)
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 4 end, 20))
vim.cmd('NotebookCellGoto 1')
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'print("changed")' })
vim.cmd('doautocmd TextChanged')
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 3 end, 20), 'editing kept a stale chart')
assert(cleared > 0)
require('notebook_rs').setup({ image_output = false })
assert(vim.wait(3000, function() return vim.tbl_count(shown) == 0 end, 20))
package.loaded.image.from_file = function() error('image processor unavailable') end
require('notebook_rs').setup({ image_output = true })
assert(vim.wait(3000, function() return #charts.slots[buf] == 0 end, 20),
  'failed image processor left blank chart space or retried indefinitely')
assert(not pcall(require('notebook_rs').setup, { image_max_height = 0 }))
assert(not pcall(require('notebook_rs').setup, { image_output = 'yes' }))
vim.cmd('bwipeout!')
vim.fn.delete(path)
vim.api.nvim_list_uis = list_uis
print('Actual Matplotlib outputs, saved images, splits, cleanup, fallback, and chart selection passed')
