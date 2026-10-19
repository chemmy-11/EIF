#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""hypothesis_selftest.py -- positive/negative self-test for the round3c
hypothesis classifier inside r3c_ila_analyze.py (Lead request 2026-10-19).

For EVERY hypothesis tag the tool produces, this test requires:
  * at least one POSITIVE scenario where the tag MUST appear, and
  * at least one NEGATIVE scenario where the tag MUST NOT appear
    (false-positive guard: a scenario that triggers some other tag, or an
     "idle / healthy bus" scenario that must classify as UNCLASSIFIED).

The CSVs are synthetic and generated locally (no board, no Vivado, no network).
The analyzer is executed as a subprocess exactly as a user would run it, and
the R3C_ILA4_HYPOTHESIS / R3C_ILA5_HYPOTHESIS marker lines are grepped back.

Covered tags
  ILA4: H-reset, H-ARnever, H-acklost, H-bstuck, H-rvalid, H-false-hs
  ILA5: GO_NOT_AT_BRIDGE, GO_AT_BRIDGE_GO_OK_0,
        GO_AT_BRIDGE_GO_OK_1_NOT_STREAM, INTR_STICKY, ENTERED_STREAM

USAGE
  <full-python> hypothesis_selftest.py
  full path: C:\\Users\\15266\\AppData\\Local\\Python\\pythoncore-3.14-64\\python.exe
EXIT CODE: 0 = every positive/negative check passed, 1 = failure.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ANALYZER = os.path.normpath(os.path.join(HERE, "..", "r3c_ila_analyze.py"))
N = 16

ILA4_TAGS = ["H-reset", "H-ARnever", "H-acklost", "H-bstuck", "H-rvalid",
             "H-false-hs"]
ILA5_TAGS = ["GO_NOT_AT_BRIDGE", "GO_AT_BRIDGE_GO_OK_0",
             "GO_AT_BRIDGE_GO_OK_1_NOT_STREAM", "INTR_STICKY",
             "ENTERED_STREAM"]


