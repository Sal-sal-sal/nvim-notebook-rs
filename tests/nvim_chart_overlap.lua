local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--clean', '-u', 'NONE' }, { rpc = true })
assert(child > 0)
local function lua(code, args) return vim.rpcrequest(child, 'nvim_exec_lua', code, args or {}) end
vim.rpcrequest(child, 'nvim_ui_attach', 80, 30, { ext_linegrid = false })
lua([[
  local root, bin = ...
  vim.opt.rtp:append(root)
  vim.g.notebook_rs_bin = bin
  vim.o.laststatus = 0
  vim.o.cmdheight = 0
  _G.placements, _G.clears = 0, 0
  package.loaded.image = { from_file = function(path, opts)
    local image = { original_path = path, window = opts.window, buffer = opts.buffer,
      global_state = { options = { backend = 'test' }, backend = {
        render = function(current) placements = placements + 1; current.is_rendered = true end,
      } }, bounds = { left = 0, top = 0, right = 80, bottom = 29 } }
    function image:clear() self.is_rendered = false; self.rendered_geometry = {}; clears = clears + 1 end
    function image:render()
      if self.is_rendered then return end -- model image.nvim's unchanged-geometry cache
      self.global_state.backend.render(self, 2, 2, 20, 10)
      self.rendered_geometry = { x = 2, y = 2, width = 20, height = 10 }
    end
    _G.chart = image
    return image
  end }
  require('notebook_rs').setup({ python_lsp = { enabled = false } })
  _G.path = vim.fn.tempname() .. '.ipynb'
  vim.cmd('NotebookNew ' .. vim.fn.fnameescape(path))
  _G.buf = vim.api.nvim_get_current_buf()
  require('notebook_rs.output').replace(buf, { '# %% [code] id=plot', 'plt.show()' })
  require('notebook_rs.inline').attach(buf, { { id = 'plot', source = 'plt.show()\n', outputs = {
    { output_type = 'display_data', data = { ['image/png'] =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUA' ..
      'AaX2RUAAAAAASUVORK5CYII=' } },
  } } })
  require('notebook_rs.cells').render(buf)
  function _G.popup(row, col)
    local ei = vim.o.eventignore
    vim.o.eventignore = 'all'
    local b = vim.api.nvim_create_buf(false, true)
    local w = vim.api.nvim_open_win(b, false, { relative = 'editor', row = row, col = col,
      width = 10, height = 3, border = 'single', focusable = false, noautocmd = true, zindex = 1000 })
    vim.o.eventignore = ei
    return w
  end
]], { assert(vim.env.NOTEBOOK_RS_ROOT), assert(vim.env.NOTEBOOK_RS_BIN) })
local function wait(code, message)
  assert(vim.wait(3000, function() return lua(code) end, 20), message)
end
wait('return chart and chart.is_rendered', 'notebook chart did not render with an attached UI')
local initial = lua('return placements')
lua('_G.float = popup(2, 2)')
wait('return not chart.is_rendered', 'event-suppressed popup failed to hide the overlapping image')
assert(lua('return clears') > 0 and lua('return placements') == initial, 'hidden image was repeatedly painted')
lua('chart:render()')
assert(not lua('return chart.is_rendered'), 'image.nvim redraw painted over the popup')
lua('vim.api.nvim_win_set_config(float, { relative = "editor", row = 20, col = 40 })')
wait('return chart.is_rendered', 'moving the popup away did not restore the chart')
local placed = lua('return placements')
lua('vim.api.nvim_win_set_config(float, { relative = "editor", row = 2, col = 21 })')
wait('return not chart.is_rendered', 'popup border was excluded from overlap detection')
lua('vim.o.eventignore = "all"; vim.api.nvim_win_close(float, true); vim.o.eventignore = ""')
wait('return chart.is_rendered', 'event-suppressed popup close did not restore the chart')
assert(lua('return placements') > placed)
lua('_G.float = popup(20, 40)')
assert(lua('return not require("notebook_rs.charts.overlap").covered(chart, 2, 2, 20, 10)'),
  'non-overlapping float masked the image')
lua('vim.api.nvim_win_close(float, true); vim.cmd("vsplit")')
wait('return chart.is_rendered', 'ordinary split hid notebook images')
for _ = 1, 3 do
  lua('_G.float = popup(3, 3)')
  wait('return not chart.is_rendered', 'repeated popup opening failed')
  lua('vim.api.nvim_win_close(float, true)')
  wait('return chart.is_rendered', 'repeated popup closing failed')
end
lua([[
  local overlap = require('notebook_rs.charts.overlap')
  local visible, position = vim.fn.pumvisible, vim.fn.pum_getpos
  vim.fn.pumvisible = function() return 1 end
  vim.fn.pum_getpos = function() return { row = 3, col = 3, width = 10, height = 3, scrollbar = false } end
  assert(overlap.covered(chart, 2, 2, 20, 10), 'completion menu did not mask image')
  vim.fn.pumvisible, vim.fn.pum_getpos = visible, position
  vim.cmd('bwipeout!')
  vim.fn.delete(path)
]])
vim.fn.jobstop(child)
print('Attached-UI popup occlusion, borders, suppressed events, restoration, splits, and completion passed')
