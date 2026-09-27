local M = { states = {}, distance_between_cells = 2 }
local borders = vim.api.nvim_create_namespace("notebook_rs_cells")
local focus = vim.api.nvim_create_namespace("notebook_rs_focus")

local colors = {
  code = "NotebookRsCode",
  markdown = "NotebookRsMarkdown",
  raw = "NotebookRsRaw",
}

local function close_cell(buf, row, kind)
  vim.api.nvim_buf_set_extmark(buf, borders, row, 0, {
    virt_lines = { { { "╰" .. string.rep("─", 55), colors[kind] } } },
    priority = 40,
  })
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
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local count = 0
  local previous_kind
  for row, line in ipairs(lines) do
    local kind = line:match("^# %%%% %[(%a+)%]")
    if colors[kind] then
      if previous_kind then
        close_cell(buf, row - 2, previous_kind)
      end
      count = count + 1
      previous_kind = kind
      local id = line:match(" id=(%S+)")
      local state = id and M.states[buf] and M.states[buf][id]
      local label = ({ running = "RUNNING", ok = "DONE", error = "ERROR" })[state]
      local title = ("  %d  %s%s  "):format(count, kind:upper(), label and "  " .. label or "")
      local color = state == "error" and "NotebookRsFailed"
        or state == "running" and "NotebookRsRunning" or colors[kind]
      local rule = "╭─" .. title .. string.rep("─", math.max(4, 52 - vim.fn.strdisplaywidth(title)))
      local virtual = {}
      if count > 1 then
        for _ = 1, M.distance_between_cells do
          virtual[#virtual + 1] = { { " ", "Normal" } }
        end
      end
      virtual[#virtual + 1] = { { rule, color } }
      vim.api.nvim_buf_set_extmark(buf, borders, row - 1, 0, {
        virt_lines = virtual,
        virt_lines_above = true,
        line_hl_group = color,
        sign_text = "▌",
        sign_hl_group = color,
        priority = 40,
      })
    end
  end
  if previous_kind then
    close_cell(buf, #lines - 1, previous_kind)
  end
  M.focus(buf)
end

function M.begin(buf, lines, cursor, all)
  local states = M.states[buf] or {}
  M.states[buf] = states
  local selected
  for row, line in ipairs(lines) do
    local kind, id = line:match("^# %%%% %[(%a+)%] id=(%S+)")
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
  local lines = vim.api.nvim_buf_get_lines(buf, 0, cursor, false)
  for row = #lines, 1, -1 do
    local kind = lines[row]:match("^# %%%% %[(%a+)%]")
    if colors[kind] then
      vim.api.nvim_buf_set_extmark(buf, focus, row - 1, 0, {
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
