local M = {
  distance_between_cells = 2,
  nootbook_hidden_id_line = true,
  nootbook_result = "nootbook",
}

function M.update(opts)
  opts = opts or {}
  local distance = opts.distance_between_cells
  local hidden = opts.nootbook_hidden_id_line
  local result = opts.nootbook_result
  if distance ~= nil then
    assert(type(distance) == "number" and distance >= 0 and distance % 1 == 0,
      "distance_between_cells must be a non-negative integer")
  end
  if hidden ~= nil then
    assert(type(hidden) == "boolean",
      "nootbook_hidden_id_line must be a boolean")
  end
  if result ~= nil then
    assert(vim.tbl_contains({ "nootbook", "window", "hidden" }, result),
      "nootbook_result must be 'nootbook', 'window', or 'hidden'")
  end
  M.distance_between_cells = distance or M.distance_between_cells
  if hidden ~= nil then M.nootbook_hidden_id_line = hidden end
  M.nootbook_result = result or M.nootbook_result
end

return M
