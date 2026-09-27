local M = {}
local bindings = {}
local kinds = { code = true, markdown = true, raw = true }

local function markers(buf)
  local rows = {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if kinds[line:match("^# %%%% %[(%a+)%]")] then
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function notebook_buffer()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.b[buf].notebook_rs_path then
    error("open a notebook with :NotebookOpen first")
  end
  return buf
end

local function jump(buf, rows, number)
  if number < 1 or number > #rows then
    vim.notify(("Notebook has %d cells; cell %d is unavailable"):format(#rows, number), vim.log.levels.WARN)
    return
  end
  local target = rows[number]
  if target < vim.api.nvim_buf_line_count(buf) and (not rows[number + 1] or target + 1 < rows[number + 1]) then
    target = target + 1
  end
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  require("notebook_rs.cells").focus(buf)
end

function M.go_to(number)
  local buf = notebook_buffer()
  number = tonumber(number)
  if not number or number % 1 ~= 0 then
    error("cell number must be a positive integer")
  end
  jump(buf, markers(buf), number)
end

function M.relative(step)
  local buf = notebook_buffer()
  local rows = markers(buf)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local current = 0
  for index, row in ipairs(rows) do
    if row > cursor then
      break
    end
    current = index
  end
  jump(buf, rows, current + step)
end

function M.refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].notebook_rs_path then
    return
  end
  local count = #markers(buf)
  local previous = bindings[buf] or 0
  if previous == count then
    return
  end
  for number = count + 1, previous do
    vim.keymap.del("n", "<leader>" .. number .. "b", { buffer = buf })
  end
  for number = previous + 1, count do
    vim.keymap.set("n", "<leader>" .. number .. "b", function() M.go_to(number) end, {
      buffer = buf,
      desc = ("Notebook: go to cell %d"):format(number),
    })
  end
  bindings[buf] = count
end

function M.attach(buf)
  require("notebook_rs.shortcuts").attach(buf)
  local maps = {
    { "<leader>jc", function() M.relative(1) end, "Notebook: next cell" },
    { "<leader>kc", function() M.relative(-1) end, "Notebook: previous cell" },
    { "<leader>rc", function() vim.cmd.NotebookRun() end, "Notebook: run current cell" },
    { "<leader>rr", function() vim.cmd.NotebookRun() end, "Notebook: run current cell" },
    { "<leader>ra", function() vim.cmd.NotebookRunAll() end, "Notebook: run all cells" },
  }
  for _, map in ipairs(maps) do
    vim.keymap.set("n", map[1], map[2], { buffer = buf, desc = map[3] })
  end
  M.refresh(buf)
  local group = vim.api.nvim_create_augroup("NotebookRsNavigation" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function() M.refresh(buf) end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function() bindings[buf] = nil end,
  })
end

return M
