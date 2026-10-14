local M = {}

local function joined(text)
  return type(text) == "table" and table.concat(text) or text or ""
end

function M.groups(outputs)
  local groups, chunks, name = {}, nil, nil
  local function flush()
    if chunks then
      groups[#groups + 1] = { output_type = "stream", name = name, text = table.concat(chunks) }
      chunks = nil
    end
  end
  for _, output in ipairs(outputs or {}) do
    if output.output_type == "stream" then
      local next_name = output.name or "stdout"
      if chunks and name ~= next_name then flush() end
      if not chunks then chunks, name = {}, next_name end
      chunks[#chunks + 1] = joined(output.text)
    else
      flush()
      groups[#groups + 1] = output
    end
  end
  flush()
  return groups
end

local function erase(line, cursor, mode)
  if mode == 2 then
    for index = #line, 1, -1 do line[index] = nil end
  elseif mode == 1 then
    for index = 1, math.min(cursor, #line) do line[index] = " " end
  else
    for index = #line, cursor, -1 do line[index] = nil end
  end
end

local function escape(text, index, line, cursor)
  local sequence, parameters, command = text:sub(index):match("^(\27%[([0-?]*)[ -/]*([@-~]))")
  if sequence then
    if command == "K" then erase(line, cursor, tonumber(parameters) or 0) end
    return index + #sequence
  end
  if text:sub(index, index + 1) == "\27[" then return #text + 1 end
  if text:sub(index, index + 1) == "\27]" then
    local bell = text:find("\7", index + 2, true)
    local stop = text:find("\27\\", index + 2, true)
    if bell and (not stop or bell < stop) then return bell + 1 end
    return stop and stop + 2 or #text + 1
  end
  return math.min(index + 2, #text + 1)
end

function M.visible(text)
  if not text:find("[%z\1-\9\11-\31\127]") then return text end
  local rows, line, cursor, index = {}, {}, 1, 1
  while index <= #text do
    local byte = text:byte(index)
    local size = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
    local char = text:sub(index, index + size - 1)
    if char == "\27" then
      index = escape(text, index, line, cursor)
    else
      if char == "\r" then
        cursor = 1
      elseif char == "\n" then
        rows[#rows + 1] = table.concat(line)
        line, cursor = {}, 1
      elseif char == "\b" then
        if cursor > 1 then table.remove(line, cursor - 1); cursor = cursor - 1 end
      elseif char == "\t" then
        local target = cursor + 8 - (cursor - 1) % 8
        for column = cursor, target - 1 do line[column] = " " end
        cursor = target
      elseif byte >= 32 and byte ~= 127 then
        for column = #line + 1, cursor - 1 do line[column] = " " end
        line[cursor], cursor = char, cursor + 1
      end
      index = index + size
    end
  end
  rows[#rows + 1] = table.concat(line)
  return table.concat(rows, "\n")
end

return M
