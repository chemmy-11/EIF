# -*- coding: utf-8 -*-
"""Fix literal backslash-n sequences accidentally written into BUILD_STATUS.md."""
import io
import os

p = r"D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\BUILD_STATUS.md"
t = io.open(p, encoding="utf-8", newline="").read()
n1 = t.count("\\n")
t = t.replace("\\n", "\n")
n2 = t.count("\\r")
t = t.replace("\\r", "\r")
io.open(p + ".tmp", "w", encoding="utf-8", newline="").write(t)
os.replace(p + ".tmp", p)
print("replaced backslash-n:", n1, "backslash-r:", n2, "size:", os.path.getsize(p))
