local M = {
  distance_between_cells = 2,
  notebook_runtime = 3600,
  cells_output_interacteable = false,
  nootbook_hidden_id_line = true,
  nootbook_result = "nootbook",
  python_lsp = { enabled = true, server = "pyright" },
}

function M.update(opts)
  opts = opts or {}
  local interactive = opts.cells_output_interacteable
  if interactive ~= nil then
    assert(type(interactive) == "boolean", "cells_output_interacteable must be a boolean")
  end
  local distance = opts.distance_between_cells
  local hidden = opts.nootbook_hidden_id_line
  local result = opts.nootbook_result
  local runtime = opts.notebook_runtime

  if distance ~= nil then
    assert(type(distance) == "number" and distance >= 0 and distance % 1 == 0,
      "distance_between_cells must be a non-negative integer")
  end
  if hidden ~= nil then
    assert(type(hidden) == "boolean",
      "nootbook_hidden_id_line must be a boolean")
  end
  if runtime ~= nil then
    assert(type(runtime) == "number" and runtime > 0 and runtime % 1 == 0,
      "notebook_runtime must be a positive integer")
  end
  if result ~= nil then
    assert(vim.tbl_contains({ "nootbook", "window", "hidden" }, result),
      "nootbook_result must be 'nootbook', 'window', or 'hidden'")
  end
  if interactive ~= nil then M.cells_output_interacteable = interactive end
  M.distance_between_cells = distance or M.distance_between_cells
  M.notebook_runtime = runtime or M.notebook_runtime
  if hidden ~= nil then M.nootbook_hidden_id_line = hidden end
  M.nootbook_result = result or M.nootbook_result
  if opts.python_lsp ~= nil then
    assert(type(opts.python_lsp) == "table", "python_lsp must be a table")
    M.python_lsp = vim.tbl_deep_extend("force", M.python_lsp, opts.python_lsp)
    assert(type(M.python_lsp.enabled) == "boolean", "python_lsp.enabled must be a boolean")
    assert(type(M.python_lsp.server) == "string", "python_lsp.server must be a string")
    if M.python_lsp.python_path ~= nil then
      assert(type(M.python_lsp.python_path) == "string", "python_lsp.python_path must be a string")
    end
    if M.python_lsp.cmd ~= nil then
      assert(type(M.python_lsp.cmd) == "table" and type(M.python_lsp.cmd[1]) == "string",
        "python_lsp.cmd must be a non-empty command list")
    end
  end
end

return M
