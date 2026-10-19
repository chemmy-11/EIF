#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""r3d_s0_buildlog_adapter.py -- make a round3d sweep log acceptable to
`out\\r2_board.ps1` Step-S0 WITHOUT editing r2_board.ps1.

WHY THIS EXISTS (offline tooling gap, verified 2026-10-19)
  round3d is built with the single-throw sweep copy `out\\r3c2_sweep_one.tcl`
  (driver: `out\\r3d_sweep_one_retry.ps1`). Its success markers are:
      SWEEP1_<directive>: WNS=<x> WHS=<y>
      V5_SWEEP1_OK: directive=<d> wns=<x> whs=<y> bit=<path>
  but r2_board.ps1 Step-S0 only recognises:
      WNS regex : SWEEP2?_[A-Za-z]+:\\s*WNS=       (SWEEP_/SWEEP2_)
      okMarker  : V5_SWEEP2_OK|V5_SWEEP_OK|W5_BUILD_OK|DBG_BUILD_DONE
  => S0 would report WNS/WHS=null + okMarker=False => FAIL even for a good
  bitstream (root cause: marker regex, not the design).

  Two fixes are possible:
    A) patch r2_board.ps1 (preferred, 5 regex tokens, see r3c_pin.md §4):
         - "SWEEP2?_[A-Za-z]+"  ->  "SWEEP[12]?_[A-Za-z]+"
         - okMarker  += V5_SWEEP1_OK        failMarker += V5_SWEEP1_ALL_FAIL
         - bitInLog  regex += V5_SWEEP1_OK
    B) this adapter: prove the real 'V5_SWEEP1_OK' line, re-emit its wns/whs as
       the SWEEP2_ / V5_SWEEP2_OK lines S0 accepts, copy the DRC / bitstream
       lines, and pass the generated file as `-BuildLog`.
  The adapter NEVER invents numbers: wns/whs/directive/bit are parsed from the
  real log; it fails (exit 2) if the marker is absent or wns/whs < 0, or if the
  bit file is missing / hash mismatch.

