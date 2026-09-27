local M = { versions = {} }

local function version(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  return { size = stat.size, sec = stat.mtime.sec, nsec = stat.mtime.nsec }
end

local function same(a, b)
  if not a or not b then
    return a == b
  end
  return a.size == b.size and a.sec == b.sec and a.nsec == b.nsec
end

local function swaps(path)
  local resolved = vim.uv.fs_realpath(path) or path
  local state = vim.fn.stdpath("state") .. "/swap/"
  local encoded = resolved:gsub("/", "%%")
  local matches = vim.fn.glob(state .. encoded .. ".sw?", false, true)
  local local_swap = vim.fn.glob(vim.fn.fnamemodify(resolved, ":h")
    .. "/." .. vim.fn.fnamemodify(resolved, ":t") .. ".sw?", false, true)
  vim.list_extend(matches, local_swap)
  return matches
end

function M.open(buf, path)
  M.versions[buf] = version(path)
  local found = swaps(path)
  if #found > 0 then
    vim.schedule(function()
      vim.notify("Existing swap for this notebook: " .. found[1]
        .. "\nCheck unsaved changes in the other Neovim session before saving.", vim.log.levels.WARN,
        { title = "Notebook" })
    end)
  end
end

function M.check(buf, path)
  if not same(M.versions[buf], version(path)) then
    error("notebook changed on disk since opening: " .. path .. "; reload it before saving")
  end
end

function M.saved(buf, path)
  M.versions[buf] = version(path)
end

function M.release(buf)
  M.versions[buf] = nil
end

return M
