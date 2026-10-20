#!/usr/bin/env python3
"""Check real completion popups with a configured Neovim and optional pynvim."""
import os
from pathlib import Path
import tempfile
import time

import pynvim


def wait_for(check, message, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.1)
    raise AssertionError(message)


config = os.environ.get("NOTEBOOK_RS_NVIM_CONFIG", str(Path.home() / ".config/nvim/init.lua"))
nvim = pynvim.attach("child", argv=["nvim", "--embed", "-u", config])
try:
    nvim.ui_attach(110, 35, rgb=True)
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / "completion.ipynb")
        nvim.command("NotebookNew " + nvim.funcs.fnameescape(path))
        wait_for(lambda: nvim.exec_lua(
            'local cs=vim.lsp.get_clients({bufnr=0,name="pyright"}); return #cs==1 and cs[1].initialized'
        ), "Python LSP did not attach")
        for imported, prefix, typed, expected in (
            ("import torch", "torch", "ten", "tensor"),
            ("import torchvision", "torchvision.datasets", "MN", "MNIST"),
            ("from torchvision import transforms", "transforms", "Com", "Compose"),
            ("from torchvision.transforms import v2", "v2", "ToI", "ToImage"),
            ("import tensorflow as tf", "tf", "con", "constant"),
            ("import tensorflow as tf", "tf.keras.layers", "De", "Dense"),
        ):
            nvim.input("<Esc>")
            wait_for(lambda: nvim.funcs.mode() == "n", "could not leave insert mode")
            nvim.current.buffer[:] = ["# %% [code] id=ui", imported, prefix]
            nvim.current.window.cursor = (3, len(prefix) - 1)
            nvim.input("A." + typed)
            try:
                wait_for(lambda: nvim.exec_lua(
                    'local c=require("blink.cmp"); if not c.is_menu_visible() then return false end '
                    'for _,i in ipairs(c.get_items()) do if i.label==... then return true end end return false',
                    expected,
                ), prefix + "." + expected + " popup missing")
            except AssertionError:
                print(nvim.exec_lua(
                    'local c=require("blink.cmp"); return {mode=vim.fn.mode(),line=vim.api.nvim_get_current_line(),'
                    'visible=c.is_menu_visible(),items=vim.tbl_map(function(i) return i.label end,'
                    'vim.list_slice(c.get_items() or {},1,10)),'
                    'messages=vim.api.nvim_exec2("messages",{output=true}).output}'
                ), flush=True)
                raise
            print(prefix + "." + expected + ": automatic popup passed", flush=True)
        for imported, expression in (
            ("from torchvision import datasets", "datasets.MNIST"),
            ("from torch import nn", "nn.Linear"),
        ):
            nvim.input("<Esc>")
            wait_for(lambda: nvim.funcs.mode() == "n", "could not leave insert mode")
            wait_for(lambda: not nvim.exec_lua('return require("blink.cmp").is_signature_visible()'),
                     "previous parameter popup stayed visible")
            nvim.current.buffer[:] = ["# %% [code] id=ui", imported, expression]
            nvim.current.window.cursor = (3, len(expression) - 1)
            nvim.input("A(")
            wait_for(lambda: nvim.exec_lua('return require("blink.cmp").is_signature_visible()'),
                     expression + " parameter popup missing")
            print(expression + "(: automatic parameter popup passed", flush=True)
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass
    nvim.close()
