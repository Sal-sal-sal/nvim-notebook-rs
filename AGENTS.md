# Working on nvim-notebook-rs

This repository contains the standalone Neovim notebook extension.
The public source repository is https://github.com/Sal-sal-sal/nvim-notebook-rs.
Rust owns notebook preservation, cell edits, execution, and the JSON worker protocol.
Lua owns Neovim buffers, presentation, mappings, and commands.
Keep business logic in the Rust modules and Neovim integration in the Lua modules.

## Changes

Preserve existing uncommitted changes and stage explicit paths.
Reproduce bugs through a notebook opened in Neovim before fixing them.
Keep source files under 200 lines and functions under 100 lines.
Group a scenario into its own directory when it requires more than three files.
Do not edit generated files or CHANGELOG.md manually.
Put each full Markdown sentence on its own physical line.
Use a plain dash instead of an em dash.
Do not add agent coauthors to commits.

## Verification

Run `python3 scripts/verify.py` before publishing changes.
CI uses a fake Colab CLI and never requires Google credentials.
An authenticated live Colab test is separate from the fake CLI checks.
Never store authorization codes or OAuth tokens in this repository.
Keep notebook metadata and unaffected cell outputs intact.
Do not restart the user's running Neovim instance during publication work.
