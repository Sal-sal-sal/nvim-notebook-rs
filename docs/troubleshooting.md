# Troubleshooting

Start with `:checkhealth notebook_rs`.
Record the execution route shown by the statusline before changing packages or Python environments.

## Worker unavailable

Run `cargo build --release --locked` from the plugin directory.
The extension discovers `target/release/nvim-notebook-rs`, `target/debug/nvim-notebook-rs`, or a worker on `PATH`.
Set `vim.g.notebook_rs_bin` to an executable path when using a downloaded release binary.
Restart Neovim after replacing a worker that is already running.

## Another plugin opens notebooks

Disable the other plugin's `*.ipynb` handler.
A notebook opened by this extension has `buftype=acwrite` and `filetype=python`.
An invalid notebook opens in a read-only error buffer and the original file remains intact.

## Colab appears connected but imports fail

Check whether the statusline says `run: colab` or `run: local`.
Use `:NotebookBackend colab` to execute on the selected remote session.
A successful connection selects Colab for its originating notebook.
A Python `ModuleNotFoundError` describes the interpreter that actually ran the cell.

## TLS or closed WebSocket errors

Check the executable set by `NVIM_NOTEBOOK_COLAB`.
Set `NVIM_NOTEBOOK_COLAB_CA_BUNDLE` to a trusted readable CA bundle if your CLI requires it.
Restart Neovim after changing executable paths or worker environment variables.
Use `:NotebookColabStatus` to test the selected session with a real kernel probe.
Authenticate interactively with `:NotebookColabLogin` when the CLI requests login.

## Saves and execution results

Use `:write` after execution to store structured outputs in the notebook.
Reopen a notebook that changed on disk before saving it again.
Keep valid `# %% [code|markdown|raw] id=...` markers when editing source.
Duplicate ids or malformed markers block saving and execution.
Local `input()` and IPython magic commands are unsupported; use Colab for magics.
