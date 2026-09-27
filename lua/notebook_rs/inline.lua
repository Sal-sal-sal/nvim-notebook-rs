local M = { errors = {} }

local function has_error(outputs)
  for _, output in ipairs(outputs or {}) do
    if output.output_type == "error" then
      return true
    end
  end
  return false
end

local function remember(buf, results)
  local records = M.errors[buf] or {}
  M.errors[buf] = records
  for _, result in ipairs(results or {}) do
    if has_error(result.outputs) then
      records[result.id] = { source = result.source, outputs = result.outputs }
    else
      records[result.id] = nil
    end
  end
end

function M.attach(buf, errors)
  M.errors[buf] = {}
  remember(buf, errors)
end

function M.update(buf, results)
  remember(buf, results)
end

function M.release(buf)
  M.errors[buf] = nil
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

function M.virtual_lines(buf, id, lines, first, last)
  local records = M.errors[buf]
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
    if output.output_type == "error" then
      virtual[#virtual + 1] = { { "├─ ERROR " .. (output.ename or "Python") .. " ─", "NotebookRsFailed" } }
      local parts = vim.split(traceback(output), "\n", { plain = true })
      if parts[#parts] == "" then
        table.remove(parts)
      end
      for _, line in ipairs(parts) do
        virtual[#virtual + 1] = { { "│ " .. line, "NotebookRsTraceback" } }
      end
    end
  end
  return virtual
end

vim.api.nvim_set_hl(0, "NotebookRsTraceback", { link = "DiagnosticError", default = true })

return M
