# -*- coding: utf-8 -*-
"""rdcap_analyze.py — 从 ILA CSV 重建「发射字节流」并与桥模式参照逐字节比对。

用法: python rdcap_analyze.py [bridge_csv] [e_csv]
输出: 两条流的前 80 字节、总字节数、首个差异位置(及两侧上下文)。
"""
import csv
import sys

B = r"D:\FPGA\prj\project_11\out"


def load(path):
    rows = list(csv.reader(open(path, encoding="utf-8", errors="replace")))
    hdr = [h.strip() for h in rows[0]]
    return hdr, rows[1:]


def pick(hdr, needle):
    hits = [i for i, h in enumerate(hdr) if needle in h]
    return hits[0] if hits else None


def stream(path):
    hdr, rows = load(path)
    ie = pick(hdr, "mem_rden")
    idd = pick(hdr, "mem_rd_data")
    if ie is None or idd is None:
        return hdr, None, None
    data = []
    for r in rows:
        if len(r) <= max(ie, idd):
            continue
        en, dv = r[ie].strip(), r[idd].strip()
        if en in ("1", "1'b1"):
            if dv.upper().startswith("0X"):
                dv = dv[2:]
            try:
                data.append(int(dv, 16) & 0xFF)
            except ValueError:
                pass
    return hdr, ie, idd, data


def dump(tag, data, n=80):
    print("%s: %d bytes" % (tag, len(data) if data else 0))
    if data:
        print("  head[0:%d]: %s" % (n, " ".join("%02x" % b for b in data[:n])))


def main():
    bp = sys.argv[1] if len(sys.argv) > 1 else B + r"\jb31b_rdcap_bridge.csv"
    ep = sys.argv[2] if len(sys.argv) > 2 else B + r"\jb31b_rdcap_e.csv"
    for tag, p in (("BRIDGE", bp), ("E", ep)):
        hdr, ie, idd, data = stream(p)
        print("=" * 70)
        print("%s  file=%s" % (tag, p))
        print("  cols: en=%s data=%s" % (hdr[ie] if ie is not None else "?", hdr[idd] if idd is not None else "?"))
        dump(tag, data)

    hb, ieb, idb, db = stream(bp)
    he, iee, ide, de = stream(ep)
    if db and de:
        n = min(len(db), len(de))
        diff = next((i for i in range(n) if db[i] != de[i]), None)
        print("=" * 70)
        print("common prefix len=%d  first diff at %s" % (n, diff))
        if diff is not None:
            lo, hi = max(0, diff - 8), min(n, diff + 16)
            print("  bridge[%d:%d] = %s" % (lo, hi, " ".join("%02x" % b for b in db[lo:hi])))
            print("  e     [%d:%d] = %s" % (lo, hi, " ".join("%02x" % b for b in de[lo:hi])))
        # 逐位/逐字节偏移相关性: E 流是否等于桥流的某段移位?
        for shift in (-8, -4, 4, 8, 16, 32, 64):
            if diff is None:
                break
            ok = db[diff + shift:diff + shift + 16] == de[diff:diff + 16] if diff + shift >= 0 else False
            if ok:
                print("  ⇒ E 流相对桥流在 diff 处错位 %d 字节" % shift)
    return 0


if __name__ == "__main__":
    sys.exit(main())
