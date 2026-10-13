#!/usr/bin/env python3
"""Exercise real inline output navigation with an attached Neovim UI (pynvim)."""
import os, tempfile, time
from pathlib import Path
import pynvim
root = Path(os.environ.get('NOTEBOOK_RS_ROOT', Path(__file__).resolve().parent.parent))
os.environ.setdefault('NVIM_LOG_FILE', str(Path(tempfile.gettempdir()) / 'notebook-output-ui.log'))
config = os.environ.get('NOTEBOOK_RS_NVIM_CONFIG', 'NONE')
argv = ['nvim', '--embed', '-u', config, '-i', 'NONE']
if config == 'NONE': argv.append('--clean')
nvim=pynvim.attach('child',argv=argv)
def wait(check,message):
    until=time.monotonic()+10
    while time.monotonic()<until:
        if check():return
        time.sleep(.02)
    raise AssertionError(message)
def snap(name):
    nvim.command('redraw')
    screen=nvim.exec_lua('local lines={}; for r=1,32 do local s=""; for c=1,100 do s=s..vim.fn.screenstring(r,c) end; lines[#lines+1]=s end; return lines')
    folder = Path(os.environ.get('NOTEBOOK_RS_UI_OUTPUT', tempfile.mkdtemp(prefix='notebook-output-ui-')))
    folder.mkdir(parents=True, exist_ok=True)
    (folder / (name + '.txt')).write_text('\n'.join(screen))
    try:
        from PIL import Image, ImageDraw, ImageFont
        font_path = Path('/System/Library/Fonts/Menlo.ttc')
        font = ImageFont.truetype(str(font_path),14) if font_path.exists() else ImageFont.load_default()
        im=Image.new('RGB',(1020,660),'#111827');d=ImageDraw.Draw(im)
        for row,line in enumerate(screen):d.text((10,10+row*20),line,font=font,fill='#e5e7eb')
        im.save(folder / (name + '.png'))
    except ImportError:pass
try:
    nvim.ui_attach(100,32,rgb=True)
    nvim.exec_lua('vim.opt.rtp:append(...); vim.g.notebook_rs_bin=...; require("notebook_rs").setup({cells_output_interacteable=true,python_lsp={enabled=false}})',str(root),os.environ.get('NOTEBOOK_RS_BIN',str(root/'target/release/nvim-notebook-rs')))
    path=Path(tempfile.mkdtemp())/'output.ipynb'
    nvim.command('NotebookNew '+str(path))
    nvim.current.buffer[:]=['# %% [code] id=first',"for i in range(200): print('Output row', i)",'# %% [code] id=second','print("second")']
    nvim.current.window.cursor=(2,0)
    nvim.command('NotebookRun')
    wait(lambda:nvim.exec_lua('return require("notebook_rs.ui").results[vim.api.nvim_get_current_buf()].first~=nil'),'execution did not finish')
    nvim.input('jj')
    wait(lambda:'Output row 0' in nvim.current.line,'native j skipped output')
    nvim.input('wyiw')
    wait(lambda:nvim.funcs.getreg('"')=='Output','word yank copied hidden display markup')
    nvim.input('20j')
    wait(lambda:'Output row 20' in nvim.current.line,'native j skipped output')
    nvim.command('normal! zt')
    snap('inline-output-before-scroll')

    nvim.input('<C-f>')
    wait(lambda:nvim.current.window.cursor[0]>24,'page down did not move through output')
    assert nvim.current.window.cursor[0]<204
    page_top = nvim.exec_lua('return vim.fn.winsaveview().topline')
    nvim.input('<C-b>')

    wait(lambda:nvim.exec_lua('return vim.fn.winsaveview().topline')<page_top,'page up did not scroll the viewport')
    nvim.input('/Output row 90<CR>')
    wait(lambda:'Output row 90' in nvim.current.line,'search could not enter output')
    nvim.input('Vjjy')
    wait(lambda:'Output row 92' in nvim.funcs.getreg('"'),'visual yank failed')
    assert nvim.funcs.getreg('"')=='Output row 90\nOutput row 91\nOutput row 92\n'
    snap('inline-output-after-search')
    nvim.input(':NotebookCellGoto 2<CR>')
    wait(lambda:nvim.funcs.mode() == 'n' and nvim.current.line == 'print("second")','cell navigation did not finish')
    nvim.input('A # changed<Esc>')
    wait(lambda:nvim.funcs.mode() == 'n' and nvim.exec_lua('return require("notebook_rs.output").source(0)[4]') == 'print("second") # changed','source editing did not finish')
    nvim.input('u')
    wait(lambda:nvim.exec_lua('return require("notebook_rs.output").source(0)[4]')=='print("second")','undo did not restore source')
    nvim.input('<C-r>')
    wait(lambda:nvim.exec_lua('return require("notebook_rs.output").source(0)[4]')=='print("second") # changed','redo did not restore source')
    print('Native inline output j/k, paging, search, visual copy, source undo, and redo passed.')
finally:
    try:nvim.command('qa!')
    except (EOFError,OSError):pass
    nvim.close()