# ---------------------------------------------------------------------------
# synthetic CSV writers (Vivado 2023.1 write_hw_ila_data layout)
# ---------------------------------------------------------------------------
def write_ila4_csv(path, rows):
    """rows: list of dict{bit_index: 0/1}; packed round3c u_ila_4 layout."""
    names = ["Sample in Buffer", "Sample in Window", "TRIGGER"]
    names += ["dbg_l_bus[%d]" % b for b in range(36)]
    names += ["dbg_l_bus[35]_1"]
    lines = [",".join(names)]
    lines.append("Radix - " + ",".join(["UNSIGNED"] * 3 + ["HEX"] * 38))
    for i, bits in enumerate(rows):
        v = [0] * 36
        for k, val in bits.items():
            v[k] = val
        cells = [str(i), str(i), "1" if i == N // 2 else "0"]
        cells += ["%X" % x for x in v]
        cells += ["%X" % v[35]]
        lines.append(",".join(cells))
    with open(path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def write_ila5_csv(path, rows):
    """rows: list of dict(go=,ack=,intr=,go_ok=,state=)."""
    names = ["Sample in Buffer", "Sample in Window", "TRIGGER",
             "dbg_wd_go_ui_1", "dbg_wd_ack_ui_1", "dbg_wd_intr_ui_1",
             "dbg_wd_go_ok_1", "dbg_s2mm_state[2:0]"]
    lines = [",".join(names)]
    lines.append("Radix - " + ",".join(["UNSIGNED"] * 3 + ["HEX"] * 5))
    for i, r in enumerate(rows):
        cells = [str(i), str(i), "1" if i == N // 2 else "0",
                 "%X" % r.get("go", 0), "%X" % r.get("ack", 0),
                 "%X" % r.get("intr", 0), "%X" % r.get("go_ok", 0),
                 "%X" % r.get("state", 0)]
        lines.append(",".join(cells))
    with open(path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# ILA4 scenarios (packed dbg_l_bus bit map from rtl/axi_lite_regs.v)
# ---------------------------------------------------------------------------
def ila4_rows(kind):
    rows = []
    for i in range(N):
        b = {28: 1, 29: 1}          # aresetn=1, rstuser_s2=1
        if kind == "arnever":
            b[1] = 1                # arready=1 level; nothing else ever happens
        elif kind == "acklost_read":
            if i in (2, 3):
                b[0] = 1; b[1] = 1; b[10] = 1          # normal AR to +0x34
            if i >= 8:
                b[20] = 1; b[24] = 1                   # lrst=1, r_req=1
        elif kind == "acklost_write":
            if i in (2, 3):
                b[4] = 1; b[5] = 1; b[6] = 1; b[7] = 1; b[14] = 1  # AW/W to +0x0C
            if i >= 8:
                b[18] = 1; b[22] = 1                   # lwst=1, a_req=1
        elif kind == "bstuck":
            if i >= 8:
                b[8] = 1; b[18] = 1; b[0] = 1          # bvalid=1 lwst=1 arvalid=1
        elif kind == "rvalid":
            if i >= 8:
                b[2] = 1; b[20] = 1; b[21] = 1         # rvalid=1 lrst=3
        elif kind == "falsehs":
            if i == 5:
                b[0] = 1; b[1] = 1; b[20] = 1          # AR handshake while lrst=1
        elif kind == "reset":
            if i in (3, 4):
                b[0] = 1; b[1] = 1; b[10] = 1          # one normal AR first
            if i >= 8:
                b[30] = 1; b[1] = 1                    # rstuser_evt sticky
        elif kind == "idle_normal":
            # one healthy read: AR -> RACK -> DRQ -> DACK -> R beat -> idle
            if i == 2:
                b[0] = 1; b[1] = 1; b[10] = 1
            elif i == 3:
                b[20] = 1; b[24] = 1
            elif i == 4:
                b[20] = 1; b[24] = 1; b[25] = 1
            elif i == 5:
                b[21] = 1; b[26] = 1; b[27] = 1
            elif i == 6:
                b[2] = 1; b[3] = 1
        rows.append(b)
    return rows


# ---------------------------------------------------------------------------
# ILA5 scenarios
# ---------------------------------------------------------------------------
def ila5_rows(kind):
    rows = []
    for i in range(N):
        r = {"go": 0, "ack": 0, "intr": 0, "go_ok": 0, "state": 0}
        if kind == "gonone":
            r["state"] = 0 if i < 8 else 4
        elif kind == "gonook":
            r["state"] = 0 if i < 3 else 1
            if i == 4:
                r["go"] = 1
        elif kind == "gooknostream":
            r["state"] = 0 if i < 3 else 1
            if i == 4:
                r["go"] = 1
            if i == 6:
                r["go_ok"] = 1
            if i >= 10:
                r["state"] = 3
        elif kind == "stream_sticky":
            if i < 3:
                r["state"] = 0
            elif i < 6:
                r["state"] = 1
            else:
                r["state"] = 2
            if i == 4:
                r["go"] = 1
            if i == 6:
                r["go_ok"] = 1
            if i == 7:
                r["ack"] = 1
            if i >= 10:
                r["intr"] = 1
        rows.append(r)
    return rows


# ---------------------------------------------------------------------------
# scenario table: (name, kind, expected_tags)
# ---------------------------------------------------------------------------
SCENARIOS = [
    ("ila4_arnever",          "ila4", "arnever",            ["H-ARnever"]),
    ("ila4_idle_normal",      "ila4", "idle_normal",        ["UNCLASSIFIED"]),
    ("ila4_acklost_read",     "ila4", "acklost_read",       ["H-acklost"]),
    ("ila4_acklost_write",    "ila4", "acklost_write",      ["H-acklost"]),
    ("ila4_bstuck",           "ila4", "bstuck",             ["H-bstuck"]),
    ("ila4_rvalid",           "ila4", "rvalid",             ["H-rvalid"]),
    ("ila4_falsehs",          "ila4", "falsehs",            ["H-false-hs"]),
    ("ila4_reset",            "ila4", "reset",              ["H-reset"]),
    ("ila5_gonone",           "ila5", "gonone",             ["GO_NOT_AT_BRIDGE"]),
    ("ila5_gonook",           "ila5", "gonook",             ["GO_AT_BRIDGE_GO_OK_0"]),
    ("ila5_gooknostream",     "ila5", "gooknostream",
     ["GO_AT_BRIDGE_GO_OK_1_NOT_STREAM"]),
    ("ila5_stream_sticky",    "ila5", "stream_sticky",
     ["ENTERED_STREAM", "INTR_STICKY"]),
    ("ila5_healthy_idle",     "ila5", "healthy_idle",       ["UNCLASSIFIED"]),
]


def ila5_healthy_idle_rows():
    rows = []
    for i in range(N):
        rows.append({"go": 0, "ack": 0, "intr": 0, "go_ok": 0, "state": 0})
    return rows


# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------
def run_analyzer(path):
    env = dict(os.environ)
    env["PYTHONUTF8"] = "1"
    proc = subprocess.run([sys.executable, ANALYZER, path],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          env=env)
    out = proc.stdout.decode("utf-8", errors="replace")
    return proc.returncode, out


def parse_hyp_tags(out, marker):
    tags = []
    rx = re.compile(r"^\s*R3C_ILA[45]_HYPOTHESIS:\s*([A-Za-z0-9_\-]+)\s*\|")
    for line in out.splitlines():
        if marker not in line:
            continue
        m = rx.match(line)
        if m:
            tags.append(m.group(1))
    return tags


def main():
    print("HYP_SELFTEST_START")
    print("HYP_SELFTEST_ANALYZER: %s" % ANALYZER)
    print("HYP_SELFTEST_PYTHON: %s" % sys.executable)
    print("HYP_SELFTEST_SCENARIOS: %d" % len(SCENARIOS))

    all_tags = ILA4_TAGS + ILA5_TAGS + ["UNCLASSIFIED"]
    pos_count = {t: 0 for t in all_tags}
    neg_count = {t: 0 for t in all_tags}
    failures = 0
    results = []

    for name, kind, builder, expected in SCENARIOS:
        csv_path = os.path.join(HERE, "hyp_%s.csv" % name)
        if kind == "ila4":
            write_ila4_csv(csv_path, ila4_rows(builder))
            marker = "R3C_ILA4_HYPOTHESIS"
        else:
            rows = ila5_healthy_idle_rows() if builder == "healthy_idle" \
                else ila5_rows(builder)
            write_ila5_csv(csv_path, rows)
            marker = "R3C_ILA5_HYPOTHESIS"

        rc, out = run_analyzer(csv_path)
        found = parse_hyp_tags(out, marker)
        forbidden = [t for t in all_tags if t not in expected]
        missing = [t for t in expected if t not in found]
        spurious = [t for t in found if t in forbidden]
        ok = (rc == 0) and not missing and not spurious
        if not ok:
            failures += 1
        for t in expected:
            if t in found:
                pos_count[t] += 1
        for t in all_tags:
            if t not in expected:
                neg_count[t] += 1
        results.append((name, ok, found, missing, spurious))
        print("HYP_SELFTEST_CASE: %-22s kind=%-4s rc=%d expected=%-45s found=%-45s %s"
              % (name, kind, rc, ",".join(expected) or "-",
                 ",".join(found) or "-", "PASS" if ok else "FAIL"))
        if missing:
            print("HYP_SELFTEST_MISSING: %s" % ",".join(missing))
        if spurious:
            print("HYP_SELFTEST_FALSE_POSITIVE: %s" % ",".join(spurious))
        if rc != 0:
            print("HYP_SELFTEST_RC_FAIL: %s rc=%d" % (name, rc))
            for line in out.splitlines()[-12:]:
                print("HYP_SELFTEST_TAIL: " + line)

    print("HYP_SELFTEST_COVERAGE:")
    coverage_fail = 0
    for t in all_tags:
        okcov = (pos_count[t] >= 1) and (neg_count[t] >= 1)
        if not okcov:
            coverage_fail += 1
        print("HYP_SELFTEST_TAG: %-36s positive=%d negative=%d %s"
              % (t, pos_count[t], neg_count[t], "OK" if okcov else "COVERAGE_FAIL"))

    print("HYP_SELFTEST_SUMMARY: scenarios=%d failures=%d coverage_fail=%d"
          % (len(SCENARIOS), failures, coverage_fail))
    ok_all = (failures == 0) and (coverage_fail == 0)
    print("HYP_SELFTEST_RESULT: %s" % ("PASS" if ok_all else "FAIL"))
    print("HYP_SELFTEST_DONE")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
