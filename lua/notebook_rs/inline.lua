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

function M.virtual_lines(buf, id, lines, first, last)
  local config = require("notebook_rs.config")
  if config.nootbook_result ~= "nootbook" then return {} end
  local records = M.records[buf]
  local record = records and records[id]
  if not record then return {} end
  local output = require("notebook_rs.output")
  local source = output.source(buf)
  local text = require("notebook_rs.output.text")
  if not text.source_matches(record.source, source, output.source_row(buf, first - 1) + 1,
    output.source_row(buf, last)) then
    records[id] = nil
    return {}
  end
  local virtual = {}
  local media = config.cells_output_interacteable and true or nil
  for _, row in ipairs(text.rows(record.outputs, media)) do
    virtual[#virtual + 1] = { { row.text, row.color } }
  end
  return virtual
end

vim.api.nvim_set_hl(0, "NotebookRsTraceback", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "NotebookRsOutput", { link = "Normal", default = true })

return M
