# -*- coding: utf-8 -*-
"""解析 ILA CSV v2: dbg_lite_*/dbg_cmd_*/dbg_mem_u_* 触发行值"""
import csv, io

path = r"D:\FPGA\prj\project_11\out\jb1_ic2_ila_capture.csv"
with io.open(path, "r", encoding="utf-8", errors="replace") as f:
    rows = list(csv.reader(f))

hdr = rows[0]
want = ["dbg_lite_owner", "dbg_lite_mode", "dbg_lite_slot[7:0]",
        "dbg_lite_trig[15:0]", "dbg_lite_exec[15:0]",
        "dbg_cmd_mode", "dbg_cmd_slot[7:0]", "dbg_cmd_exec[15:0]",
        "dbg_cmd_trig[15:0]", "dbg_mem_u_wr[15:0]", "dbg_mem_u_rd[15:0]",
        "dbg_mem_u_drop[15:0]"]
idx = {h: i for i, h in enumerate(hdr)}

# TRIGGER 列=1 的行; 找不到则取中间行
tri_col = idx["TRIGGER"]
tri_row = None
for r in rows[2:]:
    if len(r) > tri_col and r[tri_col] == "1":
        tri_row = r
        break
if tri_row is None:
    tri_row = rows[len(rows) // 2]
    print("WARN: no TRIGGER row, using mid row")

print("=== ILA @ TRIGGER (稳态心跳) ===")
for k in want:
    print("%-22s = %s" % (k, tri_row[idx[k]]))
