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

function M.anchor(buf, row, id)
  local config = require("notebook_rs.config")
  if not config.cells_output_interacteable or config.image_output_position ~= "before_text" then return row end
  local record = (M.records[buf] or {})[id]
  local image = false
  for _, item in ipairs(record and record.outputs or {}) do
    image = image or (item.data or {})["image/png"] or (item.data or {})["image/jpeg"]
  end
  if not image then return row end
  local state = require("notebook_rs.output").states[buf]
  local anchor = row
  while state and state.rows[anchor + 1] and state.rows[anchor + 1].output do anchor = anchor - 1 end
  return anchor
end

local function ordered(outputs)
  local grouped = require("notebook_rs.output.text").blocks(outputs)
  if require("notebook_rs.config").image_output_position ~= "before_text" then return grouped end
  local images, other = {}, {}
  for _, item in ipairs(grouped) do
    local data = item.output.data or {}
    local target = (data["image/png"] or data["image/jpeg"]) and images or other
    target[#target + 1] = item
  end
  return vim.list_extend(images, other)
end

function M.virtual_lines(buf, id, lines, first, last, anchor)
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
  local number = 0
  for _, block in ipairs(ordered(record.outputs)) do
    local item = block.output
    local image = (item.data or {})["image/png"] or (item.data or {})["image/jpeg"]
    if image then number = number + 1 end
    if (not image or not require("notebook_rs.charts").append(buf, item, virtual, anchor or last - 1, number))
      and (media == nil or text.is_media(item) == media) then
      for _, row in ipairs(block.rows) do
        virtual[#virtual + 1] = { { row.text, row.color } }
      end
    end
  end
  return virtual
end

vim.api.nvim_set_hl(0, "NotebookRsTraceback", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "NotebookRsOutput", { link = "Normal", default = true })

return M
