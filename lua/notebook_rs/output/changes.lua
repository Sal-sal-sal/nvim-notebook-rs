local M = {}

function M.record(buf, state, first, last, new_last)
  if state.blocked then return end
  local only_output = last > first
  for row = first + 1, last do
    if not state.rows[row] or not state.rows[row].output then only_output = false end
  end
  local next_row = state.rows[first + 1]
  local inside_output = first == last and next_row and next_row.output and (next_row.index or 0) > 1
  if only_output or inside_output then
    state.blocked = true
    return
  end
  local rows = vim.list_slice(state.rows, 1, first)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, first, new_last, false)) do
    rows[#rows + 1] = { text = line, output = line:sub(1, #state.prefix) == state.prefix, index = 0 }
  end
  vim.list_extend(rows, vim.list_slice(state.rows, last + 1))
  local source = {}
  for _, row in ipairs(rows) do
    if not row.output then source[#source + 1] = row.text end
    row.source = math.max(1, #source)
  end
  state.source, state.rows = source, rows
  state.modified, state.changed = true, true
end

function M.yank(buf, state)
  local event = vim.v.event
  if event.operator ~= "y" then return end
  local first, last = vim.fn.getpos("'[")[2], vim.fn.getpos("']")[2]
  for row = first, last do
    if not state.rows[row] or not state.rows[row].output then return end
  end
  local contents = {}
  for _, line in ipairs(event.regcontents) do
    if line:sub(1, #state.prefix) == state.prefix then line = line:sub(#state.prefix + 1) end
    contents[#contents + 1] = line:gsub("^│ ", "")
  end
  vim.fn.setreg(event.regname, contents, event.regtype)
end

return M
