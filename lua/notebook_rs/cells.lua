local M = { states = {} }
local inline = require("notebook_rs.inline")
local config = require("notebook_rs.config")
local borders = vim.api.nvim_create_namespace("notebook_rs_cells")
local focus = vim.api.nvim_create_namespace("notebook_rs_focus")
local markers = vim.api.nvim_create_namespace("notebook_rs_markers")

local colors = {
  code = "NotebookRsCode",
  markdown = "NotebookRsMarkdown",
  raw = "NotebookRsRaw",
}

local function close_cell(buf, row, kind, id, lines, first)
  local virtual = kind == "code" and inline.virtual_lines(buf, id, lines, first, row + 1) or {}
  virtual[#virtual + 1] = { { "╰" .. string.rep("─", 55), colors[kind] } }
  vim.api.nvim_buf_set_extmark(buf, borders, row, 0, {
    virt_lines = virtual,
    priority = 40,
  })
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

for kind, target in pairs({ code = "DiagnosticInfo", markdown = "DiagnosticHint", raw = "DiagnosticWarn" }) do
  vim.api.nvim_set_hl(0, colors[kind], { link = target, default = true })
end
vim.api.nvim_set_hl(0, "NotebookRsActiveCell", { link = "CursorLine", default = true })
vim.api.nvim_set_hl(0, "NotebookRsRunning", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "NotebookRsFailed", { link = "DiagnosticError", default = true })

function M.render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, borders, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, markers, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local count = 0
  local previous_kind
  local previous_id
  local previous_row
  for row, line in ipairs(lines) do
    local kind, id = line:match("^# %%%% %[(%a+)%] id=(%S+)$")
    if colors[kind] then
      if previous_kind then
        close_cell(buf, row - 2, previous_kind, previous_id, lines, previous_row + 1)
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
      vim.api.nvim_buf_set_extmark(buf, borders, whole and row or row - 1, 0, {
        virt_lines = virtual,
        virt_lines_above = true,
        line_hl_group = color,
        sign_text = "▌",
        sign_hl_group = color,
        priority = 40,
      })
      marker_visibility(buf, row, line, whole)
    elseif line:match("^# %%%% %[") then
      vim.api.nvim_buf_set_extmark(buf, borders, row - 1, 0, {
        virt_lines = { { { "INVALID CELL MARKER: expected id=...", "NotebookRsFailed" } } },
        virt_lines_above = true,
      })
    end
  end
  if previous_kind then
    close_cell(buf, #lines - 1, previous_kind, previous_id, lines, previous_row + 1)
  end
  M.focus(buf)
end

function M.begin(buf, lines, cursor, all)
  local states = M.states[buf] or {}
  M.states[buf] = states
  local selected
  for row, line in ipairs(lines) do
    local kind, id = line:match("^# %%%% %[(%a+)%] id=(%S+)$")
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
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, focus, 0, -1)
  if vim.api.nvim_get_current_buf() ~= buf then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for row = math.min(#lines, cursor), 1, -1 do
    local kind = lines[row]:match("^# %%%% %[(%a+)%] id=%S+$")
    if colors[kind] then
      local anchor = hidden_whole(lines, row) and row or row - 1
      vim.api.nvim_buf_set_extmark(buf, focus, anchor, 0, {
        line_hl_group = "NotebookRsActiveCell",
        sign_text = "▶",
        sign_hl_group = colors[kind],
        priority = 60,
      })
      return
    end
  end
end

return M
