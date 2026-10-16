# -*- coding: utf-8 -*-
"""三段差分: P0 基线 -> P1 桥模式16帧 -> P2 E模式16帧。"""
import csv

B = r"D:\FPGA\prj\project_11\out"

def load(p):
    rows = list(csv.reader(open(p, encoding="utf-8", errors="replace")))
    hdr = [h.strip() for h in rows[0]]
    for r in rows[1:]:
        if r and r[0].strip().replace(".", "").isdigit():
            return hdr, r
    return hdr, None

def grabs(ila):
    return [load(f"{B}\\cmp_p{k}_{ila}.csv") for k in (0, 1, 2)]

for ila in ("i1", "i2", "i3"):
    hs, rows = zip(*grabs(ila))
    hdr = hs[0]
    print("=" * 78)
    print(ila.upper())
    print("%-28s %10s %10s %10s   %s" % ("probe", "P0", "P0->P1桥", "P1->P2E", ""))
    for i, name in enumerate(hdr):
        if name in ("Sample in Buffer", "Sample in Window", "TRIGGER"):
            continue
        vals = []
        for r in rows:
            try:
                vals.append(int(r[i].strip(), 16))
            except ValueError:
                vals.append(None)
        if None in vals:
            continue
        d01 = vals[1] - vals[0]
        d12 = vals[2] - vals[1]
        if d01 == 0 and d12 == 0:
            continue
        print("%-28s %10d %10d %10d   %s" % (name, vals[0], d01, d12,
                                             "★桥有效/E无效" if (d01 and not d12) else ("★E独有" if (d12 and not d01) else "")))
