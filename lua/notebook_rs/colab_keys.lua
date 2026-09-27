local ui = require("notebook_rs.ui")
local status = require("notebook_rs.status")
local M = {}

local function prompt(label, default, callback, optional)
  vim.ui.input({ prompt = label, default = default }, function(value)
    if value == nil then
      return
    end
    value = vim.trim(value)
    if value ~= "" or optional then
      callback(value)
    end
  end)
end

local function connect()
  prompt("Colab session: ", status.session or "nvim", function(session)
    ui.colab({ op = "colab_connect", session = session })
  end)
end

local function create()
  prompt("New Colab session: ", "nvim", function(session)
    prompt("GPU/TPU (optional): ", "", function(accelerator)
      ui.colab({ op = "colab_new", session = session,
        gpu = accelerator ~= "" and accelerator or nil })
    end, true)
  end)
end

local function install()
  prompt("Packages to install: ", "", function(value)
    ui.colab({ op = "colab_install", packages = vim.split(value, "%s+") })
  end)
end

local function list_files()
  prompt("Remote path: ", "/content", function(path)
    ui.colab({ op = "colab_list", path = path })
  end)
end

local function upload()
  prompt("Local file: ", "", function(path)
    prompt("Remote path: ", "/content/", function(remote)
      ui.colab({ op = "colab_upload", ["local"] = vim.fn.fnamemodify(path, ":p"), remote = remote })
    end)
  end)
end

local function download()
  prompt("Remote file: ", "", function(remote)
    prompt("Local path: ", "", function(path)
      ui.colab({ op = "colab_download", remote = remote, ["local"] = vim.fn.fnamemodify(path, ":p") })
    end)
  end)
end

local function command(op)
  return function() ui.colab({ op = op }) end
end

local actions = {
  { key = "l", label = "Log in", run = ui.login },
  { key = "n", label = "New session", run = create },
  { key = "c", label = "Connect to session", run = connect },
  { key = "s", label = "Connection status", run = command("colab_status") },
  { key = "p", label = "List sessions", run = command("colab_sessions") },
  { key = "r", label = "Restart session", run = command("colab_restart") },
  { key = "u", label = "Open session URL", run = command("colab_url") },
  { key = "x", label = "Stop session", run = command("colab_stop") },
  { key = "b", label = "Use Colab backend", run = function() ui.backend("colab") end },
  { key = "L", label = "Use local backend", run = function() ui.backend("local") end },
  { key = "i", label = "Install packages", run = install },
  { key = "f", label = "List remote files", run = list_files },
  { key = "U", label = "Upload file", run = upload },
  { key = "D", label = "Download file", run = download },
}

function M.open()
  vim.ui.select(actions, {
    prompt = "Colab connections and tools",
    format_item = function(item) return item.key .. "  " .. item.label end,
  }, function(item)
    if item then
      item.run()
    end
  end)
end

function M.attach(buf)
  vim.keymap.set("n", "<leader>cc", M.open, { buffer = buf, desc = "Colab: connections and tools" })
  for _, item in ipairs(actions) do
    vim.keymap.set("n", "<leader>cc" .. item.key, item.run, {
      buffer = buf,
      desc = "Colab: " .. item.label,
    })
  end
end

return M
