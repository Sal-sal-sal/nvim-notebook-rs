local stream = require("notebook_rs.output.stream")
local M = {}

function M.source_matches(source, lines, first, last)
  source = source or ""
  local body = {}
  for row = first, last do body[#body + 1] = lines[row] end
  local shown = table.concat(body, "\n") .. (#body > 0 and "\n" or "")
  return source == shown or (source:sub(-1) ~= "\n" and source .. "\n" == shown)
end

function M.is_media(output)
  for mime in pairs(output.data or {}) do
    if mime:match("^image/") or mime == "text/html" then return true end
  end
  return false
end

local function joined(value)
  return type(value) == "table" and table.concat(value) or value or ""
end

local function content(output)
  if output.output_type == "error" then
    local trace = joined(output.traceback)
    if trace == "" then trace = (output.ename or "Error") .. ": " .. (output.evalue or "") end
    return "ERROR " .. (output.ename or "Python"), trace:gsub("\27%[[%d;]*[A-Za-z]", ""):gsub("\r", ""),
      "NotebookRsTraceback"
  end
  if output.output_type == "stream" then
    return "OUTPUT", stream.visible(joined(output.text)), "NotebookRsOutput"
  end
  local data = output.data or {}
  local value = joined(data["text/plain"])
  if data["image/png"] or data["image/jpeg"] then value = value .. "\n[Image output saved in notebook]" end
  if data["text/html"] then value = value .. "\n[HTML output saved in notebook]" end
  return "RESULT", value, "NotebookRsOutput"
end

function M.blocks(outputs)
  local blocks, hidden, tail = {}, 0, nil
  local remaining = require("notebook_rs.config").notebook.output.head or math.huge
  for _, output in ipairs(stream.groups(outputs)) do
    local block = { output = output, rows = {} }
    blocks[#blocks + 1] = block
    local title, value, color = content(output)
    local parts = vim.split(value, "\n", { plain = true })
    if parts[#parts] == "" then table.remove(parts) end
    local image = (output.data or {})["image/png"] or (output.data or {})["image/jpeg"]
    local count = image and #parts or math.min(remaining, #parts)
    if not image then
      remaining, hidden, tail = remaining - count, hidden + #parts - count, block
    end
    if count > 0 or #parts == 0 then
      block.rows[1] = { text = "├─ " .. title .. " ─", color = output.output_type == "error"
        and "NotebookRsFailed" or "NotebookRsOutput" }
      for index = 1, count do
        block.rows[#block.rows + 1] = { text = "│ " .. parts[index], color = color }
      end
    end
  end
  if hidden > 0 then
    tail.rows[#tail.rows + 1] = { text = ("│ … %d more lines (notebook.output.head)"):format(hidden),
      color = "Comment" }
  end
  return blocks
end

function M.rows(outputs, media)
  local rows = {}
  for _, block in ipairs(M.blocks(outputs)) do
    if media == nil or M.is_media(block.output) == media then vim.list_extend(rows, block.rows) end
  end
  return rows
end

return M
