local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
local sent, placed, cleared = {}, {}, 0
package.loaded['image/backends/kitty/helpers'] = {
  write_graphics = function(opts, path) sent[#sent + 1] = { opts = opts, path = path } end,
  write_graphics_at = function(opts, x, y) placed[#placed + 1] = { opts = opts, x = x, y = y } end,
}
package.loaded['image/utils/term'] = {
  get_size = function() return { cell_width = 16, cell_height = 30 } end,
  get_tty = function() return '/dev/null' end,
}
local state = { options = { backend = 'kitty' }, images = {},
  backend = { clear = function() cleared = cleared + 1 end } }
local image = { global_state = state, id = 'chart', internal_id = 42,
  cropped_path = '/tmp/chart.png', bounds = { left = 6, top = 2, right = 50, bottom = 25 } }
require('notebook_rs.charts.kitty').attach(image)
local backend = image.global_state.backend
assert(backend ~= state.backend and backend.features.crop, 'adapter changed global image.nvim backend')
backend.render(image, 6, 4, 40, 16)
local first = placed[1]
assert(first.opts.display_columns == 40 and first.opts.display_rows == 16,
  'Retina placement omitted explicit terminal cell dimensions')
assert(first.opts.display_width == 640 and first.opts.display_height == 480)
assert(first.opts.display_cursor_policy == 1 and first.x == 7 and first.y == 5)
backend.render(image, 6, -4, 40, 16)
local clipped = placed[2]
assert(clipped.y == 3 and clipped.opts.display_y == 180 and clipped.opts.display_rows == 10,
  'top clipping shifted or stretched chart')
backend.render(image, 42, 20, 40, 16)
local bottom = placed[3].opts
assert(bottom.display_columns == 8 and bottom.display_rows == 6, 'image escaped right/bottom window bounds')
assert(#sent == 1, 'scrolling retransmitted unchanged image bytes')
assert(image.is_rendered and state.images.chart == image)
backend.clear(image.id, false)
assert(cleared == 1)
backend.render(image, 6, 4, 40, 16)
assert(#sent == 2, 'cleared graphics data was not transmitted again')
image.cropped_path = '/tmp/resized-chart.png'
backend.render(image, 6, 4, 40, 16)
assert(#sent == 3 and sent[3].path == image.cropped_path)
print('Kitty Retina scaling, clipping, cursor policy, transmission cache, and backend isolation passed')
