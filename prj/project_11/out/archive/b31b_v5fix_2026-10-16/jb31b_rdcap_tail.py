# -*- coding: utf-8 -*-
"""rdcap_tail.py — 复核两条发射流的首尾与总长(确认 DROP=8 丢掉的正是前导+SFD)。"""
import csv

B = r"D:\FPGA\prj\project_11\out"


def stream(path):
    rows = list(csv.reader(open(path, encoding="utf-8", errors="replace")))
    hdr = [h.strip() for h in rows[0]]
    ie = next(i for i, h in enumerate(hdr) if "mem_rden" in h)
    idd = next(i for i, h in enumerate(hdr) if "mem_rd_data" in h)
    out = []
    for r in rows[1:]:
        if len(r) > max(ie, idd) and r[ie].strip() in ("1", "1'b1"):
            dv = r[idd].strip().upper()
            if dv.startswith("0X"):
                dv = dv[2:]
            try:
                out.append(int(dv, 16) & 0xFF)
            except ValueError:
                pass
    return out


b = stream(B + r"\jb31b_rdcap_bridge.csv")
e = stream(B + r"\jb31b_rdcap_e.csv")
hx = lambda s: " ".join("%02x" % x for x in s)
print("bridge len=%d  e len=%d" % (len(b), len(e)))
print("bridge[0:10]   = %s" % hx(b[:10]))
print("e     [0:10]   = %s" % hx(e[:10]))
print("bridge[-16:]   = %s" % hx(b[-16:]))
print("e     [-16:]   = %s" % hx(e[-16:]))
print("bridge[8:18]   = %s" % hx(b[8:18]))
print("e     [0:10]   = %s" % hx(e[:10]))
print("shift-8 equality (b[8:]==e[:len(e)-8]) : %s"
      % (b[8:] == e[:len(e) - 8]))
# 前导判定
print("bridge 前 8 字节 == 前导+SFD (55*7,D5): %s"
      % (b[:8] == [0x55] * 7 + [0xD5]))
print("e 前 8 字节 == 帧首(dst MAC 08:3c:03:a0:26:96): %s"
      % (e[:6] == [0x08, 0x3C, 0x03, 0xA0, 0x26, 0x96]))
