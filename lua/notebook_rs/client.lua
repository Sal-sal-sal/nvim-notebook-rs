local M = { next_id = 0, pending = {}, fragment = "" }
local job

local function binary()
  local explicit = vim.g.notebook_rs_bin
  if explicit and vim.fn.executable(explicit) == 1 then
    return explicit
  end
  local path = vim.fn.exepath("nvim-notebook-rs")
  if path ~= "" then
    return path
  end
  local files = vim.api.nvim_get_runtime_file("lua/notebook_rs/client.lua", false)
  for _, file in ipairs(files) do
    local root = file:gsub("/lua/notebook_rs/client%.lua$", "")
    for _, profile in ipairs({ "release", "debug" }) do
      local candidate = root .. "/target/" .. profile .. "/nvim-notebook-rs"
      if vim.fn.executable(candidate) == 1 then
        return candidate
      end
    end
  end
  error("nvim-notebook-rs binary not found; run cargo build --release")
end

M.binary = binary

local function deliver(line)
  if line == "" then
    return
  end
  local ok, response = pcall(vim.json.decode, line)
  if not ok then
    vim.notify("Notebook worker sent invalid JSON", vim.log.levels.ERROR)
    return
  end
  local callback = M.pending[response.id]
  M.pending[response.id] = nil
  if callback then
    vim.schedule(function()
      callback(response)
    end)
  end
end

local function start()
  if job and job > 0 then
    return job
  end
  M.fragment = ""
  job = vim.fn.jobstart({ binary(), "worker" }, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if not data then
        return
      end
      data[1] = M.fragment .. data[1]
      M.fragment = table.remove(data) or ""
      for _, line in ipairs(data) do
        deliver(line)
      end
    end,
    on_exit = function(_, code)
      job = nil
      vim.schedule(function()
        for id, callback in pairs(M.pending) do
          M.pending[id] = nil
          callback({ ok = false, error = "notebook worker exited with code " .. code })
        end
      end)
    end,
  })
  if job <= 0 then
    job = nil
    error("could not start nvim-notebook-rs worker")
  end
  return job
end

function M.request(payload, callback)
  M.next_id = M.next_id + 1
  payload.id = M.next_id
  M.pending[payload.id] = callback
  vim.fn.chansend(start(), vim.json.encode(payload) .. "\n")
end

function M.once(payload)
  payload.id = 1
  local result = vim.system({ binary(), "worker" }, {
    stdin = vim.json.encode(payload) .. "\n",
    text = true,
  }):wait(30000)
  if result.code ~= 0 then
    error(result.stderr ~= "" and result.stderr or "notebook worker failed")
  end
  local response = vim.json.decode(vim.split(result.stdout, "\n", { plain = true })[1])
  if not response.ok then
    error(response.error)
  end
  return response.data
end

return M
