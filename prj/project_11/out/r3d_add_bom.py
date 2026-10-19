# -*- coding: utf-8 -*-
"""CI fix: ensure UTF-8 BOM on the new PowerShell scripts (PS 5.1 + Chinese comments)."""
import io
import sys

paths = [
    r"D:\FPGA\prj\project_11\out\r3c_sweep2_retry.ps1",
    r"D:\FPGA\prj\project_11\out\r3d_synth_retry.ps1",
]
for p in paths:
    raw = io.open(p, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"):
        print("BOM already:", p)
        continue
    io.open(p, "wb").write(b"\xef\xbb\xbf" + raw)
    print("BOM added:", p, "bytes=", len(raw) + 3)
