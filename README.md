# nvim-notebook-rs

A standalone Neovim notebook extension with a Rust worker.
It opens editable Jupyter `.ipynb` notebooks as Python cell text, keeps a local Python kernel alive between runs, and can execute cells in a named Google Colab CLI session.

## Requirements

- Rust 1.85 or newer to build the worker.
- Neovim 0.10 or newer.
- Python 3 on `PATH` for local execution.
- The official Google Colab CLI for remote execution.

The CLI connection uses `colab new`, `colab status`, `colab exec`, and `colab stop`.
Connecting, creating, and checking a session execute a short `pass` cell so a stale CLI session with a closed kernel is shown as an error.
The CLI manages Google authentication and remote session state.
The extension does not read or store OAuth tokens.

## Install

Add the public repository to your `lazy.nvim` configuration:

```lua
return {
  {
    "Sal-sal-sal/nvim-notebook-rs",
    build = "cargo build --release --locked",
    config = function()
      require("notebook_rs").setup()
    end,
  },
}
```

For a local checkout, use `dir = "/absolute/path/to/nvim-notebook-rs"` in place of the repository name.
Build a standalone checkout with `cargo build --release --locked`.

The plugin finds the binary in its `target/release` directory.
Set `vim.g.notebook_rs_bin` to a custom binary path if needed.
Set `NVIM_NOTEBOOK_PYTHON` and `NVIM_NOTEBOOK_COLAB` to override the Python or Colab CLI executables.
If another plugin registers `BufReadCmd` for `*.ipynb`, disable its notebook handler so one plugin owns opening and saving these files.
Configure the notebook in Lua:

```lua
require("notebook_rs").setup({
  distance_between_cells = 2,
  nootbook_hidden_id_line = true,
  nootbook_result = "nootbook",
})
```

`nootbook_hidden_id_line = true` hides `# %% [code] id=...` from the editor without removing it from the notebook.
Neovim 0.11 and newer conceal the whole line; Neovim 0.10 conceals its text but leaves an empty line.
Set it to `false` to show the marker lines while editing.
`nootbook_result` accepts `"nootbook"` for inline cell output, `"window"` for a bottom output window, or `"hidden"` for no displayed result.
Execution results are still saved to `.ipynb` in every mode.
The option names intentionally use `nootbook` as shown above.

## Use

```vim
:NotebookNew experiment.ipynb
:NotebookOpen experiment.ipynb
:edit experiment.ipynb
:NotebookRun
:NotebookRunAll
:NotebookCellNext
:NotebookCellPrev
:NotebookCellGoto 3
:NotebookCellNew markdown
:NotebookCellNewAbove
:NotebookCellNewBelow
:NotebookCellMove up
:NotebookCellDelete
:NotebookRestart
:write
```

The notebook buffer uses `# %% [code] id=...` cell markers.
If a marker is mistyped, for example `}d=` instead of `id=`, execution stops with the source line number instead of treating that code as part of the previous cell.
Opening an `.ipynb` through a file picker or `:edit` loads the same editable cell view.
An invalid `.ipynb` opens a read-only error view so an accidental save cannot replace the original file.
Colored borders separate code, Markdown, and raw cells, and the current cell has an arrow in the sign column.
Two virtual blank lines separate cells by default; they do not change the saved notebook.
Code cell borders show `RUNNING`, `DONE`, or `ERROR` during execution.
Markdown and raw cell lines are prefixed with `# `.
Move the cursor into a code cell before `:NotebookRun`.
Inside a notebook, `<leader>jc` jumps to the next cell and `<leader>kc` jumps to the previous one.
Use `<leader>3b` to jump to cell 3, or `<leader>12b` for cell 12; cell numbers start at 1 and include code, Markdown, and raw cells.
`<leader>rc` or `<leader>rr` runs the current code cell, and `<leader>ra` runs all code cells.
`<leader>cca` inserts a code cell above the current cell, `<leader>ccb` inserts one below it, and `<leader>ccx` deletes the current cell.
The matching commands are `:NotebookCellNewAbove`, `:NotebookCellNewBelow`, and `:NotebookCellDelete`.
Pass `markdown` or `raw` to either insertion command if you need another cell type.
These mappings are buffer-local and use your Neovim `mapleader` setting.
With the default `nootbook_result = "nootbook"`, Python and Colab output and tracebacks appear below their cells.
These are virtual lines in Neovim, so they do not become Python source; `:write` stores them as structured notebook outputs.
Saved output appears again when the notebook is reopened, and changing a cell clears only its own stale output.
Images and HTML appear as inline placeholders; use `:NotebookOpenArtifact` to open a generated file after a run.
Use `:write` to save edits to the original `.ipynb` file.
Cell results are held in the buffer until `:write` saves them to the original `.ipynb` file.
Unchanged cells keep their metadata and outputs; editing a code cell clears its stale output.
Each notebook has its own local Python process, and `:NotebookRestart` resets that process.

