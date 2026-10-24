vim.opt.rtp:append(assert(vim.env.NOTEBOOK_RS_ROOT))
vim.g.notebook_rs_bin=assert(vim.env.NOTEBOOK_RS_BIN)
package.loaded.image={from_file=function(path,opts)
  return {original_path=path,buffer=opts.buffer,window=opts.window,render=function()end,clear=function()end}
end}
vim.api.nvim_list_uis=function()return {{}}end
require('notebook_rs').setup({cells_output_interacteable=true,python_lsp={enabled=false}})
local repr={}
for i=1,100 do repr[#repr+1]='<matplotlib.lines.Line2D at 0x'..string.format('%x',i)..'>' end
local png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUA'..
  'AaX2RUAAAAAASUVORK5CYII='
local original={nbformat=4,nbformat_minor=5,metadata={keep=true},cells={{cell_type='code',id='plot',
  source='plt.plot(res)\n',metadata={keep='plot'},execution_count=2,outputs={
    {output_type='execute_result',execution_count=2,metadata={},data={['text/plain']='['..table.concat(repr,',\n')..']'}},
    {output_type='display_data',metadata={},data={['image/png']=png,['text/plain']='<Figure>'}},
  }}}}
local path=vim.fn.tempname()..'.ipynb'
vim.fn.writefile({vim.json.encode(original)},path)
vim.cmd('edit '..vim.fn.fnameescape(path))
local buf=vim.api.nvim_get_current_buf()
local charts=require('notebook_rs.charts')
local function slot()return assert(charts.slots[buf][1],'chart disappeared')end
assert(slot().row==1 and slot().offset==1,'100 Line2D results pushed the chart away from its source')
local text_rows=0
for _,row in ipairs(require('notebook_rs.output').states[buf].rows) do
  if row.output then text_rows=text_rows+1 end
end
assert(text_rows==101,'prioritizing the chart removed or collapsed textual results')
local ns=vim.api.nvim_get_namespaces().notebook_rs_cells
local function marks()return vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{details=true})end
assert(#marks()==3,'image and bottom border must use separate anchors')
vim.cmd('write')
assert(vim.deep_equal(original,vim.json.decode(table.concat(vim.fn.readfile(path),'\n'))),
  'chart positioning rewrote notebook output or metadata')
require('notebook_rs').setup({image_output_position='after_text'})
assert(slot().row==102 and #marks()==2,'after_text did not restore the original placement')
require('notebook_rs').setup({cells_output_interacteable=false,image_output_position='before_text'})
assert(slot().row==1 and slot().offset==1,'virtual text still precedes the chart')
require('notebook_rs').setup({image_output_position='after_text'})
assert(slot().offset>100,'virtual after_text ignored the full result')
for _=1,3 do
 require('notebook_rs').setup({cells_output_interacteable=true,image_output_position='before_text'})
 assert(slot().row==1 and #marks()==3,'redrawing accumulated borders or misplaced the chart')
end
assert(not pcall(require('notebook_rs').setup,{image_output_position='middle'}))
require('notebook_rs.inline').records[buf].plot.outputs={
 {output_type='stream',name='stdout',text='hello\n'},
 {output_type='display_data',data={['text/html']=true}},
}
require('notebook_rs.cells').render(buf)
assert(#marks()==2 and marks()[2][2]==3,'image positioning changed the HTML-only layout')
assert(not vim.bo.modified,'view settings marked the notebook modified')
vim.cmd('bwipeout!')
vim.fn.delete(path)
print('Charts precede long results in both text modes; original results, metadata, borders, and fallback order remain intact')
