vim.opt.rtp:append(assert(vim.env.NOTEBOOK_RS_ROOT))
local geometry = require('notebook_rs.charts.geometry')
local originals = { screenpos = vim.fn.screenpos, view = vim.fn.winsaveview,
  call = vim.api.nvim_win_call, height = vim.api.nvim_win_text_height, lines = vim.api.nvim_buf_get_lines }
local view = { topline = 1, topfill = 0 }
local positions = {}
vim.fn.winsaveview = function() return view end
vim.api.nvim_win_call = function(_, callback) return callback() end
vim.api.nvim_win_text_height = function() return { fill = 19 } end
vim.api.nvim_buf_get_lines = function() return { string.rep('x', 529) } end
vim.fn.screenpos = function(_, row, col)
  return { row = positions[row .. ':' .. col] or 0 }
end
local slot = { row = 8, offset = 1 }
positions['9:1'], positions['9:529'] = 10, 13
local row, offset = geometry.anchor(1, 1000, slot)
assert(row == 8 and offset == 4, 'wrapped result text was covered by the chart')
view = { topline = 10, topfill = 12 }
positions = { ['10:1'] = 14 }
row, offset = geometry.anchor(1, 1000, slot)
assert(row == 9 and 14 + offset == -5, 'partial virtual scrolling shifted chart into bottom border')
local _, second = geometry.anchor(1, 1000, { row = 8, offset = 19 })
assert(second - offset == 18, 'multiple figures collapsed into one slot while scrolling')
positions = {}
row, offset = geometry.anchor(1, 1000, slot)
assert(row == 9 and 1 + offset == -5, 'large virtual output with offscreen following line shifted chart')
view = { topline = 12, topfill = 0 }
row, offset = geometry.anchor(1, 1000, slot)
assert(row == 8 and offset == 1, 'fully offscreen chart was incorrectly attached to viewport')
vim.fn.screenpos, vim.fn.winsaveview = originals.screenpos, originals.view
vim.api.nvim_win_call, vim.api.nvim_win_text_height = originals.call, originals.height
vim.api.nvim_buf_get_lines = originals.lines
print('Chart anchors preserve wrapped text, partial virtual scrolling, and separate image slots')
