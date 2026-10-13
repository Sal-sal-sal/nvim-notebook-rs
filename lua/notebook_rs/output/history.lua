local M = {}

local function tree(buf)
  return vim.api.nvim_buf_call(buf, vim.fn.undotree)
end

local function sequences(entries, keep)
  for _, entry in ipairs(entries or {}) do
    keep[entry.seq] = true
    sequences(entry.alt, keep)
  end
end

function M.restore(buf, state)
  local sequence = tree(buf).seq_cur
  local frame = state.history and state.history[sequence]
  if sequence == state.sequence or not frame or not vim.deep_equal(frame.source, state.source) then
    return
  end
  local records = {}
  for id, record in pairs(frame.records) do
    records[id] = record
  end
  require("notebook_rs.inline").records[buf] = records
  require("notebook_rs.ui").results[buf] = vim.tbl_extend("force", {}, frame.results)
  return records
end

function M.capture(buf, state, records)
  local undo = tree(buf)
  state.sequence = undo.seq_cur
  state.history = state.history or {}
  state.history[undo.seq_cur] = { source = vim.deepcopy(state.source),
    records = vim.tbl_extend("force", {}, records),
    results = vim.tbl_extend("force", {}, require("notebook_rs.ui").results[buf] or {}) }
  local keep = { [0] = true, [undo.seq_cur] = true }
  sequences(undo.entries, keep)
  for sequence in pairs(state.history) do
    if not keep[sequence] then state.history[sequence] = nil end
  end
end

return M
