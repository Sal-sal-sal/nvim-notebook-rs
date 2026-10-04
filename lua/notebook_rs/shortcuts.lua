local ui = require("notebook_rs.ui")
local status = require("notebook_rs.status")
local client = require("notebook_rs.client")
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

local function new_session(session, accelerator)
  ui.colab({ op = "colab_new", session = session, gpu = accelerator ~= "" and accelerator or nil })
end

local function ask_new_session(session, accelerator)
  prompt("New Colab session: ", session or status.session or "nvim", function(name)
    prompt("GPU/TPU (optional): ", accelerator or "", function(value)
      new_session(name, value)
    end, true)
  end)
end

local function choose_session(sessions, session, accelerator, should_prompt)
  local choices = {}
  for _, name in ipairs(sessions) do
    choices[#choices + 1] = { kind = "existing", name = name }
  end
  choices[#choices + 1] = { kind = "new", label = "Create a new Colab session" }

  vim.ui.select(choices, {
    prompt = "Colab session",
    format_item = function(item)
      return item.kind == "new" and item.label or "Connect to " .. item.name
    end,
  }, function(item)
    if not item then
      return
    end
    if item.kind == "new" then
      if should_prompt then
        ask_new_session(session, accelerator)
      else
        new_session(session or "nvim", accelerator or "")
      end
      return
    end
    vim.notify("Reusing active Colab session: " .. item.name)
    ui.colab({ op = "colab_connect", session = item.name })
  end)
end

function M.create_or_reuse(session, accelerator, should_prompt)
  client.request({ op = "colab_sessions" }, function(response)
    if not response.ok or not response.data.success then
      local output = response.ok and response.data.output or response.error
      require("notebook_rs.panel").show(output or "Could not check active Colab sessions", true,
        "Could not check active Colab sessions")
      return
    end
    local active = response.data.sessions or {}
    if #active > 0 then
      choose_session(active, session, accelerator, should_prompt)
    elseif response.data.unmanaged then
      local output = response.data.output or ""
      require("notebook_rs.panel").show(
        output .. "\nAn active assignment has no local Colab CLI session name and cannot be reused.",
        true, "Colab has an active session that this CLI cannot select")
    elseif should_prompt then
      ask_new_session(session, accelerator)
    else
      new_session(session or "nvim", accelerator or "")
    end
  end)
end

local function create()
  M.create_or_reuse(nil, nil, true)
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
  { key = "a", label = "Add code cell above", group = "Notebook",
    run = function() vim.cmd.NotebookCellNewAbove() end },
  { key = "b", label = "Add code cell below", group = "Notebook",
    run = function() vim.cmd.NotebookCellNewBelow() end },
  { key = "x", label = "Delete cell", group = "Notebook",
    run = function() vim.cmd.NotebookCellDelete() end },
  { key = "l", label = "Log in", run = ui.login },
  { key = "n", label = "Create session or reuse active one", run = create },
  { key = "c", label = "Connect to session", run = connect },
  { key = "s", label = "Connection status", run = command("colab_status") },
  { key = "p", label = "List sessions", run = command("colab_sessions") },
  { key = "r", label = "Restart session", run = command("colab_restart") },
  { key = "u", label = "Open session URL", run = command("colab_url") },
  { key = "X", label = "Stop session", run = command("colab_stop") },
  { key = "B", label = "Use Colab backend", run = function() ui.backend("colab") end },
  { key = "L", label = "Use local backend", run = function() ui.backend("local") end },
  { key = "i", label = "Install packages", run = install },
  { key = "f", label = "List remote files", run = list_files },
  { key = "U", label = "Upload file", run = upload },
  { key = "D", label = "Download file", run = download },
}

function M.open()
  vim.ui.select(actions, {
    prompt = "Notebook cells and Colab connections",
    format_item = function(item) return item.key .. "  " .. (item.group or "Colab") .. ": " .. item.label end,
  }, function(item)
    if item then
      item.run()
    end
  end)
end

function M.attach(buf)
  vim.keymap.set("n", "<leader>cc", M.open, { buffer = buf, desc = "Notebook cells and Colab connections" })
  for _, item in ipairs(actions) do
    vim.keymap.set("n", "<leader>cc" .. item.key, item.run, {
      buffer = buf,
      desc = (item.group or "Colab") .. ": " .. item.label,
    })
  end
end

return M
