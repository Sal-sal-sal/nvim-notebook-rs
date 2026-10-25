local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
vim.g.mapleader = ' '
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local path, journal, cli = directory .. '/test.ipynb', directory .. '/journal.json', directory .. '/colab'
vim.fn.writefile({ '#!/usr/bin/env python3', 'import os, runpy, sys, time',
  'from pathlib import Path', 'if "--file" in sys.argv:',
  '    if "journal_slow" in Path(sys.argv[sys.argv.index("--file") + 1]).read_text():',
  '        deadline = time.monotonic() + 15',
  '        while not Path(os.environ["JOURNAL_RELEASE"]).exists() and time.monotonic() < deadline: time.sleep(0.02)',
  'runpy.run_path(os.environ["FAKE_COLAB"], run_name="__main__")' }, cli)
vim.fn.setfperm(cli, 'rwx------')
vim.env.NVIM_NOTEBOOK_COLAB = cli
vim.env.NVIM_NOTEBOOK_COLAB_JOURNAL = journal
vim.env.NVIM_NOTEBOOK_COLAB_CA_BUNDLE = nil
vim.env.FAKE_COLAB = root .. '/tests/fake_colab.py'
vim.env.JOURNAL_RELEASE = directory .. '/release'
require('notebook_rs').setup({ python_lsp = { enabled = false } })
vim.cmd('NotebookNew ' .. vim.fn.fnameescape(path))
local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local client = require('notebook_rs.client')
local function snapshot() return client.once({ op = 'colab_journal' }) end
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end
local function visible() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
assert(#snapshot().entries == 0, 'local notebook creation polluted Colab history')
assert(vim.fn.maparg(' ccj', 'n', false, true).desc == 'Colab: Request journal')
press(' ccj')
assert(visible():find('No Colab requests recorded yet.', 1, true), 'empty journal is not readable')
press('q')
assert(vim.api.nvim_get_current_win() == win)
vim.cmd('NotebookColabConnect journal-test')
assert(vim.wait(5000, function() return require('notebook_rs.status').state == 'connected' end, 20))
vim.api.nvim_set_current_win(win)
local entry = snapshot().entries[1]
assert(entry.request.op == 'colab_connect' and entry.request.session == 'journal-test')
assert(entry.response.ok and entry.response.data.success and type(entry.duration_ms) == 'number')
require('notebook_rs.output').replace(buf, { '# %% [code] id=slow', 'journal_slow = 1' }, true)
local source = require('notebook_rs.output').source(buf)
vim.api.nvim_win_set_cursor(win, { 2, 0 })
vim.cmd('NotebookRun')
assert(vim.wait(3000, function()
  local entries = vim.json.decode(table.concat(vim.fn.readfile(journal), '\n'))
  return #entries == 2 and entries[2].response == vim.NIL
end, 20), 'running request was not recorded before Colab replied')
press(' ccj')
assert(visible():find('RUNNING', 1, true) and visible():find('journal_slow = 1', 1, true),
  'journal did not open while execution worker was busy')
assert(not vim.bo.modifiable and vim.bo.buftype == 'nofile' and not vim.bo.modified)
assert(vim.fn.foldclosed(5) == -1, 'latest request should start expanded')
press('<CR>')
assert(vim.fn.foldclosed(5) == 5, 'Enter did not fold the request')
press('<CR>')
vim.fn.writefile({ 'continue' }, vim.env.JOURNAL_RELEASE)
assert(vim.wait(5000, function() return require('notebook_rs.cells').states[buf].slow == 'ok' end, 20))
press('r')
assert(visible():find('OK', 1, true) and visible():find('remote:journal_slow = 1', 1, true),
  'refresh did not replace pending state with the actual return')
assert(not visible():find('RUNNING', 1, true))
local logbuf = vim.api.nvim_get_current_buf()
press('q')
assert(vim.deep_equal(require('notebook_rs.output').source(buf), source), 'viewing journal changed notebook source')
local failed
client.request({ op = 'colab_connect', session = 'bad session' }, function(response) failed = response end)
assert(vim.wait(3000, function() return failed ~= nil end, 20))
assert(not failed.ok)
vim.cmd('NotebookColabJournal')
assert(vim.api.nvim_get_current_buf() == logbuf, 'reopening duplicated the journal buffer')
assert(visible():find('ERROR', 1, true) and visible():find('session name may contain only', 1, true))
local before = #snapshot().entries
press('r')
assert(#snapshot().entries == before, 'reading the journal generated Colab requests')
press('q')
require('notebook_rs.output').replace(buf, { '# %% [code] id=error', 'raise ValueError("bad cell")' }, true)
vim.api.nvim_win_set_cursor(win, { 2, 0 })
vim.cmd('NotebookRun')
assert(vim.wait(5000, function() return require('notebook_rs.cells').states[buf].error == 'error' end, 20))
vim.cmd('NotebookColabJournal')
assert(visible():find('ERROR', 1, true) and visible():find('ValueError: bad cell', 1, true),
  'a Python exception with CLI exit zero was reported as success')
press('q')
local format = require('notebook_rs.journal.format')
local sample = { path = journal, entries = { { id = 1, started_at_ms = 1, duration_ms = 1,
  request = { op = 'run' }, response = { ok = true, data = { outputs = {
    { data = { ['image/png'] = 'BASE64_IMAGE_BYTES', ['text/plain'] = 'figure' } },
  } } } } } }
local rendered = table.concat(format.render(sample), '\n')
assert(rendered:find('image: 18 base64 characters', 1, true) and not rendered:find('BASE64_IMAGE_BYTES', 1, true))
sample.entries[1].response, sample.entries[1].worker_pid = vim.NIL, 2147483647
assert(table.concat(format.render(sample), '\n'):find('INTERRUPTED', 1, true), 'dead worker still appears running')
vim.cmd('enew!')
assert(vim.tbl_isempty(vim.fn.maparg(' ccj', 'n', false, true)), 'shortcut leaked into plain buffers')
vim.api.nvim_buf_delete(logbuf, { force = true })
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(directory, 'rf')
print('Colab journal key, pending requests, returns, errors, persistence, folding, refresh, and source safety passed')
