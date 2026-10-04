# Architecture

The Rust worker owns notebook data and execution.
Neovim calls it through a line-delimited JSON protocol and presents cell source and results.

| Module | Responsibility |
| --- | --- |
| `src/notebook/percent.rs` | Parse cell markers and select code cells |
| `src/notebook/edit.rs` | Insert, delete, and move cells |
| `src/notebook/store.rs` | Preserve notebook JSON and save atomically |
| `src/notebook/results.rs` | Apply results only to matching source |
| `src/notebook/view.rs` | Convert stored notebooks into editable lines |
| `src/runtime/local.rs` | Persistent Python process for each notebook |
| `src/runtime/colab.rs` | Named Colab CLI sessions and operations |
| `src/runtime/colab_notebook.rs` | Decode remote structured outputs |
| `src/runtime/colab_sessions.rs` | Parse reusable session names |
| `src/protocol.rs` | Dispatch requests and collect execution results |
| `lua/notebook_rs/` | Buffers, routing, commands, display, and diagnostics |

## Execution

A run request carries cell lines, cursor position, notebook path, and backend.
The worker parses cells, selects the requested code, and executes cells in order.
Local interpreters are keyed by notebook path so variables remain isolated between notebooks.
Colab operations invoke the CLI directly and let it manage authentication.
Results include cell ids, source, outputs, execution counts, and artifact paths.
Lua stores these results in memory and marks the notebook as modified.
A save request applies results only when their source still matches the cell.
Changing a code cell clears stale stored output while preserving other cells.

## Lifetime and concurrency

The interactive worker processes requests sequentially.
A separate short-lived worker handles saves during long cell execution.
The worker removes its temporary artifacts when it exits.
Restarting a local notebook removes only that notebook's persistent interpreter.
The Colab connection state and each buffer's execution backend are separate values.

## Testing

Worker integration tests drive the executable through its JSON protocol.
Neovim tests exercise notebook commands, buffer state, output, and saves.
Fake Colab tests cover routing and CLI behavior without authentication.
`tests/nvim_live_colab.lua` separately validates an authenticated remote kernel.
