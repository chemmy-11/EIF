# -*- coding: utf-8 -*-
"""ILA2 捕获分析: E 轮期间以太网 TX 是否发生 + 收帧事件对照。"""
import csv, collections

P = r"D:\FPGA\prj\project_11\out\jb31b_ila2_txen.csv"
rows = list(csv.reader(open(P, encoding="utf-8", errors="replace")))
hdr = [h.strip() for h in rows[0]]
print("COLS(%d): %s" % (len(hdr), hdr))
idx = {h: i for i, h in enumerate(hdr)}
data = rows[1:]
print("SAMPLES: %d" % len(data))

def col(w):
    i = idx.get(w)
    return [r[i].strip() for r in data] if i is not None else None

for w in ["dbg_stack_txen", "dbg_udp_rec_done", "dbg_gmii_rx_dv", "dbg_gmii_rxd", "dbg_arp_rx_done",
          "dbg_pfwd_wr", "dbg_pfwd_drop", "dbg_cmd_rx", "dbg_rec_byte_num", "dbg_icmp_rec_done"]:
    c = col(w)
    if c is None:
        print("%-20s MISSING" % w)
        continue
    cnt = collections.Counter(c)
    print("%-20s distinct=%d top=%s" % (w, len(cnt), cnt.most_common(3)))

tx = col("dbg_stack_txen")
if tx:
    ones = [i for i, v in enumerate(tx) if v in ("1", "1'b1")]
    print("txen high samples: %d" % len(ones))
    if ones:
        print("first high idx: %s" % ones[:12])
