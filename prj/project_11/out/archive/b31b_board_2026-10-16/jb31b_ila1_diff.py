# -*- coding: utf-8 -*-
"""ILA1 E 轮前后差分: 取 radix 行之后的第一行数据。"""
import csv

def load(p):
    rows = list(csv.reader(open(p, encoding="utf-8", errors="replace")))
    hdr = [h.strip() for h in rows[0]]
    data = None
    for r in rows[1:]:
        if r and r[0].strip().replace(".", "").isdigit():
            data = r
            break
    return hdr, data

hb, b = load(r"D:\FPGA\prj\project_11\out\jb31b_ila1_before.csv")
ha, a = load(r"D:\FPGA\prj\project_11\out\jb31b_ila1_after.csv")
print("rows_found: before=%s after=%s" % (b is not None, a is not None))
print("--- 数值差分 ---")
for i, name in enumerate(hb):
    if name in ("Sample in Buffer", "Sample in Window", "TRIGGER"):
        continue
    vb, va = b[i].strip(), a[i].strip()
    try:
        d = int(va, 16) - int(vb, 16)
    except ValueError:
        d = None
    print("%-28s %-10s -> %-10s %s" % (name, vb, va, ("delta=%d" % d) if d is not None else ""))
