local M = {}
local buffers = {}

function M.file(buf, output)
  local data = output.data or {}
  local mime = data["image/png"] and "image/png" or data["image/jpeg"] and "image/jpeg"
  if not mime then return end
  local encoded = data[mime]
  if type(encoded) == "table" then
    local ok, joined = pcall(table.concat, encoded)
    if not ok then return end
    encoded = joined
  end
  if type(encoded) ~= "string" then return end
  encoded = encoded:gsub("%s", "")
  local key = vim.fn.sha256(encoded)
  local cache = buffers[buf]
  if not cache then
    cache = { directory = vim.fn.tempname(), files = {} }
    buffers[buf] = cache
    vim.fn.mkdir(cache.directory, "p")
  end
  if cache.files[key] then return cache.files[key] end
  local ok, bytes = pcall(vim.base64.decode, encoded)
  if not ok or not (mime == "image/png" and bytes:sub(1, 8) == "\137PNG\r\n\26\n"
    or mime == "image/jpeg" and bytes:sub(1, 3) == "\255\216\255") then return end
  local path = cache.directory .. "/" .. key .. (mime == "image/png" and ".png" or ".jpg")
  local file = io.open(path, "wb")
  if not file then return end
  file:write(bytes)
  file:close()
  cache.files[key] = path
  return path
end

function M.release(buf)
  if buffers[buf] then vim.fn.delete(buffers[buf].directory, "rf") end
  buffers[buf] = nil
end

return M
