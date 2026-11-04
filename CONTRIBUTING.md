# Contributing

## Set up

Use Linux or macOS with Rust 1.85 or newer, Neovim 0.10 or newer, and Python 3.
Clone the repository and run these commands from its root.

```sh
cargo build --release --locked
demo_dir=$(mktemp -d)
cp examples/local.ipynb "$demo_dir/local.ipynb"
nvim --clean --cmd 'set runtimepath+=.' \
  --cmd 'lua require("notebook_rs").setup()' "$demo_dir/local.ipynb"
```

Try `:NotebookRunAll` and `:write` in the copied notebook.
See the [architecture overview](docs/architecture.md) to find the code that owns a feature.

## Verify a change

Reproduce bugs through Neovim first and add a regression test when existing coverage misses the failure.
Put editor workflow tests in `tests/nvim_*.lua` and worker protocol tests in `tests/*_e2e.rs`.

```sh
python3 -m venv target/verify-venv
target/verify-venv/bin/python -m pip install matplotlib
target/verify-venv/bin/python scripts/verify.py
```

The script runs formatting, Clippy, Rust tests, a release build, and headless Neovim tests.
Install Pyright with `npm install --global pyright@1.1.411` to include the completion test.
Colab checks use a fake CLI and run without a Google account.

## Report a bug

Include the Neovim and worker versions, the local or Colab backend, the exact steps, and a minimal example notebook.
Attach `:checkhealth notebook_rs` and relevant logs after removing credentials and private data.

## Submit a change

Keep each change focused and preserve notebook metadata and outputs from unaffected cells.
Update Neovim help when commands or options change.
In the pull request, summarize the user-visible behavior and list the checks you ran.
