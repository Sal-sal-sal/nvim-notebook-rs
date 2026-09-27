local M = { records = {} }

local function remember(buf, results)
  local records = M.records[buf] or {}
  M.records[buf] = records
  for _, result in ipairs(results or {}) do
    if #(result.outputs or {}) > 0 then
      records[result.id] = { source = result.source, outputs = result.outputs }
    else
      records[result.id] = nil
    end
  end
end

function M.attach(buf, results)
  M.records[buf] = {}
  remember(buf, results)
end

function M.update(buf, results)
  remember(buf, results)
end

function M.release(buf)
  M.records[buf] = nil
end

local function source_matches(source, lines, first, last)
  source = source or ""
  local body = {}
  for row = first, last do
    body[#body + 1] = lines[row]
  end
  local shown = table.concat(body, "\n")
  if #body > 0 then
    shown = shown .. "\n"
  end
  return source == shown or (source:sub(-1) ~= "\n" and source .. "\n" == shown)
end

local function traceback(output)
  local value = output.traceback
  local trace = type(value) == "table" and table.concat(value, "\n")
    or type(value) == "string" and value or ""
  if trace == "" then
    trace = (output.ename or "Error") .. ": " .. (output.evalue or "")
  end
  return trace:gsub("\27%[[%d;]*[A-Za-z]", ""):gsub("\r", "")
end

local function output_lines(output)
  if output.output_type == "error" then
    return "ERROR " .. (output.ename or "Python"), traceback(output), "NotebookRsTraceback"
  end
  if output.output_type == "stream" then
    local value = output.text
    return "OUTPUT", type(value) == "table" and table.concat(value) or value or "", "NotebookRsOutput"
  end
  local data = output.data or {}
  local value = data["text/plain"]
  if type(value) == "table" then
    value = table.concat(value)
  end
  if data["image/png"] then
    value = (value or "") .. "\n[Image output saved in notebook]"
  end
  if data["text/html"] then
    value = (value or "") .. "\n[HTML output saved in notebook]"
  end
  return "RESULT", value or "", "NotebookRsOutput"
end

function M.virtual_lines(buf, id, lines, first, last)
  if require("notebook_rs.config").nootbook_result ~= "nootbook" then
    return {}
  end
  local records = M.records[buf]
  local record = records and records[id]
  if not record then
    return {}
  end
  if not source_matches(record.source, lines, first, last) then
    records[id] = nil
    return {}
  end
  local virtual = {}
  for _, output in ipairs(record.outputs) do
    local title, value, color = output_lines(output)
    virtual[#virtual + 1] = { { "├─ " .. title .. " ─", output.output_type == "error"
      and "NotebookRsFailed" or "NotebookRsOutput" } }
    local parts = vim.split(value, "\n", { plain = true })
    if parts[#parts] == "" then
      table.remove(parts)
    end
    for _, line in ipairs(parts) do
      virtual[#virtual + 1] = { { "│ " .. line, color } }
    end
  end
  return virtual
end

vim.api.nvim_set_hl(0, "NotebookRsTraceback", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "NotebookRsOutput", { link = "Normal", default = true })

return M
