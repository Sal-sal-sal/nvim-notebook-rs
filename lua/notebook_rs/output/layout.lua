local text = require("notebook_rs.output.text")
local markers = require("notebook_rs.markers")
local M = {}

function M.build(source, records, prefix, enabled)
  local rows, marker, kind, id = {}, nil, nil, nil
  local function finish(last)
    local record = kind == "code" and records[id]
    if not record then return end
    if not text.source_matches(record.source, source, marker + 1, last) then
      records[id] = nil
      return
    end
    if enabled then
      for index, line in ipairs(text.rows(record.outputs, false)) do
        rows[#rows + 1] = { text = prefix .. line.text, color = line.color,
          source = last, output = true, id = id, index = index }
      end
    end
  end
  for index, line in ipairs(source) do
    local next_kind, next_id = markers.parse(line)
    if next_kind then
      finish(index - 1)
      marker, kind, id = index, next_kind, next_id
    end
    rows[#rows + 1] = { text = line, source = index }
  end
  finish(#source)
  return rows
end

function M.source_row(rows, row)
  return rows[math.min(row, #rows)] and rows[math.min(row, #rows)].source or row
end

function M.display_row(rows, source)
  for row, item in ipairs(rows) do
    if not item.output and item.source >= source then return row end
  end
  return math.max(1, #rows)
end

function M.locate(rows, anchor)
  if anchor and anchor.output then
    local last
    for row, item in ipairs(rows) do
      if item.output and item.id == anchor.id then
        last = row
        if item.index >= (anchor.index or 1) then return row end
      end
    end
    if last then return last end
  end
  return M.display_row(rows, anchor and anchor.source or 1)
end

return M