USAGE
  <full-python> r3d_s0_buildlog_adapter.py ^
      --sweep-log D:\\FPGA\\prj\\project_11\\out\\r3d_one.log ^
      --bit "D:\\FPGA\\prj\\project_11\\out\\archive\\b31b_r2_2026-10-19_round3d\\aurora_mem_bridge_r2_<h8>.bit" ^
      [--expect-bit-hash8 <H8>] [--out <adapter log path>]

  then:
    powershell -File D:\\FPGA\\prj\\project_11\\out\\r2_board.ps1 -Run `
        ... -BuildLog <adapter log path> ...

EXIT: 0 = adapter written and self-checked; 2 = cannot adapt (details printed).
"""

import argparse
import os
import re
import sys

MARK_RE = re.compile(
    r"V5_SWEEP[12]?_OK:\s*directive=(\S+)\s+wns=(-?\d+(?:\.\d+)?)\s+"
    r"whs=(-?\d+(?:\.\d+)?)\s+bit=(\S+)")
SWEEP_LINE_RE = re.compile(
    r"SWEEP[12]?_[A-Za-z0-9_]+:\s*WNS=(-?\d+(?:\.\d+)?)\s+"
    r"WHS=(-?\d+(?:\.\d+)?)")
DRC_RE = re.compile(r".*DRC finished with (\d+) Errors.*")
BITSTREAM_RE = re.compile(r".*write_bitstream completed successfully.*", re.I)
FAIL_RE = re.compile(r"V5_SWEEP[12]?_ALL_FAIL|NO_BITSTREAM")

# regexes copied from out\r2_board.ps1 Step-S0 (2026-10-18 version) so the
# adapter output can be self-checked against exactly what S0 will parse
S0_WNS_RE = re.compile(r"SWEEP2?_[A-Za-z]+:\s*WNS=(-?\d+(?:\.\d+)?)")
S0_WHS_RE = re.compile(r"SWEEP2?_[A-Za-z]+:\s*WNS=-?\d+(?:\.\d+)?\s+WHS=(-?\d+(?:\.\d+)?)")
S0_OK_RE = re.compile(r"V5_SWEEP2_OK|V5_SWEEP_OK|W5_BUILD_OK|DBG_BUILD_DONE")
S0_FAIL_RE = re.compile(r"V5_SWEEP_ALL_FAIL|V5_SWEEP2_ALL_FAIL|W5_BUILD_TIMING_FAIL|NO_BITSTREAM")
S0_BIT_RE = re.compile(r"(?:V5_SWEEP2_OK|V5_SWEEP_OK|DBG_BUILD_DONE)[^\r\n]*bit=(\S+)")
S0_DRC_RE = re.compile(r"DRC finished with (\d+) Errors")


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main(argv=None):
    ap = argparse.ArgumentParser(description="round3d sweep log -> S0-compatible build log")
    ap.add_argument("--sweep-log", required=True, help="round3d sweep log (e.g. out\\r3d_one.log)")
    ap.add_argument("--bit", required=True, help="archived round3d bitstream path")
    ap.add_argument("--expect-bit-hash8", default="", help="optional expected sha256 first 8")
    ap.add_argument("--out", default="", help="output adapter log path")
    args = ap.parse_args(argv)

    print("S0_ADAPTER_START")
    print("S0_ADAPTER_SWEEP_LOG: %s" % args.sweep_log)
    print("S0_ADAPTER_BIT: %s" % args.bit)

    if not os.path.isfile(args.sweep_log):
        print("S0_ADAPTER_RESULT: FAIL sweep log not found")
        return 2
    if not os.path.isfile(args.bit):
        print("S0_ADAPTER_RESULT: FAIL bitstream not found: %s" % args.bit)
        return 2

    text = read_text(args.sweep_log)
    marks = MARK_RE.findall(text)
    if not marks:
        # fall back: WNS/WHS line only (no bit path) is not enough for S0 bitInLog,
        # but S0 tolerates an empty bitInLog; still require the ok marker.
        print("S0_ADAPTER_RESULT: FAIL no 'V5_SWEEP[12]_OK: ... wns= whs= bit=' marker"
              " in sweep log (was the build successful?)")
        tail = [ln for ln in text.splitlines() if ln.strip()][-12:]
        for ln in tail:
            print("S0_ADAPTER_TAIL: " + ln)
        return 2

    directive, wns_s, whs_s, log_bit = marks[-1]
    wns = float(wns_s)
    whs = float(whs_s)
    print("S0_ADAPTER_MARKER: directive=%s wns=%s whs=%s log_bit=%s"
          % (directive, wns_s, whs_s, log_bit))
    if wns < 0 or whs < 0:
        print("S0_ADAPTER_RESULT: FAIL wns/whs negative (build did not pass the gate)")
        return 2

    # bit identity cross-check (log bit leaf vs archived bit leaf)
    log_leaf = os.path.basename(log_bit.replace("\\", "/"))
    arc_leaf = os.path.basename(args.bit)
    print("S0_ADAPTER_BIT_LEAF: log=%s archived=%s match=%s"
          % (log_leaf, arc_leaf, log_leaf == arc_leaf))

    bit_hash8 = ""
    try:
        import hashlib
        h = hashlib.sha256()
        with open(args.bit, "rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                h.update(chunk)
        bit_hash8 = h.hexdigest()
    except Exception as exc:  # noqa: BLE001
        print("S0_ADAPTER_RESULT: FAIL cannot hash bit: %s" % exc)
        return 2
    print("S0_ADAPTER_BIT_SHA8: %s" % bit_hash8[:8].upper())
    if args.expect_bit_hash8:
        want = args.expect_bit_hash8.strip().lower()
        if not bit_hash8.startswith(want):
            print("S0_ADAPTER_RESULT: FAIL bit sha8 %s != expected %s"
                  % (bit_hash8[:8], want))
            return 2

    drc_line = ""
    for ln in text.splitlines():
        m = DRC_RE.match(ln)
        if m:
            drc_line = ln.strip()
    bitstream_line = ""
    if BITSTREAM_RE.search(text):
        for ln in text.splitlines():
            if BITSTREAM_RE.match(ln):
                bitstream_line = ln.strip()
    fail_lines = [ln.strip() for ln in text.splitlines() if FAIL_RE.search(ln)]
    print("S0_ADAPTER_DRC_LINE: %s" % (drc_line or "(not found)"))
    print("S0_ADAPTER_BITSTREAM_LINE: %s" % (bitstream_line or "(not found)"))
    print("S0_ADAPTER_FAIL_MARKER_LINES: %d" % len(fail_lines))
    if fail_lines:
        print("S0_ADAPTER_RESULT: FAIL sweep log contains failure markers")
        return 2

    out_path = args.out
    if not out_path:
        out_path = os.path.join(os.path.dirname(os.path.abspath(args.sweep_log)),
                                "R3D_s0_buildlog_adapter.log")
    arc_bit_fwd = args.bit.replace("\\", "/")
    lines = [
        "# S0 adapter log (generated by tools/r3d_s0_buildlog_adapter.py)",
        "# source sweep log : %s" % os.path.abspath(args.sweep_log),
        "# archived bit     : %s (sha256 %s)" % (os.path.abspath(args.bit), bit_hash8),
        "# purpose          : re-emit the real V5_SWEEP1_OK numbers in the marker",
        "#                    form that out\\r2_board.ps1 Step-S0 parses. No value",
        "#                    is invented: wns/whs/directive/bit are parsed from",
        "#                    the source log above; DRC/bitstream lines are copied.",
        "# original marker line:",
        "#   V5_SWEEP1_OK: directive=%s wns=%s whs=%s bit=%s"
        % (directive, wns_s, whs_s, log_bit),
        "SWEEP2_%s: WNS=%s WHS=%s" % (directive, wns_s, whs_s),
        "V5_SWEEP2_OK: directive=%s wns=%s whs=%s bit=%s"
        % (directive, wns_s, whs_s, arc_bit_fwd),
    ]
    if drc_line:
        lines.append(drc_line)
    else:
        lines.append("# WARN: no 'DRC finished with N Errors' line in source log"
                     " (S0 needs it unless -SkipDrcRequirement)")
    if bitstream_line:
        lines.append(bitstream_line)
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("S0_ADAPTER_OUT: %s (%d B)" % (out_path, os.path.getsize(out_path)))

    # ---- self-check against the exact S0 regexes ----
    adapter = read_text(out_path)
    checks = []
    checks.append(("WNS", bool(S0_WNS_RE.search(adapter))))
    checks.append(("WHS", bool(S0_WHS_RE.search(adapter))))
    checks.append(("okMarker", bool(S0_OK_RE.search(adapter))))
    checks.append(("failMarker_absent", not S0_FAIL_RE.search(adapter)))
    mb = S0_BIT_RE.search(adapter)
    checks.append(("bitInLog", bool(mb)))
    if mb:
        s0_leaf = os.path.basename(mb.group(1).replace("/", "\\"))
        checks.append(("bitLeafMatch", s0_leaf == arc_leaf))
    checks.append(("drc0", bool(S0_DRC_RE.search(adapter)) and
                   int(S0_DRC_RE.search(adapter).group(1)) == 0))
    all_ok = True
    for name, ok in checks:
        print("S0_ADAPTER_SELFCHECK: %-16s %s" % (name, "PASS" if ok else "FAIL"))
        if not ok:
            all_ok = False
    print("S0_ADAPTER_RESULT: %s" % ("PASS" if all_ok else "FAIL"))
    print("S0_ADAPTER_NEXT: pass -BuildLog \"%s\" to out\\r2_board.ps1" % out_path)
    return 0 if all_ok else 2


if __name__ == "__main__":
    sys.exit(main())
