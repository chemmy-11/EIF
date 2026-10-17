# -*- coding: utf-8 -*-
"""jb31b_ilacnt_parse.py -- parse ILA CSV (snapshot captures) and print counters.

Usage: py jb31b_ilacnt_parse.py <csv> [<csv> ...]
For each CSV: header row 0, radix row 1, data rows 2..N.
Prints min/max/first/last for selected cumulative counters.
"""
import csv
import sys

PATS = [
    "dbg_mem2_wr_frm", "dbg_mem2_rd_frm", "dbg_mem2_ost", "dbg_mem2_wm",
    "dbg_mem2_u_wr", "dbg_mem2_u_rd",
    "dbg_mem_wr_frm", "dbg_mem_rd_frm", "dbg_mem_ost", "dbg_mem_wm",
    "dbg_pk_frames", "dbg_echo_b_rx", "dbg_echo_b_tx",
    "dbg_mem_rden",
]


def parse(path):
    rows = list(csv.reader(open(path, encoding="utf-8", errors="replace")))
    hdr = [h.strip() for h in rows[0]]
    data = rows[2:]
    out = {}
    for pat in PATS:
        idxs = [i for i, h in enumerate(hdr) if pat in h]
        for i in idxs:
            vals = []
            for r in data:
                if len(r) <= i:
                    continue
                v = r[i].strip()
                if v.upper().startswith("0X"):
                    v = v[2:]
                try:
                    vals.append(int(v, 16))
                except ValueError:
                    pass
            if vals:
                out[hdr[i]] = (min(vals), max(vals), vals[0], vals[-1], len(vals))
    return out


def main():
    for p in sys.argv[1:]:
        print("=" * 78)
        print("FILE:", p)
        res = parse(p)
        if not res:
            print("  (no matching counter columns)")
            continue
        print("  %-22s %8s %8s %8s %8s %6s" % ("probe", "min", "max", "first", "last", "n"))
        for k, v in res.items():
            print("  %-22s %8d %8d %8d %8d %6d" % (k, v[0], v[1], v[2], v[3], v[4]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
