local M = {}

M.defaults = { auto_download = true, max_download_mb = 25,
  packages = { sklearn = "scikit-learn", PIL = "Pillow", yaml = "PyYAML", cv2 = "opencv-python" } }

function M.validate(options)
  assert(type(options) == "table", "python_lsp.documentation must be a table")
  assert(type(options.auto_download) == "boolean", "documentation.auto_download must be a boolean")
  assert(type(options.max_download_mb) == "number" and options.max_download_mb > 0
    and options.max_download_mb % 1 == 0, "documentation.max_download_mb must be a positive integer")
  assert(type(options.packages) == "table", "documentation.packages must be a table")
  for module, package in pairs(options.packages) do
    assert(type(module) == "string" and module:match("^[%a_][%w_]*$") and type(package) == "string",
      "documentation.packages must map import names to package names or package==version")
  end
  if options.cache ~= nil then assert(type(options.cache) == "string", "documentation.cache must be a path") end
end

return M
