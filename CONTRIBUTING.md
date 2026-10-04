# Contributing

Install Rust, Neovim, and Python 3, then clone the repository.
Install Matplotlib in the Python interpreter used for tests with `python3 -m pip install matplotlib`.
Build with `cargo build --release --locked`.

Run the complete local verification before sending a change:

```sh
python3 scripts/verify.py
```

Use `NVIM_NOTEBOOK_PYTHON` to select a Python environment for local cell execution.
The test suite uses a fake Colab executable, so Google authentication is unnecessary.
See [architecture](docs/architecture.md) for module ownership and the worker protocol.

## Reporting a bug

Include Neovim, Rust worker, Python, and Colab CLI versions when relevant.
Provide a minimal notebook and the exact commands that reproduce the problem.
Attach the output of `:checkhealth notebook_rs`.
Remove credentials, personal data, and private notebook contents before sharing logs.
Distinguish local execution from Colab execution using `:NotebookBackend` and the statusline.

## Pull requests

Keep each change focused and preserve notebook metadata and outputs.
Reproduce a bug through the affected user workflow before fixing it.
Add regression coverage when notebook data, execution, or routing is affected.
Document new commands and settings in the README and Neovim help.
Run formatting, Clippy, worker tests, and Neovim tests through the verification script.
The supported operating systems are Linux and macOS.