For Colab, authorize in an interactive terminal and select a named session:

```vim
:NotebookColabLogin
:NotebookColabNew training T4
:NotebookBackend colab
:NotebookRun
:NotebookColabStatus
:NotebookColabRestart
:NotebookColabInstall torch numpy
:NotebookColabUpload data.csv /content/data.csv
:NotebookColabList /content
:NotebookColabDownload /content/data.csv copy.csv
:NotebookColabURL
:NotebookColabStop
```

Use `:NotebookColabConnect training` to select a session that already exists.
When named active sessions exist, `:NotebookColabNew` and `<leader>ccn` show them alongside a `Create a new Colab session` option.
Choose an existing session to connect, or choose the new-session option to create another one; `<leader>ccn` then asks for its name and optional GPU or TPU.
A CLI entry marked `[?]` has no local name and cannot be selected by the plugin.
Other commands are `:NotebookColabSessions` and `:NotebookBackend local`.
Press `<leader>cc` inside a notebook to choose a cell or Colab action from a menu.
Direct shortcuts use the same prefix:

| Shortcut | Action |
| --- | --- |
| `<leader>ccl` | Log in |
| `<leader>ccn` | Choose an active session or create one |
| `<leader>ccc` | Connect to a session |
| `<leader>ccs` | Check connection status |
| `<leader>ccp` | List sessions |
| `<leader>ccr` | Restart the session |
| `<leader>ccu` | Get the session URL |
| `<leader>ccX` | Stop the session |
| `<leader>ccB` / `<leader>ccL` | Select Colab / local backend |
| `<leader>cci` | Install packages |
| `<leader>ccf` | List remote files |
| `<leader>ccU` / `<leader>ccD` | Upload / download a file |

If the CLI asks for an authorization code, complete `:NotebookColabLogin` first.
Enter authorization codes only in that terminal, never in a notebook cell or chat.
GPU allocation depends on your Colab account and availability.
For a TPU, use `:NotebookColabNew training TPU:v6e1` or `TPU:v5e1`.

To show the selected Colab connection in a bottom `lualine` statusline, add this component to its `lualine_x` section:

```lua
{
  function() return require("notebook_rs.status").component() end,
  cond = function() return vim.b.notebook_rs_path ~= nil end,
  color = function() return require("notebook_rs.status").color() end,
}
```

The segment shows the selected session after a successful CLI connection, and changes to an error state when the CLI or kernel check fails.
It rechecks a connected session after five minutes when focus returns or the notebook is idle.

Local execution accepts standard Python syntax; IPython magic commands need the Colab backend.
Interactive `input()` is not supported in the local worker and raises `EOFError` without consuming the worker protocol.
The worker runs one request at a time, so a long ML cell delays subsequent requests.
Saving uses a separate short-lived worker and remains available during execution.
Set `nootbook_result = "window"` to show the full result of each run in the bottom output panel.
Set `nootbook_result = "hidden"` to suppress the run output view while keeping notebook results available for saving.
Local Matplotlib plots and Colab images and HTML are saved to temporary files; `:NotebookOpenArtifact` opens the latest one, or pass an index such as `:NotebookOpenArtifact 1`.
Image links in the output panel can render inside Neovim when a compatible Markdown image plugin is installed.
The installed Colab CLI may exit with code zero for a Python exception, so the extension reads the CLI's output notebook to detect failed cells.
`RunAll` stops at the first failed cell.

## Architecture and tests

`src/notebook/` owns notebook parsing, cell edits, and preservation of unchanged cell metadata and outputs.
`src/runtime/` owns the persistent local Python process and Colab CLI subprocesses.
`src/protocol.rs` exposes a line-delimited JSON protocol to the minimal Lua Neovim interface in `lua/notebook_rs/`.

`cargo test` covers notebook round trips, local kernel state and plots, Colab file operations, authentication failure, and the worker talking to a fake Colab CLI.
The fake CLI exits successfully after a Python error, matching the installed CLI, so tests prove structured error detection.
The headless Neovim smoke tests cover execution, cell edits, insertion above and below, navigation shortcuts, Colab actions, inline tracebacks, and numeric cell targets.
GitHub Actions runs formatting, Clippy, tests, a release build, and the Neovim smoke tests on macOS and Linux.
The Colab test uses a fake CLI so CI never needs account credentials or allocates a paid runtime.
