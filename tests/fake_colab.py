#!/usr/bin/env python3
import base64
import json
import sys
from pathlib import Path

args = sys.argv[1:]
command = args[0]

if command == "exec":
    path = Path(args[args.index("--file") + 1])
    notebook = json.loads(path.read_text())
    cell = notebook["cells"][0]
    source = cell["source"]
    if "raise ValueError" in source:
        cell["outputs"] = [{"output_type": "error", "ename": "ValueError",
                            "evalue": "bad cell", "traceback": ["ValueError: bad cell"]}]
    elif "plot()" in source:
        png = base64.b64encode(bytes.fromhex(
            "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
            "0000000b49444154789c636000020000050001a5f645400000000049454e44ae426082"
        )).decode()
        cell["outputs"] = [{"output_type": "display_data", "data": {"image/png": png}, "metadata": {}}]
    else:
        cell["outputs"] = [{"output_type": "stream", "name": "stdout", "text": "remote:" + source}]
    cell["execution_count"] = 1
    path.with_name(path.stem + "_output.ipynb").write_text(json.dumps(notebook))
    sys.exit(0)  # The installed CLI also exits zero for a Python cell exception.

if command == "download":
    Path(args[-1]).write_text("downloaded from " + args[-2])

if command == "upload" and not Path(args[-2]).is_file():
    sys.exit(2)

if command in {"status", "new", "stop", "sessions", "restart-kernel", "url",
               "install", "upload", "download", "ls"}:
    print(" ".join(args))
    sys.exit(0)

sys.exit(2)
