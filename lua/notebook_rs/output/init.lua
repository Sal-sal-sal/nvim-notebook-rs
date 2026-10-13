local layout = require("notebook_rs.output.layout")
local buffer = require("notebook_rs.output.buffer")
local changes = require("notebook_rs.output.changes")
local M = { states = {} }
local attached = {}

local function ensure(buf)
  if M.states[buf] then return M.states[buf] end
  local source = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local state = { source = source, rows = layout.build(source, {}, "", false), records = {},
    prefix = ("# [notebook-rs-output:%x] "):format(vim.uv.hrtime()), modified = vim.bo[buf].modified }
  M.states[buf] = state
  if not attached[buf] then
    attached[buf] = true
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first, last, new_last)
        local current = M.states[buf]
        if not current or current.busy then return end
        changes.record(buf, current, first, last, new_last)
        if current.pending then return end
        current.pending = true
        vim.schedule(function()
          if M.states[buf] ~= current or not vim.api.nvim_buf_is_valid(buf) then return end
          current.pending = false
          local cells = require("notebook_rs.cells")
          if M.changed(buf) then cells.reset(buf) else cells.render(buf) end
          require("notebook_rs.navigation").refresh(buf)
        end)
      end,
      on_detach = function() M.states[buf], attached[buf] = nil, nil end,
    })
    vim.api.nvim_create_autocmd("TextYankPost", {
      buffer = buf,
      callback = function()
        local current = M.states[buf]
        if current then changes.yank(buf, current) end
      end,
    })
  end
  return state
end

function M.sync(buf, records)
  local state = ensure(buf)
  state.records = records
  local config = require("notebook_rs.config")
  local enabled = config.cells_output_interacteable and config.nootbook_result == "nootbook"
  buffer.apply(buf, state, layout.build(state.source, records, state.prefix, enabled))
end

function M.source(buf)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  return vim.deepcopy(M.states[buf] and M.states[buf].source or vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

function M.source_row(buf, row)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  return M.states[buf] and layout.source_row(M.states[buf].rows, row) or row
end

function M.display_row(buf, row)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  return M.states[buf] and layout.display_row(M.states[buf].rows, row) or row
end

function M.replace(buf, source, modified)
  local state = ensure(buf)
  state.source, state.modified, state.changed = source, modified or false, false
  buffer.apply(buf, state, layout.build(source, {}, state.prefix, false))
end

function M.modified(buf, value)
  if M.states[buf] then M.states[buf].modified = value end
end

function M.changed(buf)
  local state = M.states[buf]
  if not state then return true end
  local changed = state.changed
  state.changed = false
  return changed
end

function M.cursor(buf)
  local state = M.states[buf]
  if not state then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = state.rows[cursor[1]]
  if row and row.output and cursor[2] < #state.prefix then
    vim.api.nvim_win_set_cursor(0, { cursor[1], #state.prefix })
  end
end

function M.release(buf)
  M.states[buf] = nil
end

return M
