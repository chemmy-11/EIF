# -*- coding: utf-8 -*-
"""E 轮前后 ILA1/ILA3 差分 (含 Aurora B 回程判定)。"""
import csv, glob, os

def load(p):
    rows = list(csv.reader(open(p, encoding="utf-8", errors="replace")))
    hdr = [h.strip() for h in rows[0]]
    for r in rows[1:]:
        if r and r[0].strip().replace(".", "").isdigit():
            return hdr, r
    return hdr, None

base = r"D:\FPGA\prj\project_11\out"
pairs = [
    ("ILA1", f"{base}\\jb31b_diff_i1_before.csv", f"{base}\\jb31b_diff_i1_after.csv"),
    ("ILA3", f"{base}\\jb31b_diff_i3_before.csv", f"{base}\\jb31b_diff_i3_after.csv"),
]
for tag, pb, pa in pairs:
    hb, b = load(pb)
    ha, a = load(pa)
    print("=" * 60)
    print("%s  (cols=%d)" % (tag, len(hb)))
    for i, name in enumerate(hb):
        if name in ("Sample in Buffer", "Sample in Window", "TRIGGER"):
            continue
        vb, va = b[i].strip(), a[i].strip()
        try:
            d = int(va, 16) - int(vb, 16)
        except ValueError:
            d = None
        print("  %-28s %-10s -> %-10s %s" % (name, vb, va, ("delta=%d" % d) if d is not None else ""))
