#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""r3c_ila_analyze.py -- prj11 R2 round3c offline ILA CSV analyzer (stdlib only).

Reads the CSV files exported by `write_hw_ila_data -csv_file <base>` (Vivado
2023.1) and prints a human/machine readable judgement. It never touches the
board, Vivado, or any network.

Supported profiles (auto detected from the CSV header probe names, or forced
with --mode):

  ILA4        @clk_100m axi_lite_regs AXI-lite wedge probes (round3c NEW).
              Two layouts are auto-detected:
              (a) PACKED (round3c build 2026-10-19): the core carries a single
                  36-bit bus dbg_l_bus[35:0] (probe0) + bit35 as probe1, so the
                  CSV columns are dbg_l_bus[0]..dbg_l_bus[35]. This tool rebuilds
                  the logical signals from the RTL bit map
                  (rtl/axi_lite_regs.v dbg_o assignments):
                    [0..9] arvalid/arready/rvalid/rready/awvalid/awready/
                           wvalid/wready/bvalid/bready
                    [10..13] AR address class (+0x34/+0x40/+0x44/other, one-hot)
                    [14..17] AW address class (+0x0C/+0x48/+0x4C/other, one-hot)
                    [18..21] lwst[1:0] / lrst[1:0]
                    [22..27] a_req/a_ack_s1/r_req/r_ack_s1/d_req_s1/d_ack
                    [28..30] aresetn/rstuser_s2/rstuser_evt
                    [31..34] stuck: lrst!IDLE / lwst!IDLE / arvalid&!arready /
                             rvalid&!rready
                    [35] |stuck  (trigger bit)
              (b) NAMED: individual dbg_l_arvalid/... alias nets (the audit-plan
                  layout, used only if a build exposes named nets instead).
              -> AXI handshake counts (AR/R/AW/W/B), address sequence decoded
                 to register byte offsets, last-N state, wedge verdict
                 (which wait is stuck / AR not accepted / RVALID not returned).

  ILA5        @ui_clk S2MM write engine + round3c probe5:
              dbg_wd_go_ui / dbg_wd_ack_ui / dbg_wd_intr_ui / dbg_wd_go_ok /
              dbg_s2mm_state[2:0]  (+ round3b tdata64/tkeep8/tvalid/tready/
              tlast_w if present)
              -> GO/ACK/intr/state timeline; did GO reach the bridge, did the
                 bridge ACK it, is introut sticky, did S2MM enter STREAM.

  LEGACY_UI   round3b ILA3 @ui bridge counters (dbg_mem_wm/wr_frm/rd_frm/...)
  LEGACY_USER round3b ILA0 @user bridge counters (dbg_mem_u_* ...)
              -> first/last/delta of every counter + s2mm state histogram and
                 zero-commit / zero-read conclusions (used to dry-run this tool
                 on the 2026-10-19 wed2 CSVs).

  GENERIC     any other CSV -> per-column first/last/min/max/change count.

HYPOTHESIS SIGNATURES (Lead request 2026-10-19; printed at the end of the
ILA4/ILA5 analysis; machine-greppable markers)

  ILA4 (evaluated on the LAST sample of the post-trigger window; extra
        whole-window guards noted below so an idle bus is not misclassified):
    R3C_ILA4_HYPOTHESIS: H-reset   | rstuser_evt(bit30)=1 (sticky) => user-domain
                                     reset mismatch takes priority
    R3C_ILA4_HYPOTHESIS: H-ARnever | arvalid=0 & arready=1 & rvalid=0 &
                                     lwst=lrst=0 & mailbox all 0 & no AR handshake
                                     in window => upstream MCU/interconnect never
                                     issued the read (NOT lite_regs internal)
    R3C_ILA4_HYPOTHESIS: H-acklost | lrst!=0 & r_req=1 & r_ack_s1=0 (read mailbox
                                     C return lost) OR lwst!=0 & a_req=1 &
                                     a_ack_s1=0 (write mailbox A return lost)
    R3C_ILA4_HYPOTHESIS: H-bstuck  | bvalid=1 & bready=0 & lwst!=0 & arvalid=1 &
                                     arready=0 (B not consumed => read frozen)
    R3C_ILA4_HYPOTHESIS: H-rvalid  | rvalid=1 & rready=0 & lrst!=0
    R3C_ILA4_HYPOTHESIS: H-false-hs| AR/AW/W handshake accepted in the same sample
                                     as a non-IDLE FSM state (must not happen after
                                     lite fix2 => stale netlist / layout mismatch)
    R3C_ILA4_HYPOTHESIS: UNCLASSIFIED | no signature matched; followed by
                                     R3C_ILA4_BITS_LAST: (all decoded signals) and
                                     R3C_ILA4_RAW_BITS_LAST: (b0..b35 when packed)
  ILA5:
    R3C_ILA5_HYPOTHESIS: GO_NOT_AT_BRIDGE | go_ui rising=0 over the window while
                         other S2MM activity (state/ack/intr/go_ok) IS present
                         (a completely idle window => UNCLASSIFIED instead)
    R3C_ILA5_HYPOTHESIS: GO_AT_BRIDGE_GO_OK_0 | go_ui rose but go_ok never high
    R3C_ILA5_HYPOTHESIS: GO_AT_BRIDGE_GO_OK_1_NOT_STREAM | GO+go_ok seen but
                         s2mm_state never 2(STREAM)
    R3C_ILA5_HYPOTHESIS: INTR_STICKY | intr_ui rose and never fell, last=1
    R3C_ILA5_HYPOTHESIS: ENTERED_STREAM | s2mm_state=2 seen (sample index given)
    (GO_AT_BRIDGE_GO_OK_UNKNOWN / GO_UI_PROBE_MISSING are defensive variants for
     CSVs without the go_ok / go_ui probe.)
  All hypothesis lines are [L1]-grade by construction (state-signature reading of
  one capture window); they are candidate labels, not final root causes.

USAGE
  python r3c_ila_analyze.py <file.csv> [<file2.csv> ...] [--last-n 16]
  python r3c_ila_analyze.py --dir <evidence dir> [--pattern "R3C_*.csv"]
  python r3c_ila_analyze.py --dir <evidence dir> --pattern "R2_ila_wed2_*.csv"

Full path of the Python used in this project:
  C:\\Users\\15266\\AppData\\Local\\Python\\pythoncore-3.14-64\\python.exe
  (pitfall #45: the Git-Bash `python` alias is a broken stub; always use the
   full path. Set PYTHONUTF8=1 for Chinese consoles.)

