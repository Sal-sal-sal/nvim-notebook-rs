# nvim-notebook-rs

A standalone Neovim notebook extension with a Rust worker.
It opens editable Jupyter `.ipynb` notebooks as Python cell text, keeps a local Python kernel alive between runs, and can execute cells in a named Google Colab CLI session.

## Requirements

- Rust 1.85 or newer to build the worker.
- Neovim 0.10 or newer.
- Python 3 on `PATH` for local execution.
- The official Google Colab CLI for remote execution.

The CLI connection uses `colab new`, `colab status`, `colab exec`, and `colab stop`.
The CLI manages Google authentication and remote session state.
The extension does not read or store OAuth tokens.

## Install

Clone this repository outside your Neovim configuration and build it:

```sh
cargo build --release
```

Add the repository as a local plugin in a `lazy.nvim` configuration:

```lua
return {
  {
    dir = "/absolute/path/to/nvim-notebook-rs",
    name = "nvim-notebook-rs",
    build = "cargo build --release",
  },
}
```

The plugin finds the binary in its `target/release` directory.
Set `vim.g.notebook_rs_bin` to a custom binary path if needed.
Set `NVIM_NOTEBOOK_PYTHON` and `NVIM_NOTEBOOK_COLAB` to override the Python or Colab CLI executables.

## Use

```vim
:NotebookNew experiment.ipynb
:NotebookOpen experiment.ipynb
:NotebookRun
:NotebookRunAll
:NotebookCellNew markdown
:NotebookCellMove up
:NotebookCellDelete
:NotebookRestart
:write
```

The notebook buffer uses `# %% [code] id=...` cell markers.
Markdown and raw cell lines are prefixed with `# `.
Move the cursor into a code cell before `:NotebookRun`.
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
Other commands are `:NotebookColabSessions` and `:NotebookBackend local`.
If the CLI asks for an authorization code, complete `:NotebookColabLogin` first.
Enter authorization codes only in that terminal, never in a notebook cell or chat.
GPU allocation depends on your Colab account and availability.
For a TPU, use `:NotebookColabNew training TPU:v6e1` or `TPU:v5e1`.

Local execution accepts standard Python syntax; IPython magic commands need the Colab backend.
Interactive `input()` is not supported in the local worker and raises `EOFError` without consuming the worker protocol.
The worker runs one request at a time, so a long ML cell delays subsequent requests.
Saving uses a separate short-lived worker and remains available during execution.
Colab text results and tracebacks appear in a bottom output panel.
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
The headless Neovim smoke test creates a notebook, saves it, runs two cells with shared state, and edits cell order.
GitHub Actions runs formatting, Clippy, tests, a release build, and the Neovim smoke test on macOS and Linux.
The Colab test uses a fake CLI so CI never needs account credentials or allocates a paid runtime.
