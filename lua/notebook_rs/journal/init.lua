local M = {}

function M.environment()
  return { NVIM_NOTEBOOK_COLAB_JOURNAL = vim.env.NVIM_NOTEBOOK_COLAB_JOURNAL
    or (vim.fn.stdpath("state") .. "/notebook-rs/colab-journal.json") }
end

function M.open()
  -- A separate reader stays usable while the execution worker is busy.
  local ok, data = pcall(require("notebook_rs.client").once, { op = "colab_journal" })
  if not ok then
    vim.notify("Could not read Colab journal: " .. tostring(data), vim.log.levels.ERROR)
    return
  end
  require("notebook_rs.journal.view").show(data, M.open)
end

return M
