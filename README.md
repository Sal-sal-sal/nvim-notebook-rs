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
:write
```

The notebook buffer uses `# %% [code] id=...` cell markers.
Markdown and raw cell lines are prefixed with `# `.
Move the cursor into a code cell before `:NotebookRun`.
Use `:write` to save edits to the original `.ipynb` file.
Unchanged cells keep their metadata and outputs; editing a code cell clears its stale output.

For Colab, authorize in an interactive terminal and select a named session:

```vim
:NotebookColabLogin
:NotebookColabNew training T4
:NotebookBackend colab
:NotebookRun
:NotebookColabStatus
:NotebookColabStop
```

Use `:NotebookColabConnect training` to select a session that already exists.
Other commands are `:NotebookColabSessions` and `:NotebookBackend local`.
GPU allocation depends on your Colab account and availability.

Local Python state is shared by notebooks in one Neovim process.
Local execution accepts standard Python syntax; IPython magic commands need the Colab backend.
The worker runs one request at a time, so a long ML cell delays subsequent requests.
Saving uses a separate short-lived worker and remains available during execution.
Images and rich HTML outputs are not rendered in this first version; text appears in a bottom output panel.

## Architecture and tests

`src/notebook/` owns notebook parsing and preservation of unchanged cell metadata and outputs.
`src/runtime/` owns the persistent local Python process and Colab CLI subprocesses.
`src/protocol.rs` exposes a line-delimited JSON protocol to the minimal Lua Neovim interface in `lua/notebook_rs/`.

`cargo test` covers notebook round trips, local kernel state, and the worker talking to a fake Colab CLI.
The headless Neovim smoke test creates a notebook, saves it, and runs two cells with shared Python state.
GitHub Actions runs formatting, Clippy, tests, a release build, and the Neovim smoke test on macOS and Linux.
The Colab test uses a fake CLI so CI never needs account credentials or allocates a paid runtime.
