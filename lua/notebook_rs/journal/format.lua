local M = {}

local function fields(lines, value, indent, key)
  local prefix = string.rep(" ", indent) .. (key and tostring(key) .. ": " or "")
  if key and tostring(key):match("^image/") then
    local bytes = type(value) == "table" and #table.concat(value) or #tostring(value)
    lines[#lines + 1] = prefix .. ("[image: %d base64 characters; stored in journal file]"):format(bytes)
  elseif value == vim.NIL or value == nil then
    lines[#lines + 1] = prefix .. "null"
  elseif type(value) == "table" then
    local nested = indent
    if key or next(value) == nil then
      lines[#lines + 1] = next(value) == nil and prefix .. "{}" or prefix:gsub(" $", "")
      nested = indent + 2
    end
    local keys = vim.tbl_keys(value)
    table.sort(keys, function(a, b)
      if type(a) == "number" and type(b) == "number" then return a < b end
      return tostring(a) < tostring(b)
    end)
    for _, name in ipairs(keys) do fields(lines, value[name], nested, name) end
  elseif type(value) == "string" then
    local text = require("notebook_rs.output.stream").visible(value)
    local parts = vim.split(text, "\n", { plain = true })
    if parts[#parts] == "" and #parts > 1 then table.remove(parts) end
    for index, part in ipairs(parts) do
      lines[#lines + 1] = (index == 1 and prefix or string.rep(" ", indent + 2)) .. part
    end
  else
    lines[#lines + 1] = prefix .. tostring(value)
  end
end

local function status(entry)
  local response = entry.response
  if response == nil or response == vim.NIL then
    if type(entry.worker_pid) ~= "number" or entry.worker_pid <= 0 then return "INTERRUPTED" end
    local ok, alive = pcall(vim.uv.kill, entry.worker_pid, 0)
    return ok and alive and "RUNNING" or "INTERRUPTED"
  end
  local data = type(response.data) == "table" and response.data or {}
  return (response.ok == false or data.success == false) and "ERROR" or "OK"
end

function M.render(data)
  local entries = data.entries or {}
  local lines = { ("Colab request journal · %d/%d"):format(#entries, data.limit or 100),
    "File: " .. data.path, "<Enter> fold/unfold · r refresh · q close · / search", "" }
  local folds, headings = {}, {}
  if #entries == 0 then lines[#lines + 1] = "No Colab requests recorded yet." end
  for index = #entries, 1, -1 do
    local entry = entries[index]
    local first = #lines + 1
    local duration = type(entry.duration_ms) == "number" and entry.duration_ms .. " ms" or "no return yet"
    local time = os.date("%Y-%m-%d %H:%M:%S", math.floor(entry.started_at_ms / 1000))
    local request = entry.request or {}
    local label = request.op == "run" and (request.all and "run all" or "run cell") or request.op
    local session = type(request.session) == "string" and " [" .. request.session .. "]" or ""
    local state = status(entry)
    lines[#lines + 1] = ("#%04d  %s  %s%s  %s  %s"):format(entry.id, time, label, session, state, duration)
    headings[#headings + 1] = { row = first - 1, state = state }
    lines[#lines + 1] = "  REQUEST"
    fields(lines, request, 4)
    lines[#lines + 1] = "  RETURN"
    if state == "RUNNING" then
      lines[#lines + 1] = "    Waiting for Colab; press r to refresh."
    elseif state == "INTERRUPTED" then
      lines[#lines + 1] = "    Worker stopped before a return was recorded."
    else
      fields(lines, entry.response, 4)
    end
    folds[#folds + 1] = { first, #lines }
    lines[#lines + 1] = ""
  end
  return lines, folds, headings
end

return M