EXIT CODE: 0 = analysed, 2 = one or more inputs could not be read.
"""

import argparse
import glob
import os
import re
import sys

# ---------------------------------------------------------------------------
# register offset decode for axi_lite_regs (round3b RTL map; word offsets are
# s_axi_axaddr[7:2], so byte offset = word * 4)
# ---------------------------------------------------------------------------
REG_MAP = {
    0x00: "MODE",
    0x04: "RD_SLOT",
    0x08: "WM_WR",
    0x0C: "WM_RD/SET_ENGINE",
    0x10: "WM_DROP",
    0x14: "SLOTMAP",
    0x18: "STATUS",
    0x1C: "ID",
    0x20: "GET_LAT_W",
    0x24: "GET_LAT_R",
    0x34: "DMA_REQ",
    0x38: "ARL",
    0x3C: "EMIT",
    0x40: "WR_REQ",
    0x44: "WR_DBG",
    0x48: "WRGO(write)",
    0x4C: "WRACK(write)",
}

# g_step map (diagnostic firmware sw/j3_soft/src/main.c 2026-10-19)
GSTEP_MAP = {
    1: "serve_any entry",
    2: "after dread(REGS_BASE+0x34) DMA_REQ read",
    3: "no read request -> write service",
    9: "read request -> serve_dma_once()",
    10: "serve_write_once entry",
    11: "after dread(R_WRDBG 0x44)",
    12: "after dread(R_WRREQ 0x40)",
    13: "before S2MM_LENGTH write",
    14: "after S2MM_LENGTH write",
    15: "after R_WRGO write (+0x48)",
    16: "after busy_ms(20)",
    17: "after dread(S2MM_LENGTH)",
    18: "after dread(S2MM_DMASR) + s2cr/wreq/wdbg snapshots",
    19: "serve_write_once return",
}

S2MM_STATE_MAP = {0: "IDLE", 1: "WAITGO", 2: "STREAM", 3: "PUSH",
                  4: "WAITDONE", 5: "DRAIN", 6: "HALT"}

LWST_MAP = {0: "LW_IDLE", 1: "LW_EXEC", 2: "LW_CLOSE"}
LRST_MAP = {0: "LR_IDLE", 1: "LR_RACK", 2: "LR_DRQ", 3: "LR_DACK"}

STUCK_BIT_MAP = {
    0: "lrst != LR_IDLE (read FSM busy >256 cycles)",
    1: "lwst != LW_IDLE (write FSM busy >256 cycles)",
    2: "arvalid && !arready (AR not accepted >256 cycles)",
    3: "rvalid && !rready (R not consumed >256 cycles)",
}

# ---------------------------------------------------------------------------
# round3c hypothesis signatures (Lead request 2026-10-19)
#   Evaluated on the LAST sample of the post-trigger window (the static wedge
#   state), plus whole-window guards where noted, so that a bus that merely
#   returned to idle is NOT mis-classified.
#     H-reset     : rstuser_evt (bit30) == 1  => user-domain reset mismatch first
#     H-ARnever   : arvalid=0 & arready=1 & rvalid=0 & lwst=lrst=0 & mailbox all 0
#                   AND no AR handshake anywhere in the window
#                   => upstream MCU/interconnect never issued the read
#     H-acklost   : lrst!=0 & r_req=1 & r_ack_s1=0  (read mailbox C return lost)
#                   or lwst!=0 & a_req=1 & a_ack_s1=0 (write mailbox A return lost)
#     H-bstuck    : bvalid=1 & bready=0 & lwst!=0 & arvalid=1 & arready=0
#                   (B response not consumed -> read frozen)
#     H-rvalid    : rvalid=1 & rready=0 & lrst!=0
#     H-false-hs  : AR/AW/W handshake in the same sample as a non-IDLE FSM state
#                   (must be impossible after lite fix2; indicates a stale netlist
#                   or a probe/layout mismatch rather than a protocol behaviour)
#   Output marker: R3C_ILA4_HYPOTHESIS: <TAG> | <evidence>
#   No match      : R3C_ILA4_HYPOTHESIS: UNCLASSIFIED | ... + R3C_ILA4_BITS_LAST:
# ---------------------------------------------------------------------------
ILA4_MB_KEYS = ("a_req", "a_ack_s1", "r_req", "r_ack_s1", "d_req_s1", "d_ack")
ILA4_SIG_KEYS = ("arvalid", "arready", "rvalid", "rready", "awvalid",
                 "awready", "wvalid", "wready", "bvalid", "bready",
                 "lwst", "lrst", "a_req", "a_ack_s1", "r_req", "r_ack_s1",
                 "d_req_s1", "d_ack", "aresetn", "rstuser_s2",
                 "rstuser_evt", "stuck", "stuck_or")
ILA4_HYP_ORDER = ("H-reset", "H-ARnever", "H-acklost", "H-bstuck",
                  "H-rvalid", "H-false-hs")


def _last_val(seq):
    if seq is None or len(seq) == 0:
        return None
    return seq[-1]


def _aligned_len(*seqs):
    n = None
    for s in seqs:
        if s is not None:
            if n is None or len(s) < n:
                n = len(s)
    return n


def _false_handshakes(ctx):
    """Handshakes seen while the corresponding lite FSM is NOT in IDLE."""
    av, ar = ctx.get("av"), ctx.get("ar")
    awv, awr = ctx.get("awv"), ctx.get("awr")
    wv, wr = ctx.get("wv"), ctx.get("wr")
    lwst, lrst = ctx.get("lwst"), ctx.get("lrst")
    n = _aligned_len(av, ar, awv, awr, wv, wr, lwst, lrst)
    out = []
    if not n:
        return out
    for i in range(n):
        if av is not None and ar is not None and av[i] and ar[i]:
            lv = lrst[i] if lrst is not None else None
            if lv not in (None, 0):
                out.append((i, "AR", lv))
        if awv is not None and awr is not None and awv[i] and awr[i]:
            lv = lwst[i] if lwst is not None else None
            if lv not in (None, 0):
                out.append((i, "AW", lv))
        if wv is not None and wr is not None and wv[i] and wr[i]:
            lv = lwst[i] if lwst is not None else None
            if lv not in (None, 0):
                out.append((i, "W", lv))
    return out


def classify_ila4_hypotheses(ctx):
    """Return [(tag, evidence), ...] ordered by ILA4_HYP_ORDER."""
    hyp = {}
    sig = ctx.get("sig", {})
    mb = ctx.get("mailbox", {})
    reset = ctx.get("reset", {})

    av_l = _last_val(sig.get("arvalid"))
    ar_l = _last_val(sig.get("arready"))
    rv_l = _last_val(sig.get("rvalid"))
    rr_l = _last_val(sig.get("rready"))
    bv_l = _last_val(sig.get("bvalid"))
    br_l = _last_val(sig.get("bready"))
    lwst_l = _last_val(sig.get("lwst"))
    lrst_l = _last_val(sig.get("lrst"))

    # ---- H-reset: user-domain reset mismatch (sticky "was low" flag) ----
    ev = reset.get("rstuser_evt")
    if ev is not None and any(v == 1 for v in ev):
        first = next(i for i, v in enumerate(ev) if v == 1)
        hyp["H-reset"] = ("rstuser_evt(bit30)=1 from sample %d (sticky) =>"
                          " rst_user_n was low while aresetn=%s/rstuser_s2=%s;"
                          " user-domain reset mismatch takes priority"
                          % (first, _last_val(reset.get("aresetn")),
                             _last_val(reset.get("rstuser_s2"))))

    # ---- H-ARnever: upstream never issued the read ----
    mb_vals = {k: _last_val(mb.get(k)) for k in ILA4_MB_KEYS}
    mb_ok = all((v is None) or (v == 0) for v in mb_vals.values())
    if (av_l == 0 and ar_l == 1 and rv_l == 0 and lwst_l == 0 and lrst_l == 0
            and mb_ok and not ctx.get("ar_hs")):
        hyp["H-ARnever"] = ("arvalid(last)=0 arready(last)=1 rvalid(last)=0"
                            " lwst=0 lrst=0 mailbox_last=(%s) AR_handshakes_in_window=0"
                            " => no AR was ever issued; the lite_regs was not read"
                            " (suspect upstream MCU/interconnect, NOT lite_regs internal)"
                            % ", ".join("%s=%s" % (k, v) for k, v in mb_vals.items()))

    # ---- H-acklost: cross-domain return path lost ----
    rreq_l = _last_val(mb.get("r_req"))
    rack_l = _last_val(mb.get("r_ack_s1"))
    areq_l = _last_val(mb.get("a_req"))
    aack_l = _last_val(mb.get("a_ack_s1"))
    if lrst_l not in (None, 0) and rreq_l == 1 and rack_l == 0:
        hyp["H-acklost"] = ("lrst=%s r_req=1 r_ack_s1=0 => read mailbox C return"
                            " lost (lite waits in LR_RACK; user domain never acked)"
                            % lrst_l)
    elif lwst_l not in (None, 0) and areq_l == 1 and aack_l == 0:
        hyp["H-acklost"] = ("lwst=%s a_req=1 a_ack_s1=0 => write mailbox A return"
                            " lost (lite waits in LW_EXEC; user domain never acked)"
                            % lwst_l)

    # ---- H-bstuck: B response not consumed -> read frozen ----
    if (bv_l == 1 and br_l == 0 and lwst_l not in (None, 0)
            and av_l == 1 and ar_l == 0):
        hyp["H-bstuck"] = ("bvalid=1 bready=0 lwst=%s arvalid=1 arready=0 =>"
                           " write response not consumed; the read FSM is frozen"
                           " out of LR_IDLE by the pending B" % lwst_l)

    # ---- H-rvalid: R beat not consumed ----
    if rv_l == 1 and rr_l == 0 and lrst_l not in (None, 0):
        hyp["H-rvalid"] = ("rvalid=1 rready=0 lrst=%s => read data beat was never"
                           " consumed" % lrst_l)

    # ---- H-false-hs: handshake while FSM non-IDLE (impossible after fix2) ----
    fh = _false_handshakes(ctx)
    if fh:
        shown = ", ".join("sample=%d %s(lwst/lrst=%s)" % (i, ch, st)
                          for i, ch, st in fh[:6])
        hyp["H-false-hs"] = ("%d handshake(s) accepted while the FSM was not IDLE:"
                             " %s => protocol violation signature; after lite fix2"
                             " this must not happen (stale netlist / probe layout?)"
                             % (len(fh), shown))

    return [(t, hyp[t]) for t in ILA4_HYP_ORDER if t in hyp]


def print_ila4_hypotheses(hyps, ctx):
    if hyps:
        for tag, evidence in hyps:
            print("  R3C_ILA4_HYPOTHESIS: %s | %s" % (tag, evidence))
        return
    print("  R3C_ILA4_HYPOTHESIS: UNCLASSIFIED | no signature matched on the last"
          " sample; all decoded last values follow")
    sig = ctx.get("sig", {})
    parts = []
    for k in ILA4_SIG_KEYS:
        parts.append("%s=%s" % (k, _last_val(sig.get(k))))
    print("  R3C_ILA4_BITS_LAST: " + " ".join(parts))
    raw = ctx.get("packed_bits")
    if raw:
        print("  R3C_ILA4_RAW_BITS_LAST: " + " ".join(
            "b%d=%s" % (k, raw[k][-1] if raw[k] else None) for k in sorted(raw)))


ILA5_HYP_ORDER = ("GO_NOT_AT_BRIDGE", "GO_AT_BRIDGE_GO_OK_0",
                  "GO_AT_BRIDGE_GO_OK_UNKNOWN",
                  "GO_AT_BRIDGE_GO_OK_1_NOT_STREAM", "INTR_STICKY",
                  "ENTERED_STREAM", "GO_UI_PROBE_MISSING")


def classify_ila5_hypotheses(go, ack, intr, go_ok, state):
    """Return [(tag, evidence), ...] ordered by ILA5_HYP_ORDER."""
    hyp = {}
    n = _aligned_len(go, ack, intr, go_ok, state) or 0
    go_rise = edges(go) if go is not None else []
    stream_idx = None
    if state is not None:
        for i, v in enumerate(state):
            if v == 2:
                stream_idx = i
                break
    if go is None:
        hyp["GO_UI_PROBE_MISSING"] = ("no dbg_wd_go_ui probe in this CSV => GO"
                                      " arrival cannot be judged (legacy ILA5?)")
    elif not go_rise:
        # An entirely idle window carries no evidence either way: report
        # UNCLASSIFIED (no hypothesis) instead of blaming the GO path.
        active = False
        if state is not None and any(v not in (None, 0) for v in state):
            active = True
        if ack is not None and any(ack):
            active = True
        if intr is not None and any(intr):
            active = True
        if go_ok is not None and any(go_ok):
            active = True
        if active:
            hyp["GO_NOT_AT_BRIDGE"] = ("go_ui rising=0 over %d samples while other"
                                       " S2MM activity IS present => GO pulse never"
                                       " reached the ui/bridge (or the capture"
                                       " window missed it)" % n)
    else:
        go_first = go_rise[0]
        gok_any = (any(v for v in go_ok) if go_ok is not None else None)
        if gok_any is False:
            hyp["GO_AT_BRIDGE_GO_OK_0"] = ("go_ui rose at sample %d but go_ok"
                                           " never went high => bridge WAITGO did"
                                           " not observe the GO" % go_first)
        elif gok_any is None:
            hyp["GO_AT_BRIDGE_GO_OK_UNKNOWN"] = ("go_ui rose at sample %d but the"
                                                 " go_ok probe is absent => GO"
                                                 " visibility at the bridge unknown"
                                                 % go_first)
        elif stream_idx is None:
            hyp["GO_AT_BRIDGE_GO_OK_1_NOT_STREAM"] = (
                "go_ui@%d and go_ok seen, but s2mm_state never reached 2(STREAM)"
                " (last=%s) => write engine armed but the stream never started"
                % (go_first, state[-1] if state else None))
    if intr is not None:
        intr_rise = edges(intr)
        if intr_rise:
            falls = [i for i in edges(intr, rising=False) if i > intr_rise[0]]
            if not falls and intr[-1]:
                hyp["INTR_STICKY"] = ("intr_ui rose at sample %d and never"
                                      " deasserted (last=1) => S2MM introut sticky"
                                      " / no retirement handshake seen"
                                      % intr_rise[0])
    if stream_idx is not None:
        hyp["ENTERED_STREAM"] = ("s2mm_state=2(STREAM) at sample %d (hist=[%s])"
                                 % (stream_idx, hist(state, S2MM_STATE_MAP)))
    return [(t, hyp[t]) for t in ILA5_HYP_ORDER if t in hyp]


def print_ila5_hypotheses(hyps, go, ack, intr, go_ok, state):
    if hyps:
        for tag, evidence in hyps:
            print("  R3C_ILA5_HYPOTHESIS: %s | %s" % (tag, evidence))
        return
    print("  R3C_ILA5_HYPOTHESIS: UNCLASSIFIED | no signature matched")
    print("  R3C_ILA5_BITS_LAST: go_ui=%s ack_ui=%s intr_ui=%s go_ok=%s"
          " s2mm_state=%s"
          % (_last_val(go), _last_val(ack), _last_val(intr), _last_val(go_ok),
             _last_val(state)))



# ---------------------------------------------------------------------------
# CSV loading
# ---------------------------------------------------------------------------
class IlaCsv(object):
    def __init__(self, path):
        self.path = path
        self.names = []          # raw header names, in column order
        self.base = []           # normalized names (no [msb:lsb])
        self.radix = []          # per-column radix from the "Radix -" line
        self.cols = {}           # base name -> list[Optional[int]]
        self.numbuf = []         # "Sample in Buffer" column
        self.trigger = []        # "TRIGGER" column (0/1)
        self.nrows = 0
        self.data_start_line = 0
        self.parse_errors = 0

    def load(self):
        with open(self.path, "r", encoding="utf-8", errors="replace",
                  newline="") as fh:
            raw = fh.read()
        if raw.startswith("\ufeff"):
            raw = raw[1:]
        lines = raw.split("\n")
        if not lines or lines[0].strip() == "":
            raise ValueError("empty CSV")
        header = lines[0].rstrip("\r")
        self.names = [h.strip() for h in header.split(",")]
        self.base = [_base_name(n) for n in self.names]
        self.radix = ["HEX"] * len(self.names)
        idx = 1
        if idx < len(lines) and lines[idx].lstrip().startswith("Radix"):
            rad = lines[idx].rstrip("\r")
            pos = rad.find("-")
            if pos >= 0:
                items = [x.strip().upper() for x in rad[pos + 1:].split(",")]
                for i, it in enumerate(items[:len(self.names)]):
                    self.radix[i] = it
            idx += 1
        self.data_start_line = idx + 1
        values = [[] for _ in self.names]
        for line in lines[idx:]:
            line = line.rstrip("\r")
            if line.strip() == "":
                continue
            cells = line.split(",")
            if len(cells) < len(self.names):
                self.parse_errors += 1
                continue
            for i in range(len(self.names)):
                values[i].append(parse_cell(cells[i], self.radix[i]))
            self.nrows += 1
        for i, nm in enumerate(self.base):
            self.cols[nm] = values[i]
        # special columns (exact header names)
        for key, target in (("Sample in Buffer", "numbuf"),
                            ("TRIGGER", "trigger")):
            for i, nm in enumerate(self.names):
                if nm.strip().lower() == key.lower():
                    setattr(self, target, values[i])
                    break
        return self

    def get(self, name, default=None):
        return self.cols.get(name, default)

    def has(self, name):
        return name in self.cols


def _base_name(n):
    n = n.strip()
    n = re.sub(r"\[[0-9]+\s*:\s*[0-9]+\]", "", n)
    n = n.strip()
    return n


def _width_of(raw_name):
    m = re.search(r"\[\s*([0-9]+)\s*:\s*([0-9]+)\s*\]", raw_name)
    if m:
        return abs(int(m.group(1)) - int(m.group(2))) + 1
    return 1


def parse_cell(txt, radix):
    t = txt.strip()
    if t == "" or t.lower() in ("x", "xx", "z", "undef", "nan"):
        return None
    if re.match(r"^[0-9]+$", t):
        # single bits / unsigned columns are decimal; HEX columns are hex.
        # A decimal string like "0000" is identical in either radix, but
        # "10" differs; the Radix line disambiguates it.
        if radix in ("UNSIGNED", "DECIMAL", "SIGNED"):
            return int(t, 10)
        return int(t, 16)
    if re.match(r"^0[xX][0-9a-fA-F]+$", t):
        return int(t, 16)
    if re.match(r"^[01]+$", t) and radix == "BINARY":
        return int(t, 2)
    if re.match(r"^[0-9a-fA-F]+$", t):
        return int(t, 16)
    return None


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
def fmt_hex(v, width=None):
    if v is None:
        return "None"
    if width is None:
        return "0x%X" % v
    digits = max(1, (width + 3) // 4)
    return "0x%0*X" % (digits, v)


def build_alias(csv):
    """Map short logical names -> actual CSV base column names (first match)."""
    alias = {}

    def take(logical, patterns, exclude=()):
        for pat in patterns:
            rx = re.compile(pat, re.IGNORECASE)
            for nm in csv.base:
                if nm in alias.values():
                    continue
                if any(ex.search(nm) for ex in exclude):
                    continue
                if rx.search(nm):
                    alias[logical] = nm
                    return nm
        return None

    # order matters: longer / more specific names first
    take("arvalid", [r"arvalid"])
    take("arready", [r"arready"])
    take("rvalid", [r"rvalid"])
    take("rready", [r"rready"])
    take("awvalid", [r"awvalid"])
    take("awready", [r"awready"])
    take("wvalid", [r"wvalid"])
    take("wready", [r"wready"])
    take("bvalid", [r"bvalid"])
    take("bready", [r"bready"])
    take("araddr", [r"araddr"])
    take("awaddr", [r"awaddr"])
    take("lwst", [r"lwst"])
    take("lrst", [r"lrst"])
    take("stuck_or", [r"stuck_or", r"stuckor"])
    take("stuck", [r"stuck"])
    # round3c ILA5 probe5 first (go/ack/intr/go_ok), so that 'd_ack' cannot
    # steal the 'dbg_wd_ack_ui' column via the substring 'd_ack'
    take("go_ui", [r"(^|_)go_ui"])
    take("go_ok", [r"(^|_)go_ok"])
    take("ack_ui", [r"(^|_)ack_ui"])
    take("intr_ui", [r"(^|_)intr_ui", r"introut"])
    take("a_req", [r"(^|_)a_req(?!.*ack)"])
    take("a_ack_s1", [r"(^|_)a_ack_s1", r"(^|_)a_ack"])
    take("r_req", [r"(^|_)r_req"])
    take("r_ack_s1", [r"(^|_)r_ack_s1", r"(^|_)r_ack"])
    take("d_req_s1", [r"(^|_)d_req_s1", r"(^|_)d_req"])
    take("d_ack", [r"(^|_)d_ack"])
    take("aresetn", [r"aresetn"])
    take("rstuser_evt", [r"rstuser.*evt", r"rstuser_evt"])
    take("rstuser_s2", [r"rstuser_s2", r"rstuser"])
    take("s2mm_state", [r"s2mm_state"])
    take("tdata64", [r"tdata64"])
    take("tkeep8", [r"tkeep8"])
    take("tvalid", [r"s2mm_tvalid", r"(^|_)tvalid"])
    take("tready", [r"s2mm_tready", r"(^|_)tready"])
    take("tlast", [r"s2mm_tlast", r"(^|_)tlast"])
    return alias


def col_values(csv, alias, logical):
    nm = alias.get(logical)
    if nm is None:
        return None
    return csv.cols[nm]


def values_of(csv, logical_token):
    """Generic token search used by the legacy/generic profiles.

    Prefer an exact (case-insensitive) probe-name match, then fall back to a
    substring match. This avoids e.g. token 'dbg_mem_ost' matching the longer
    'dbg_mem_ost_s' column when both families exist.
    """
    tok = logical_token.lower()
    for nm in csv.base:
        if nm.lower() == tok:
            return csv.cols[nm], nm
    for nm in csv.base:
        if tok in nm.lower():
            return csv.cols[nm], nm
    return None, None


def edges(seq, rising=True):
    """Return indices where seq goes low->high (rising) / high->low."""
    out = []
    prev = None
    for i, v in enumerate(seq):
        b = bool(v) if v is not None else None
        if b is None:
            prev = None
            continue
        if prev is not None:
            if rising and b and not prev:
                out.append(i)
            if (not rising) and (not b) and prev:
                out.append(i)
        prev = b
    return out


def handshakes(valid, ready):
    """Return sample indices where valid & ready are both high.

    In AXI a handshake happens on EVERY cycle where VALID and READY are both
    high (back-to-back transfers keep both high), so this counts cycles, not
    rising edges. Used for AR/R/AW/W/B counts and AXI-Stream beats.
    """
    idx = []
    for i, (v, r) in enumerate(zip(valid, ready)):
        if bool(v) and bool(r):
            idx.append(i)
    return idx


def longest_true_run(seq):
    best = 0
    cur = 0
    for v in seq:
        if v:
            cur += 1
            if cur > best:
                best = cur
        else:
            cur = 0
    return best


def counter_summary(csv, nm):
    seq = csv.cols.get(nm, [])
    vals = [v for v in seq if v is not None]
    if not vals:
        return (None, None, None, 0)
    return (vals[0], vals[-1], vals[-1] - vals[0], len(set(vals)))


def hist(seq, mapping):
    out = {}
    for v in seq:
        if v is not None:
            out[v] = out.get(v, 0) + 1
    parts = []
    for k in sorted(out):
        label = mapping.get(k, str(k)) if mapping else str(k)
        parts.append("%s=%d" % (label, out[k]))
    return ", ".join(parts)


def print_last_rows(csv, alias, keys, last_n):
    print("  LAST_%d_ROWS (sample | %s):" % (last_n, " ".join(keys)))
    n = csv.nrows
    start = max(0, n - last_n)
    for i in range(start, n):
        cells = []
        for k in keys:
            seq = col_values(csv, alias, k)
            if seq is None:
                cells.append("?")
            else:
                v = seq[i]
                cells.append("None" if v is None else str(v))
        print("    %5d | %s" % (i, " ".join(cells)))


# ---------------------------------------------------------------------------
# profile detection
# ---------------------------------------------------------------------------
def detect_profile(csv, forced=None):
    if forced and forced != "auto":
        return forced.upper()
    base = [b.lower() for b in csv.base]
    joined = " ".join(base)
    if any(b.startswith("dbg_l_") for b in base) or "stuck_or" in joined \
            or "lwst" in joined or "lrst" in joined:
        return "ILA4"
    if ("wd_go_ui" in joined or "wd_intr_ui" in joined or
            any(b.startswith("dbg_wd_") for b in base) or "tdata64" in joined):
        return "ILA5"
    if "dbg_mem_wm" in joined or "dbg_mem2_wm" in joined:
        return "LEGACY_UI"
    if "dbg_mem_u_wr" in joined or "dbg_mem2_u_wr" in joined:
        return "LEGACY_USER"
    return "GENERIC"


# ---------------------------------------------------------------------------
# ILA4: axi_lite_regs wedge analysis
# ---------------------------------------------------------------------------
# round3c hardware layout (rtl/axi_lite_regs.v dbg_o + scripts/build_synth_only.tcl
# 2026-10-19): the observation bus is packed as dbg_o[35:0] -> BD port
# dbg_l_bus[35:0] -> top-level nets dbg_l_bus[0]..dbg_l_bus[35] on u_ila_4
# probe0 (36b) + probe1 (same bit35 as the trigger).  The exported CSV columns
# are therefore dbg_l_bus[0] .. dbg_l_bus[35] (plus a duplicate bit35 column
# from probe1, usually named dbg_l_bus[35]_1).  materialize_packed_ila4()
# rebuilds the logical named signals from this bit map so the rest of the
# analysis (and the -csv parser) stays layout independent.
DBGL_BITNAMES = {
    0: "dbg_l_arvalid", 1: "dbg_l_arready", 2: "dbg_l_rvalid",
    3: "dbg_l_rready", 4: "dbg_l_awvalid", 5: "dbg_l_awready",
    6: "dbg_l_wvalid", 7: "dbg_l_wready", 8: "dbg_l_bvalid",
    9: "dbg_l_bready",
    18: "dbg_l_lwst_b0", 19: "dbg_l_lwst_b1",
    20: "dbg_l_lrst_b0", 21: "dbg_l_lrst_b1",
    22: "dbg_l_a_req", 23: "dbg_l_a_ack_s1", 24: "dbg_l_r_req",
    25: "dbg_l_r_ack_s1", 26: "dbg_l_d_req_s1", 27: "dbg_l_d_ack",
    28: "dbg_l_aresetn", 29: "dbg_l_rstuser_s2", 30: "dbg_l_rstuser_evt",
    31: "dbg_l_stuck_b0", 32: "dbg_l_stuck_b1",
    33: "dbg_l_stuck_b2", 34: "dbg_l_stuck_b3",
    35: "dbg_l_stuck_or",
}
DBGL_AR_CLASS = {10: 13, 11: 16, 12: 17}    # +0x34 DMA_REQ / +0x40 WR_REQ / +0x44 WR_DBG
DBGL_AW_CLASS = {14: 3, 15: 18, 16: 19}     # +0x0C / +0x48 SET_WRGO / +0x4C SET_WRACK
DBGL_CLASS_OTHER = 0x3F                     # byte 0xFC = unmapped/other address


def _add_synth(csv, name, seq):
    if seq is None:
        return
    if name in csv.cols:
        return
    csv.cols[name] = seq
    csv.base.append(name)


def materialize_packed_ila4(csv):
    """If the CSV carries packed dbg_l_bus[N] columns, synthesize the logical
    dbg_l_* named columns. Returns True when the packed layout was used."""
    bits = {}
    for nm in csv.base:
        m = re.match(r"^dbg_l_bus\[(\d+)\]", nm, re.IGNORECASE)
        if m:
            n = int(m.group(1))
            if n not in bits:
                bits[n] = csv.cols[nm]
    if not bits:
        return False

    def b(n):
        return bits.get(n)

    # one-hot comparator address bits -> synthetic word-offset column
    def addr_from(class_map, other_bit):
        pairs = [(word, b(bit)) for bit, word in class_map.items() if b(bit) is not None]
        other = b(other_bit) if other_bit is not None else None
        if not pairs and other is None:
            return None
        out = []
        for i in range(csv.nrows):
            val = None
            for word, seq in pairs:
                if seq[i]:
                    val = word
                    break
            if val is None and other is not None and other[i]:
                val = DBGL_CLASS_OTHER
            out.append(val)
        return out

    for bit, name in DBGL_BITNAMES.items():
        _add_synth(csv, name, b(bit))
    _add_synth(csv, "dbg_l_araddr", addr_from(DBGL_AR_CLASS, 13))
    _add_synth(csv, "dbg_l_awaddr", addr_from(DBGL_AW_CLASS, 17))
    # combine 2-bit FSM state columns
    if b(18) is not None and b(19) is not None:
        _add_synth(csv, "dbg_l_lwst",
                   [None if (x is None or y is None) else ((x & 1) | ((y & 1) << 1))
                    for x, y in zip(b(18), b(19))])
    if b(20) is not None and b(21) is not None:
        _add_synth(csv, "dbg_l_lrst",
                   [None if (x is None or y is None) else ((x & 1) | ((y & 1) << 1))
                    for x, y in zip(b(20), b(21))])
    if all(b(k) is not None for k in (31, 32, 33, 34)):
        stuck = []
        for x in zip(b(31), b(32), b(33), b(34)):
            if any(v is None for v in x):
                stuck.append(None)
            else:
                stuck.append((x[0] & 1) | ((x[1] & 1) << 1) |
                             ((x[2] & 1) << 2) | ((x[3] & 1) << 3))
        _add_synth(csv, "dbg_l_stuck", stuck)
    print("  ILA4_LAYOUT: PACKED round3c dbg_l_bus[35:0] (u_ila_4 probe0=36b +"
          " probe1=bit35); logical signals rebuilt from the RTL bit map")
    print("  ILA4_BITMAP: " + ", ".join("%d=%s" % (k, DBGL_BITNAMES[k])
                                       for k in sorted(DBGL_BITNAMES)))
    csv.packed_bits = bits
    return True


def analyze_ila4(csv, last_n):
    packed = materialize_packed_ila4(csv)
    if not packed:
        print("  ILA4_LAYOUT: named dbg_l_* alias nets (audit-plan layout)")
    alias = build_alias(csv)
    print("  PROBE_ALIAS:")
    for k in sorted(alias):
        print("    %-12s -> %s" % (k, alias[k]))
    missing = [k for k in ("arvalid", "arready", "rvalid", "rready") if k not in alias]
    if missing:
        print("  WARN_MISSING_CORE_PROBES: %s (not a full AXI-lite handshake set;"
              " verdict will be limited)" % ",".join(missing))

    av = col_values(csv, alias, "arvalid")
    ar = col_values(csv, alias, "arready")
    rv = col_values(csv, alias, "rvalid")
    rr = col_values(csv, alias, "rready")
    awv = col_values(csv, alias, "awvalid")
    awr = col_values(csv, alias, "awready")
    wv = col_values(csv, alias, "wvalid")
    wr = col_values(csv, alias, "wready")
    bv = col_values(csv, alias, "bvalid")
    br = col_values(csv, alias, "bready")

    ar_hs = handshakes(av, ar) if av is not None and ar is not None else []
    r_hs = handshakes(rv, rr) if rv is not None and rr is not None else []
    aw_hs = handshakes(awv, awr) if awv is not None and awr is not None else []
    w_hs = handshakes(wv, wr) if wv is not None and wr is not None else []
    b_hs = handshakes(bv, br) if bv is not None and br is not None else []

    print("  HANDSHAKE_COUNTS: AR=%d R=%d AW=%d W=%d B=%d"
          % (len(ar_hs), len(r_hs), len(aw_hs), len(w_hs), len(b_hs)))
    if av is not None:
        print("  VALID_SEEN: arvalid=%d rvalid=%d awvalid=%d wvalid=%d bvalid=%d"
              % (sum(1 for v in av if v), sum(1 for v in rv if v) if rv is not None else -1,
                 sum(1 for v in awv if v) if awv is not None else -1,
                 sum(1 for v in wv if v) if wv is not None else -1,
                 sum(1 for v in bv if v) if bv is not None else -1))

    # ---- address sequence decode ----
    # round3c probe plan: dbg_l_araddr[5:0] = s_axi_araddr[7:2] (WORD offset),
    # so byte offset = word * 4. Auto-detect: if any sampled address > 63 the
    # probe must be a byte address already (defensive; --addr-shift overrides).
    addr_vals = []
    for k in ("araddr", "awaddr"):
        seq = col_values(csv, alias, k)
        if seq is not None:
            addr_vals += [v for v in seq if v is not None]
    addr_shift = 4
    if addr_vals and max(addr_vals) <= 63:
        addr_shift = 4
        print("  ADDR_DECODE: word offset x4 (probe = s_axi_axaddr[7:2])")
    elif addr_vals:
        addr_shift = 1
        print("  ADDR_DECODE: byte address as-is (probe wider than [7:2])")
    else:
        print("  ADDR_DECODE: no address probe")

    def decode_addr_word(v):
        if v is None:
            return "None"
        byte = v * addr_shift
        return "word=0x%02X byte=0x%02X %s" % (v, byte, REG_MAP.get(byte, "UNKNOWN"))

    for label, hs, addr_key in (("AR", ar_hs, "araddr"), ("AW", aw_hs, "awaddr")):
        seq = col_values(csv, alias, addr_key)
        vseq = av if label == "AR" else awv
        rseq = ar if label == "AR" else awr
        print("  %s_ADDR_SEQ:" % label)
        if seq is None:
            print("    (no %s probe)" % addr_key)
            continue
        if vseq is None or rseq is None:
            print("    (no %s channel valid/ready probes)" % label)
            continue
        seen = []
        prev = False
        for i, (valid, ready) in enumerate(zip(vseq, rseq)):
            cur = bool(valid) and bool(ready)
            if cur and not prev and seq[i] is not None:
                seen.append((i, seq[i]))
            prev = cur
        if not seen:
            print("    (none; no %s address handshake in window)" % label)
        for i, v in seen[-24:]:
            print("    sample=%-5d %s" % (i, decode_addr_word(v)))
        print("    %s_ADDR_COUNT=%d" % (label, len(seen)))

    # ---- last AR -> did RVALID come back? ----
    last_ar_addr = None
    if ar_hs and alias.get("araddr"):
        seq = col_values(csv, alias, "araddr")
        last_ar_addr = seq[ar_hs[-1]] if ar_hs[-1] < len(seq) else None
    r_after_last_ar = [i for i in r_hs if ar_hs and i >= ar_hs[-1]]
    print("  LAST_AR: sample=%s %s" % (ar_hs[-1] if ar_hs else "None",
                                       decode_addr_word(last_ar_addr)))
    print("  R_AFTER_LAST_AR: count=%d" % len(r_after_last_ar))

    # ---- sustained wait detection (in the last quarter of the window) ----
    n = csv.nrows
    tail_start = max(0, n - max(last_n, n // 4))
    def tail(seq):
        if seq is None:
            return []
        return seq[tail_start:]

    wait = {}
    if ar is not None:
        wait["arvalid&!arready"] = sum(1 for a, b in zip(tail(av) or [], tail(ar)) if a and not b)
    if rr is not None:
        wait["rvalid&!rready"] = sum(1 for a, b in zip(tail(rv) or [], tail(rr)) if a and not b)
    if awr is not None:
        wait["awvalid&!awready"] = sum(1 for a, b in zip(tail(awv) or [], tail(awr)) if a and not b)
    if wr is not None:
        wait["wvalid&!wready"] = sum(1 for a, b in zip(tail(wv) or [], tail(wr)) if a and not b)
    if br is not None:
        wait["bvalid&!bready"] = sum(1 for a, b in zip(tail(bv) or [], tail(br)) if a and not b)
    print("  TAIL_WAIT_CYCLES (last %d samples): %s"
          % (min(last_n, n), ", ".join("%s=%d" % (k, v) for k, v in wait.items()) or "n/a"))

    # ---- FSM states + mailbox + reset ----
    lwst = col_values(csv, alias, "lwst")
    lrst = col_values(csv, alias, "lrst")
    stuck = col_values(csv, alias, "stuck")
    stuck_or = col_values(csv, alias, "stuck_or")
    lwst_last = lwst[-1] if lwst else None
    lrst_last = lrst[-1] if lrst else None
    stuck_last = stuck[-1] if stuck else None
    stuck_or_last = stuck_or[-1] if stuck_or else None
    print("  STATE_LAST: lwst=%s(%s) lrst=%s(%s) stuck=%s stuck_or=%s"
          % (lwst_last, LWST_MAP.get(lwst_last, "?"),
             lrst_last, LRST_MAP.get(lrst_last, "?"),
             fmt_hex(stuck_last), stuck_or_last))
    if lwst is not None:
        print("  LWST_HIST: %s" % hist(lwst, LWST_MAP))
    if lrst is not None:
        print("  LRST_HIST: %s" % hist(lrst, LRST_MAP))
    for key in ("a_req", "a_ack_s1", "r_req", "r_ack_s1", "d_req_s1", "d_ack",
                "aresetn", "rstuser_s2", "rstuser_evt"):
        seq = col_values(csv, alias, key)
        if seq is None:
            continue
        print("  MAILBOX_LAST: %-12s last=%s high_cycles=%d rising=%d"
              % (key, seq[-1], sum(1 for v in seq if v), len(edges(seq))))

    print_last_rows(csv, alias, ["lwst", "lrst", "a_req", "a_ack_s1",
                                 "r_req", "r_ack_s1", "d_req_s1", "d_ack",
                                 "stuck", "stuck_or"], min(last_n, 8))

    # ---- round3c hypothesis signatures (Lead request 2026-10-19) ----
    sig = {}
    for k in ILA4_SIG_KEYS:
        sig[k] = col_values(csv, alias, k)
    mailbox = {}
    for k in ILA4_MB_KEYS:
        mailbox[k] = col_values(csv, alias, k)
    reset = {"aresetn": col_values(csv, alias, "aresetn"),
             "rstuser_s2": col_values(csv, alias, "rstuser_s2"),
             "rstuser_evt": col_values(csv, alias, "rstuser_evt")}
    hyp_ctx = {"sig": sig, "mailbox": mailbox, "reset": reset,
               "av": av, "ar": ar, "awv": awv, "awr": awr, "wv": wv, "wr": wr,
               "lwst": lwst, "lrst": lrst, "ar_hs": ar_hs,
               "packed_bits": getattr(csv, "packed_bits", None)}
    hyps = classify_ila4_hypotheses(hyp_ctx)

    # ---- verdict ----
    verdicts = []
    stuck_bits = []
    if stuck_last:
        stuck_bits = [b for b in range(4) if (stuck_last >> b) & 1]
    if stuck_or_last:
        verdicts.append("[L1] STUCK_OR=1 at end of window: lite_regs AXI window"
                        " is stuck; set bits=%s (%s)"
                        % (stuck_bits or "?", "; ".join(STUCK_BIT_MAP.get(b, str(b)) for b in stuck_bits)))
    if stuck_or is not None and not stuck_or_last:
        print("  NOTE: dbg_l_stuck_or=0 in this window: no >256-cycle wedge was"
              " observed in the captured window (a snapshot taken after the CPU"
              " was stopped/frozen may legitimately show 0; prefer a triggered"
              " capture armed before the stimulus)")

    if lrst_last is not None:
        if lrst_last == 1:
            verdicts.append("[L1] READ FSM stuck in LR_RACK: r_req fired but the"
                            " user-domain ack (r_ack_s1) never came => cross-domain"
                            " mailbox/user side did not answer the read request")
        elif lrst_last == 2:
            verdicts.append("[L1] READ FSM stuck in LR_DRQ: read request was acked"
                            " but the user-domain read data (d_req_s1) never came")
        elif lrst_last == 3:
            verdicts.append("[L1] READ FSM stuck in LR_DACK: d_ack is high and the"
                            " user domain has not dropped d_req")
    if lwst_last is not None:
        if lwst_last == 1:
            verdicts.append("[L1] WRITE FSM stuck in LW_EXEC: write command fired"
                            " (a_req=1) but the user-domain ack (a_ack_s1) never came")
        elif lwst_last == 2:
            verdicts.append("[L1] WRITE FSM stuck in LW_CLOSE: waiting for the user"
                            " domain to deassert a_ack (4-phase close)")

    if wait.get("arvalid&!arready", 0) > 0:
        verdicts.append("[L1] AR never accepted: arvalid=1 while arready=0 for %d"
                        " sampled cycles (read FSM not in LR_IDLE: blocked by pending"
                        " write/bvalid/rvalid)" % wait["arvalid&!arready"])
    if wait.get("rvalid&!rready", 0) > 0:
        verdicts.append("[L1] RVALID not consumed: rvalid=1 while rready=0 for %d"
                        " sampled cycles" % wait["rvalid&!rready"])
    if ar_hs and rv is not None and not r_after_last_ar:
        last = decode_addr_word(last_ar_addr)
        verdicts.append("[L1] AR accepted (sample %d, %s) but NO R beat after it:"
                        " the read data phase never completed" % (ar_hs[-1], last))
        if last_ar_addr is not None and last_ar_addr * addr_shift == 0x44:
            verdicts.append("[L1] LAST_AR reads +0x44 WR_DBG: consistent with the"
                            " firmware g_step=11 wedge (dread(R_WRDBG 0x44) never"
                            " returns) -- cross-check with r3c_diag.tcl G_STEP")
    if av is not None and ar is not None:
        run = longest_true_run([bool(a) and not bool(b) for a, b in zip(av, ar)])
        print("  LONGEST_ARVALID_NO_ARREADY_RUN: %d samples" % run)
    if rv is not None and rr is not None:
        run = longest_true_run([bool(a) and not bool(b) for a, b in zip(rv, rr)])
        print("  LONGEST_RVALID_NO_RREADY_RUN: %d samples" % run)

    if not verdicts:
        verdicts.append("[L1] no stuck wait identified in this window (either the"
                        " event was missed by the capture window, or the bus was"
                        " idle/healthy at this moment); judgement NOT obtained")
    print("  ILA4_VERDICT:")
    for v in verdicts:
        print("    %s" % v)
    print_ila4_hypotheses(hyps, hyp_ctx)
    return verdicts


# ---------------------------------------------------------------------------
# ILA5: S2MM write engine + GO/ACK/intr/state
# ---------------------------------------------------------------------------
def analyze_ila5(csv, last_n):
    alias = build_alias(csv)
    print("  PROBE_ALIAS:")
    for k in sorted(alias):
        print("    %-12s -> %s" % (k, alias[k]))
    go = col_values(csv, alias, "go_ui")
    ack = col_values(csv, alias, "ack_ui")
    intr = col_values(csv, alias, "intr_ui")
    go_ok = col_values(csv, alias, "go_ok")
    state = col_values(csv, alias, "s2mm_state")

    new_probe_ok = all(x is not None for x in (go, ack, intr, state))
    if not new_probe_ok:
        print("  NOTE: round3c probe5 missing (%s); falling back to round3b ILA5"
              " content (S2MM write stream) where available."
              % ",".join(k for k, v in (("go_ui", go), ("ack_ui", ack),
                                        ("intr_ui", intr), ("s2mm_state", state)) if v is None))

    verdicts = []
    if go is not None:
        go_rise = edges(go)
        go_fall = edges(go, rising=False)
        print("  GO_UI: rising=%d falling=%d first_rise=%s last_value=%s"
              % (len(go_rise), len(go_fall),
                 go_rise[0] if go_rise else "None", go[-1]))
        if not go_rise:
            verdicts.append("[L1] GO_UI never rose in the window: the firmware's"
                            " S2MM programming / +0x48 GO toggle did not reach the"
                            " bridge (or the capture window missed it)")
        else:
            verdicts.append("[L1] GO_UI reached the bridge at sample %d (%d pulse(s))"
                            % (go_rise[0], len(go_rise)))
    if ack is not None:
        print("  ACK_UI: rising=%d last_value=%s"
              % (len(edges(ack)), ack[-1]))
        if go is not None and not ack and go_rise:
            verdicts.append("[L1] bridge never ACKed the write request after GO")
        elif not ack:
            verdicts.append("[L1] ACK_UI never rose in the window")
    if go_ok is not None:
        print("  GO_OK: rising=%d last_value=%s"
              % (len(edges(go_ok)), go_ok[-1]))
    if intr is not None:
        intr_rise = edges(intr)
        intr_fall_after = []
        if intr_rise:
            intr_fall_after = [i for i in edges(intr, rising=False) if i > intr_rise[0]]
        print("  INTR_UI: rising=%d last_value=%s sticky_at_end=%s"
              % (len(intr_rise), intr[-1],
                 "YES" if (intr_rise and not intr_fall_after and intr[-1]) else "NO"))
        if intr_rise and not intr_fall_after and intr[-1]:
            verdicts.append("[L1] S2MM introut is STICKY: asserted at sample %d and"
                            " never deasserted in the window (no retirement seen)"
                            % intr_rise[0])
        elif intr_rise:
            verdicts.append("[L1] S2MM introut pulsed at sample %s (retirement event"
                            " visible)" % intr_rise[0])
        else:
            verdicts.append("[L1] S2MM introut never asserted in the window")
    if state is not None:
        st_hist = hist(state, S2MM_STATE_MAP)
        print("  S2MM_STATE: first=%s(%s) last=%s(%s) hist=[%s]"
              % (state[0], S2MM_STATE_MAP.get(state[0], "?"),
                 state[-1], S2MM_STATE_MAP.get(state[-1], "?"), st_hist))
        entered_stream = any(v == 2 for v in state if v is not None)
        if entered_stream:
            idx = next(i for i, v in enumerate(state) if v == 2)
            verdicts.append("[L1] S2MM entered STREAM (state=2) at sample %d => the"
                            " write stream started" % idx)
        else:
            verdicts.append("[L1] S2MM never entered STREAM (state=2) in the window;"
                            " final state=%s(%s)"
                            % (state[-1], S2MM_STATE_MAP.get(state[-1], "?")))
        if state[-1] == 6:
            verdicts.append("[L1] S2MM final state=6 HALT: fail-stop watchdog fired"
                            " (fault should be 1 in WR_DBG; recovery is firmware"
                            " ACK +0x4C or re-burn)")

    # round3b ILA5 fallback: S2MM write stream content
    tdata = col_values(csv, alias, "tdata64")
    tkeep = col_values(csv, alias, "tkeep8")
    tvalid = col_values(csv, alias, "tvalid")
    tready = col_values(csv, alias, "tready")
    tlast = col_values(csv, alias, "tlast")
    if tdata is not None and tvalid is not None and tready is not None:
        beats = handshakes(tvalid, tready)
        print("  S2MM_BEATS: count=%d" % len(beats))
        if beats:
            i = beats[0]
            print("  S2MM_FIRST_BEAT: sample=%d tdata=%s tkeep=%s tlast=%s"
                  % (i, fmt_hex(tdata[i], 64) if tdata is not None else "?",
                     fmt_hex(tkeep[i], 8) if tkeep is not None else "?",
                     tlast[i] if tlast is not None else "?"))
            if tdata[i] is not None:
                if tdata[i] == 0xD555555555555555:
                    verdicts.append("[L1] first S2MM beat tdata=0xD555555555555555"
                                    " (= 8B preamble + SFD as expected for len>=66)")
                else:
                    verdicts.append("[L1] first S2MM beat tdata=%s (NOT the expected"
                                    " 0xD555555555555555 preamble pattern)"
                                    % fmt_hex(tdata[i], 64))
        else:
            verdicts.append("[L1] no S2MM tvalid&tready beats in the window")

    print_last_rows(csv, alias, [k for k in ("go_ui", "ack_ui", "intr_ui",
                                             "go_ok", "s2mm_state") if k in alias],
                    min(last_n, 8))
    if not verdicts:
        verdicts.append("[L1] no GO/ACK/intr/state evidence available")
    print("  ILA5_VERDICT:")
    for v in verdicts:
        print("    %s" % v)
    hyps5 = classify_ila5_hypotheses(go, ack, intr, go_ok, state)
    print_ila5_hypotheses(hyps5, go, ack, intr, go_ok, state)
    return verdicts


# ---------------------------------------------------------------------------
# legacy profiles: bridge counter snapshots (round3b ILA3/ILA0)
# ---------------------------------------------------------------------------
COUNTER_TOKENS = [
    "dbg_mem_wm", "dbg_mem_wr_frm", "dbg_mem_rd_frm", "dbg_mem_stall",
    "dbg_mem_len_err", "dbg_mem_ost", "dbg_mem2_wm", "dbg_mem2_wr_frm",
    "dbg_mem2_rd_frm", "dbg_mem2_ost", "dbg_mem_u_wr", "dbg_mem_u_rd",
    "dbg_mem_u_drop", "dbg_mem_ost_s", "dbg_mem2_u_wr", "dbg_mem2_u_rd",
    "dbg_s2mm_reqpend", "dbg_wr_fault", "dbg_s2mm_state",
    "dbg_s2mm_tvalid", "dbg_s2mm_tready", "dbg_pfwd_en",
]


def analyze_legacy(csv, profile, last_n):
    verdicts = []
    print("  COUNTERS (first -> last, delta, distinct_values):")
    found = []
    for tok in COUNTER_TOKENS:
        seq, nm = values_of(csv, tok)
        if seq is None:
            continue
        found.append(nm)
        first, last, delta, ndist = counter_summary(csv, nm)
        if first is None:
            print("    %-22s (no samples)" % nm)
            continue
        if delta == 0:
            print("    %-22s %s -> %s  delta=0  (STATIC)" % (nm, first, last))
        else:
            print("    %-22s %s -> %s  delta=%+d distinct=%d"
                  % (nm, first, last, delta, ndist))
    # state histogram
    state_seq, state_nm = values_of(csv, "dbg_s2mm_state")
    if state_seq is not None:
        print("  S2MM_STATE_HIST: %s (last=%s)"
              % (hist(state_seq, S2MM_STATE_MAP), state_seq[-1]))
    # handshake activity on ui ILA (tvalid/tready)
    tv, _ = values_of(csv, "dbg_s2mm_tvalid")
    tr, _ = values_of(csv, "dbg_s2mm_tready")
    if tv is not None and tr is not None:
        beats = handshakes(tv, tr)
        print("  S2MM_STREAM_BEATS_IN_WINDOW: %d" % len(beats))

    # conclusions
    def last_delta(tok):
        seq, nm = values_of(csv, tok)
        if seq is None:
            return None
        vals = [v for v in seq if v is not None]
        if not vals:
            return None
        return vals[-1] - vals[0]

    if profile == "LEGACY_UI":
        dwm = last_delta("dbg_mem_wm")
        dwr = last_delta("dbg_mem_wr_frm")
        drd = last_delta("dbg_mem_rd_frm")
        dstall = last_delta("dbg_mem_stall")
        dlen = last_delta("dbg_mem_len_err")
        dost = last_delta("dbg_mem_ost")
        print("  BRIDGE1_UI_DELTA: wm=%s wr_frm=%s rd_frm=%s stall=%s len_err=%s ost=%s"
              % (dwm, dwr, drd, dstall, dlen, dost))
        if dwm == 0 and dwr == 0 and drd == 0 and dost == 0:
            verdicts.append("[L1] bridge1 ui counters are STATIC (wm=wr_frm=rd_frm=ost"
                            " unchanged over the window): no commit/read activity was"
                            " captured -- consistent with the round3b zero-commit wedge"
                            " (user-side count stopped at the pre-wedge value)")
        if dwm is not None and dwr is not None and dwm == dwr and dwm not in (0,):
            verdicts.append("[INFO] bridge1 write counter advanced by %d in the window"
                            % dwm)
        if dstall not in (None, 0) or dlen not in (None, 0):
            verdicts.append("[L1] bridge1 error counters advanced (stall=%s len_err=%s):"
                            " check bridge error path" % (dstall, dlen))
    else:  # LEGACY_USER
        duw = last_delta("dbg_mem_u_wr")
        dur = last_delta("dbg_mem_u_rd")
        dd = last_delta("dbg_mem_u_drop")
        print("  BRIDGE1_USER_DELTA: u_wr=%s u_rd=%s u_drop=%s" % (duw, dur, dd))
        if duw not in (None, 0):
            verdicts.append("[INFO] user-side accepted frame counter advanced by %d"
                            " in the window" % duw)
        if dur in (None, 0):
            verdicts.append("[L1] user-side read counter did NOT advance: no frame was"
                            " read out of frame_mem_if in this window")
    if not verdicts:
        verdicts.append("[L1] no interpretation possible from the counters present")
    print("  %s_VERDICT:" % profile)
    for v in verdicts:
        print("    %s" % v)
    return verdicts


# ---------------------------------------------------------------------------
# generic profile
# ---------------------------------------------------------------------------
def analyze_generic(csv, last_n):
    print("  COLUMNS: %d, ROWS: %d" % (len(csv.names), csv.nrows))
    for nm in csv.base:
        seq = csv.cols[nm]
        vals = [v for v in seq if v is not None]
        if not vals:
            print("    %-28s (no numeric samples)" % nm)
            continue
        chg = sum(1 for a, b in zip(vals, vals[1:]) if a != b)
        print("    %-28s first=%s last=%s min=%s max=%s changes=%d"
              % (nm, fmt_hex(vals[0]), fmt_hex(vals[-1]),
                 fmt_hex(min(vals)), fmt_hex(max(vals)), chg))
    return []


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def analyze_file(path, forced, last_n):
    print("=" * 78)
    print("ANALYZE_FILE: %s" % os.path.abspath(path))
    try:
        csv = IlaCsv(path).load()
    except Exception as exc:  # noqa: BLE001
        print("ANALYZE_ERROR: cannot load: %s" % exc)
        return False
    profile = detect_profile(csv, forced)
    print("PROFILE: %s (rows=%d cols=%d)" % (profile, csv.nrows, len(csv.names)))
    trig_idx = [i for i, v in enumerate(csv.trigger) if v == 1]
    print("TRIGGER_INDEX: %s" % (trig_idx[:8] if trig_idx else "None"))
    if profile == "ILA4":
        analyze_ila4(csv, last_n)
    elif profile == "ILA5":
        analyze_ila5(csv, last_n)
    elif profile in ("LEGACY_UI", "LEGACY_USER"):
        analyze_legacy(csv, profile, last_n)
    else:
        analyze_generic(csv, last_n)
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Offline ILA CSV analyzer for prj11 R2 round3c "
                    "(ILA4 AXI-lite wedge / ILA5 GO-ACK-intr-state / legacy)")
    ap.add_argument("csvs", nargs="*", help="CSV file(s) exported by write_hw_ila_data")
    ap.add_argument("--dir", default=None, help="directory to scan")
    ap.add_argument("--pattern", default="R3C_*.csv",
                    help="glob pattern used with --dir (default R3C_*.csv)")
    ap.add_argument("--mode", default="auto",
                    choices=["auto", "ila4", "ila5", "legacy_ui", "legacy_user",
                             "generic"])
    ap.add_argument("--last-n", type=int, default=16,
                    help="number of trailing samples shown/used (default 16)")
    args = ap.parse_args(argv)

    files = list(args.csvs)
    if args.dir:
        files += sorted(glob.glob(os.path.join(args.dir, args.pattern)))
    # de-dup while keeping order
    seen = set()
    uniq = []
    for f in files:
        a = os.path.abspath(f)
        if a not in seen:
            seen.add(a)
            uniq.append(f)
    if not uniq:
        print("ANALYZE_ERROR: no input CSV (give files or --dir/--pattern)")
        return 2
    ok = 0
    bad = 0
    for f in uniq:
        if analyze_file(f, args.mode, args.last_n):
            ok += 1
        else:
            bad += 1
    print("=" * 78)
    print("ANALYZE_DONE: files=%d ok=%d failed=%d" % (len(uniq), ok, bad))
    return 0 if bad == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
