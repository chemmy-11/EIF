#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_selftest_csv.py -- generate synthetic ILA CSVs to exercise
r3c_ila_analyze.py ILA4/ILA5 code paths OFFLINE (no board, no Vivado).

The CSVs mimic the Vivado 2023.1 `write_hw_ila_data -csv_file` layout:
  line 1 : probe names ("..." bus slices, "_1" single-bit suffix)
  line 2 : "Radix - UNSIGNED,UNSIGNED,UNSIGNED,HEX,..."
  line 3+: samples "Sample in Buffer,Sample in Window,TRIGGER,..."

Generated scenarios
  r3c_selftest_ila4_wedge.csv
      NAMED layout (dbg_l_arvalid/... alias nets, the audit-plan layout).
      - AR 0x34 handshake completes (R beat returns), then
      - AR 0x44 (WR_DBG) accepted at sample 17, then lrst sticks in LR_RACK,
        r_req=1 / r_ack_s1=0 forever, no R beat afterwards,
        dbg_l_stuck[3:0]=1 (bit0) and dbg_l_stuck_or=1.
  r3c_selftest_ila4_bus_wedge.csv
      PACKED layout (dbg_l_bus[0..35] + duplicate dbg_l_bus[35]_1), i.e. the
      real round3c u_ila_4 shape. Same scene, encoded in the RTL bit map:
        bit0/1 AR handshake, bit12 = AR address class +0x44 (one-hot),
        bit20 lrst[0]=1, bit24 r_req=1, bit31 stuck[0]=1, bit35 |stuck=1.
  r3c_selftest_ila5_go.csv
      GO_UI pulse at sample 8, ACK_UI at sample 10, S2MM state 1(WAITGO) ->
      2(STREAM) at 11, tdata beats 12/13, introut rises at 20 and is sticky.

Run:  <full-python> gen_selftest_csv.py
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))
N = 64


