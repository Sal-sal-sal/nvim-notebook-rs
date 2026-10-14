local M = {}
local kinds = { code = true, markdown = true, raw = true }

function M.parse(line)
  local kind, id = line:match("^# %%%% %[(%a+)%] id=(%S+)%s*$")
  if kinds[kind] then return kind, id end
end

return M
