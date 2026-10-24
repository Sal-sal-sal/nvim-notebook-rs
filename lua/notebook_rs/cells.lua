local M = { states = {} }
local marker = require("notebook_rs.markers")
local inline = require("notebook_rs.inline")
local charts = require("notebook_rs.charts")
local config = require("notebook_rs.config")
local borders = vim.api.nvim_create_namespace("notebook_rs_cells")
local focus = require("notebook_rs.cells.focus")
local frames = {}
local markers = vim.api.nvim_create_namespace("notebook_rs_markers")

local colors = require("notebook_rs.cells.colors")

local function close_cell(buf, row, kind, id, lines, first)
  local anchor = inline.anchor(buf, row, id)
  local virtual = kind == "code" and inline.virtual_lines(buf, id, lines, first, row + 1, anchor) or {}
  if anchor ~= row and #virtual > 0 then
    vim.api.nvim_buf_set_extmark(buf, borders, anchor, 0, { virt_lines = virtual, priority = 40 })
    virtual = {}
  end
  virtual[#virtual + 1] = { { "╰" .. string.rep("─", 55), colors[kind] } }
  local opts = { virt_lines = virtual, priority = 40 }
  return { row = row, opts = opts, color = colors[kind],
    id = vim.api.nvim_buf_set_extmark(buf, borders, row, 0, opts) }
end

local function hidden_whole(lines, row)
  return config.nootbook_hidden_id_line and vim.fn.has("nvim-0.11") == 1
    and row < #lines and not lines[row + 1]:match("^# %%%% %[")
end

local function marker_visibility(buf, row, line, whole)
  if not config.nootbook_hidden_id_line then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_get_option_value("conceallevel", { win = win }) < 2 then
      vim.api.nvim_set_option_value("conceallevel", 2, { win = win })
    end
    vim.api.nvim_set_option_value("concealcursor", "nivc", { win = win })
  end
  local opts = whole
    and { end_row = row - 1, end_col = #line, conceal_lines = "" }
    or { end_col = #line, conceal = "" }
  vim.api.nvim_buf_set_extmark(buf, markers, row - 1, 0, opts)
end

vim.api.nvim_create_autocmd("BufWipeout", {
  group = vim.api.nvim_create_augroup("NotebookRsCellFrames", { clear = true }),
  callback = function(args)
    frames[args.buf], M.states[args.buf] = nil, nil
    focus.reset(args.buf)
  end,
})

function M.render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  require("notebook_rs.output").sync(buf, inline.records[buf] or {})
  charts.begin(buf)
  focus.reset(buf)
  frames[buf] = {}
  vim.api.nvim_buf_clear_namespace(buf, borders, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, markers, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local count = 0
  local previous_kind
  local previous_id
  local previous_row
  for row, line in ipairs(lines) do
    local kind, id = marker.parse(line)
    if colors[kind] then
      if previous_kind then
        local frame = frames[buf][#frames[buf]]
        frame.last = row - 1
        frame.bottom = close_cell(buf, row - 2, previous_kind, previous_id, lines, previous_row + 1)
      end
      count = count + 1
      previous_kind = kind
      previous_id = id
      previous_row = row
      local state = id and M.states[buf] and M.states[buf][id]
      local label = ({ running = "RUNNING", ok = "DONE", error = "ERROR" })[state]
      local title = ("  %d  %s%s  "):format(count, kind:upper(), label and "  " .. label or "")
      local color = state == "error" and "NotebookRsFailed"
        or state == "running" and "NotebookRsRunning" or colors[kind]
      local rule = "╭─" .. title .. string.rep("─", math.max(4, 52 - vim.fn.strdisplaywidth(title)))
      local virtual = {}
      if count > 1 then
        for _ = 1, config.distance_between_cells do
          virtual[#virtual + 1] = { { " ", "Normal" } }
        end
      end
      virtual[#virtual + 1] = { { rule, color } }
      local whole = hidden_whole(lines, row)
      local anchor = whole and row or row - 1
      local opts = { virt_lines = virtual, virt_lines_above = true,
        sign_text = "▌", sign_hl_group = color, priority = 40 }
      frames[buf][#frames[buf] + 1] = { first = row,
        top = { row = anchor, opts = opts, color = color,
          id = vim.api.nvim_buf_set_extmark(buf, borders, anchor, 0, opts) } }
      marker_visibility(buf, row, line, whole)
    elseif line:match("^# %%%% %[") then
      vim.api.nvim_buf_set_extmark(buf, borders, row - 1, 0, {
        virt_lines = { { { "INVALID CELL MARKER: expected id=...", "NotebookRsFailed" } } },
        virt_lines_above = true,
      })
    end
  end
  if previous_kind then
    local frame = frames[buf][#frames[buf]]
    frame.last = #lines
    frame.bottom = close_cell(buf, #lines - 1, previous_kind, previous_id, lines, previous_row + 1)
  end
  M.focus(buf)
  charts.finish(buf)
end

function M.begin(buf, lines, cursor, all)
  local states = M.states[buf] or {}
  M.states[buf] = states
  local selected
  for row, line in ipairs(lines) do
    local kind, id = marker.parse(line)
    if kind then
      if all and kind == "code" then
        states[id] = "running"
      elseif row <= cursor then
        selected = kind == "code" and id or nil
      end
    end
  end
  if not all and selected then
    states[selected] = "running"
  end
  M.render(buf)
end

function M.finish(buf, results, success)
  local states = M.states[buf] or {}
  for id, state in pairs(states) do
    if state == "running" then
      states[id] = nil
    end
  end
  for index, result in ipairs(results) do
    states[result.id] = not success and index == #results and "error" or "ok"
  end
  M.states[buf] = states
  M.render(buf)
end

function M.reset(buf)
  M.states[buf] = nil
  M.render(buf)
end

function M.focus(buf)
  focus.update(buf, frames[buf] or {})
end

return M