def write_csv(path, names, nrows, rowfn):
    lines = []
    lines.append(",".join(names))
    lines.append("Radix - " + ",".join(["UNSIGNED"] * 3 +
                                       ["HEX"] * (len(names) - 3)))
    for i in range(nrows):
        lines.append(",".join(rowfn(i)))
    with open(path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote %s (%d rows, %d cols)" % (path, nrows, len(names)))


def gen_ila4_named():
    names = [
        "Sample in Buffer", "Sample in Window", "TRIGGER",
        "dbg_l_arvalid_1", "dbg_l_arready_1", "dbg_l_rvalid_1",
        "dbg_l_rready_1", "dbg_l_awvalid_1", "dbg_l_awready_1",
        "dbg_l_wvalid_1", "dbg_l_wready_1", "dbg_l_bvalid_1",
        "dbg_l_bready_1", "dbg_l_araddr[5:0]", "dbg_l_awaddr[5:0]",
        "dbg_l_lwst[1:0]", "dbg_l_lrst[1:0]", "dbg_l_a_req_1",
        "dbg_l_a_ack_s1_1", "dbg_l_r_req_1", "dbg_l_r_ack_s1_1",
        "dbg_l_d_req_s1_1", "dbg_l_d_ack_1", "dbg_l_aresetn_1",
        "dbg_l_rstuser_s2_1", "dbg_l_rstuser_evt_1", "dbg_l_stuck[3:0]",
        "dbg_l_stuck_or_1",
    ]

    def row(i):
        arvalid = arready = rvalid = rready = 0
        araddr = 0
        lrst = 0
        r_req = r_ack = d_req = d_ack = 0
        stuck = 0
        if i == 10:                     # AR 0x34 (word 13) handshake
            arvalid = arready = 1
            araddr = 13
        elif i in (11, 12):             # lite waits for user ack of read req
            lrst = 1
            r_req = 1
        elif i == 13:                   # user acked the read request
            lrst = 2
            r_req = 1
            r_ack = 1
            d_ack = 1
        elif i == 14:                   # user returned read data
            lrst = 3
            d_req = 1
        elif i == 15:                   # R beat returned, read done
            lrst = 0
            rvalid = 1
            rready = 1
        elif i == 17:                   # AR 0x44 (word 17 = WR_DBG) accepted
            arvalid = arready = 1
            araddr = 17
        elif i >= 18:                   # WEDGE: LR_RACK forever, no R beat
            lrst = 1
            r_req = 1
            stuck = 1                   # bit0 = lrst != LR_IDLE
        vals = [
            str(i), str(i), "1" if i == 17 else "0",
            str(arvalid), str(arready), str(rvalid), str(rready),
            "0", "0", "0", "0", "0", "0",
            "%02X" % araddr, "00",
            "0", "%01X" % lrst,
            "0", "0", str(r_req), str(r_ack), str(d_req), str(d_ack),
            "1", "1", "0",
            "%X" % stuck, "1" if stuck else "0",
        ]
        return vals

    write_csv(os.path.join(HERE, "r3c_selftest_ila4_wedge.csv"), names, N, row)


def gen_ila4_packed():
    """Real round3c u_ila_4 shape: 36-bit packed dbg_l_bus + duplicate bit35."""
    names = ["Sample in Buffer", "Sample in Window", "TRIGGER"]
    names += ["dbg_l_bus[%d]" % b for b in range(36)]
    names += ["dbg_l_bus[35]_1"]

    def row(i):
        bits = [0] * 36
        # defaults: aresetn=1, rstuser_s2=1
        bits[28] = 1
        bits[29] = 1
        if i == 10:                     # AR +0x34 handshake
            bits[0] = 1
            bits[1] = 1
            bits[10] = 1
        elif i in (11, 12):             # lrst=1 (LR_RACK), r_req=1
            bits[20] = 1
            bits[24] = 1
        elif i == 13:                   # lrst=2 (LR_DRQ), r_ack=1, d_ack=1
            bits[21] = 1
            bits[25] = 1
            bits[27] = 1
        elif i == 14:                   # lrst=3 (LR_DACK), d_req_s1=1
            bits[20] = 1
            bits[21] = 1
            bits[26] = 1
            bits[27] = 1
        elif i == 15:                   # R handshake, back to LR_IDLE
            bits[2] = 1
            bits[3] = 1
        elif i == 17:                   # AR +0x44 (WR_DBG) accepted
            bits[0] = 1
            bits[1] = 1
            bits[12] = 1
        elif i >= 18:                   # WEDGE: LR_RACK forever
            bits[20] = 1
            bits[24] = 1
            bits[31] = 1                # stuck[0]
        bits[35] = 1 if i >= 18 else 0  # |stuck trigger bit
        vals = [str(i), str(i), "1" if i == 17 else "0"]
        vals += ["%01X" % b for b in bits]
        vals += ["%01X" % bits[35]]     # duplicate bit35 column (probe1)
        return vals

    write_csv(os.path.join(HERE, "r3c_selftest_ila4_bus_wedge.csv"), names, N, row)


def gen_ila5():
    names = [
        "Sample in Buffer", "Sample in Window", "TRIGGER",
        "dbg_s2mm_tdata64[63:0]", "dbg_s2mm_tkeep8[7:0]",
        "dbg_s2mm_tvalid_1", "dbg_s2mm_tready_1", "dbg_s2mm_tlast_w_1",
        "dbg_wd_go_ui_1", "dbg_wd_ack_ui_1", "dbg_wd_intr_ui_1",
        "dbg_wd_go_ok_1", "dbg_s2mm_state[2:0]",
    ]

    def row(i):
        go = ack = intr = go_ok = 0
        tvalid = tready = tlast = 0
        tdata = "0000000000000000"
        tkeep = "00"
        if i < 7:
            state = 0                   # IDLE
        elif i <= 10:
            state = 1                   # WAITGO
        elif i <= 18:
            state = 2                   # STREAM
        else:
            state = 4                   # WAITDONE
        if i == 8:
            go = 1
        if i == 10:
            ack = 1
        if i == 11:
            go_ok = 1
        if i in (12, 13):
            tvalid = 1
            tready = 1
            tdata = "D555555555555555" if i == 12 else "00000000FEDCBA98"
            tkeep = "FF" if i == 12 else "3F"
            if i == 13:
                tlast = 1
        if i >= 20:
            intr = 1                    # introut asserts and stays sticky
        vals = [
            str(i), str(i), "1" if i == 16 else "0",
            tdata, tkeep, str(tvalid), str(tready), str(tlast),
            str(go), str(ack), str(intr), str(go_ok), "%01X" % state,
        ]
        return vals

    write_csv(os.path.join(HERE, "r3c_selftest_ila5_go.csv"), names, N, row)


if __name__ == "__main__":
    gen_ila4_named()
    gen_ila4_packed()
    gen_ila5()
