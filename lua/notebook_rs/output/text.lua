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
  if data["image/png"] then value = value .. "\n[Image output saved in notebook]" end
  if data["text/html"] then value = value .. "\n[HTML output saved in notebook]" end
  return "RESULT", value, "NotebookRsOutput"
end

function M.rows(outputs, media)
  local rows = {}
  for _, output in ipairs(stream.groups(outputs)) do
    if media == nil or M.is_media(output) == media then
      local title, value, color = content(output)
      rows[#rows + 1] = { text = "├─ " .. title .. " ─", color = output.output_type == "error"
        and "NotebookRsFailed" or "NotebookRsOutput" }
      local parts = vim.split(value, "\n", { plain = true })
      if parts[#parts] == "" then table.remove(parts) end
      for _, line in ipairs(parts) do rows[#rows + 1] = { text = "│ " .. line, color = color } end
    end
  end
  return rows
end

return M
