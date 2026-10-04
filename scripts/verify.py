#!/usr/bin/env python3
"""Run the same credential-free checks locally and in CI."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run(command, env=None, timeout=600):
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, env=env, timeout=timeout, check=True)


def main():
    run(["cargo", "fmt", "--all", "--check"])
    run(["cargo", "clippy", "--all-targets", "--locked", "--", "-D", "warnings"])
    run(["cargo", "test", "--locked"])
    run(["cargo", "build", "--release", "--locked"])
    env = os.environ.copy()
    env.update({
        "NOTEBOOK_RS_ROOT": str(ROOT),
        "NOTEBOOK_RS_BIN": str(ROOT / "target/release/nvim-notebook-rs"),
        "NVIM_NOTEBOOK_PYTHON": sys.executable,
    })
    tests = sorted((ROOT / "tests").glob("nvim_*.lua"))
    for test in tests:
        if test.name == "nvim_live_colab.lua":
            continue
        run(["nvim", "--headless", "--clean", "-u", "NONE", "-l", str(test)], env, 180)
    print("All worker and Neovim checks passed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError) as error:
        print(f"Verification failed: {error}", file=sys.stderr)
        sys.exit(1)
