# Releases

GitHub hosts the Lua plugin source and native Rust worker downloads.
The repository is not published as a crates.io package.

## Using a release

Install the plugin with the GitHub `lazy.nvim` specification in the README.
Its build hook compiles the worker for your machine with the committed dependency lockfile.
Alternatively, download the archive matching your operating system and CPU architecture from [GitHub Releases](https://github.com/Sal-sal-sal/nvim-notebook-rs/releases).
Verify its SHA-256 checksum against the accompanying `.sha256` file before extracting it.
Set `vim.g.notebook_rs_bin` to the extracted worker's absolute path, then install the Lua plugin source as usual.
The worker archive includes the license, README, and Neovim help files.
Python remains a separate requirement for local execution, and the Colab CLI remains a separate requirement for remote execution.

## Publishing a release

Update the package version in `Cargo.toml` and regenerate `Cargo.lock` through Cargo.
Run `python3 scripts/verify.py` and wait for the CI and Compatibility workflows to pass on the intended commit.
Create an annotated `v<version>` tag whose version matches `Cargo.toml`.
Push the tag to trigger the Release workflow.
The workflow verifies the tag, runs tests, and builds native workers for Linux and macOS on x86_64 and ARM64.
It publishes archives and checksums only after the full Linux and macOS verification jobs pass.
A rerun uploads replacement assets to the existing tagged release.

## Validation boundaries

CI covers the worker and real Neovim workflows with a fake Colab CLI.
Live authenticated Colab execution is an optional separate check and is never required for an unauthenticated installation.
The release does not include Python packages, Google credentials, or the Colab CLI.
