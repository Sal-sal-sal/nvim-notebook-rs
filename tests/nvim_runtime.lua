local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
vim.g.notebook_rs_bin = assert(vim.env.NOTEBOOK_RS_BIN)
local log = vim.fn.tempname()
local cli = vim.fn.tempname()
local script = table.concat(vim.fn.readfile(root .. "/tests/fake_colab.py"), "\n")
vim.env.NVIM_NOTEBOOK_TEST_RUNTIME_LOG = log
local spy = "#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\n"
  .. "with Path(os.environ['NVIM_NOTEBOOK_TEST_RUNTIME_LOG']).open('a') as f: "
  .. "f.write(json.dumps(sys.argv[1:])+'\\n')\n"
vim.fn.writefile(vim.split(spy .. script, "\n", { plain = true }), cli)
assert(vim.uv.fs_chmod(cli, 493))
vim.env.NVIM_NOTEBOOK_COLAB = cli
local plugin = require("notebook_rs")
plugin.setup({ python_lsp = { enabled = false } })
local config = require("notebook_rs.config")
assert(config.notebook_runtime == 3600, "default runtime changed")
local path = vim.fn.tempname() .. ".ipynb"
vim.cmd("NotebookNew " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local lines = { "# %% [code] id=runtime", "print('timeout')" }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.cmd("doautocmd TextChanged")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("NotebookColabConnect training")
assert(vim.wait(5000, function() return vim.b[buf].notebook_rs_backend == "colab" end, 20))

local function timeout()
  local result
  for _, line in ipairs(vim.fn.readfile(log)) do
    local args = vim.json.decode(line)
    if args[1] == "exec" then
      for index, arg in ipairs(args) do if arg == "--timeout" then result = args[index + 1] end end
    end
  end
  return result
end

local function run(expected)
  vim.cmd("NotebookRun")
  assert(vim.wait(5000, function()
    return require("notebook_rs.cells").states[buf].runtime == "ok" and timeout() == expected
  end, 20), "Lua setting did not reach the Colab CLI")
end

assert(timeout() == "20", "execution timeout changed the connection probe")
run("3600")
plugin.setup({ notebook_runtime = 7200 })
run("7200")
for _, invalid in ipairs({ 0, -1, 1.5, "7200", false }) do
  assert(not pcall(plugin.setup, { notebook_runtime = invalid }), "invalid runtime was accepted")
  assert(config.notebook_runtime == 7200, "invalid runtime changed the configuration")
end
local client = require("notebook_rs.client")
local payload = { op = "run", lines = lines, line = 2, all = false, backend = "colab", path = path }
local function request(value)
  local response
  client.request(value, function(result) response = result end)
  assert(vim.wait(5000, function() return response ~= nil end, 20), "worker did not respond")
  return response
end
local legacy = request(payload)
assert(legacy.ok and legacy.data.success and timeout() == "3600", "old JSON clients lost the default timeout")
payload.notebook_runtime = 0
local count = #vim.fn.readfile(log)
local invalid = request(payload)
assert(not invalid.ok and invalid.error:find("notebook_runtime must be greater than zero", 1, true))
assert(#vim.fn.readfile(log) == count, "zero timeout reached the CLI")
for _, file in ipairs({ path, log, cli }) do vim.fn.delete(file) end
print("Neovim configurable runtime and Colab CLI argument test passed")
