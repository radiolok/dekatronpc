#!/usr/bin/env python3
"""Run a SPICE deck through libngspice (the library KiCad ships); no ngspice binary needed.

usage: ngrun.py deck.cir [ngspice command ...]    (default command: run)
"""
import ctypes
import sys

lib = ctypes.CDLL("libngspice.so.0")
OUT = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_void_p)
EXIT = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.c_bool, ctypes.c_bool, ctypes.c_int, ctypes.c_void_p)


def _print(s, _id, _user):
    t = s.decode(errors="replace")
    for pre in ("stdout ", "stderr "):
        if t.startswith(pre):
            t = t[len(pre):]
    print(t)
    return 0


cb_out = OUT(_print)
cb_exit = EXIT(lambda *a: 0)
lib.ngSpice_Init(cb_out, None, cb_exit, None, None, None, None)
lib.ngSpice_Command(f"source {sys.argv[1]}".encode())
for c in sys.argv[2:] or ["run"]:
    lib.ngSpice_Command(c.encode())
