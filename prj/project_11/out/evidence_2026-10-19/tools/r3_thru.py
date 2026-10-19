# -*- coding: utf-8 -*-
"""r3_thru.py -- R3 rate quantification for prj11 route B (softcore-served AXI DMA).

For each pace tier:
  - wait board quiescent ('I' counters stable twice)
  - snapshot board counters ('I'), event-ring counter ('X'), wall clock
  - run json_storm.py with given --pace-us / --chunk 1466 / --limit-bytes
  - snapshot again; wait quiet; compute board-side served/accept counts and rates
Writes one JSON + one text log. Board is round3d bit (F6012BA0) + perf1 ELF (BA3C0220),
firmware already in DMA mode ('d').

Usage:
  py r3_thru.py --tiers "1000:10293111,500:10293111,200:10293111" --out <json> --log <txt>
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

import serial

I_RX = re.compile(r"\[B2\] ID=\d+ wr=(\d+) rd=(\d+) drop=(\d+)")
U_RX = {
    "req": re.compile(r"U req:([0-9a-f ]+)"),
    "wmrd": re.compile(r"U wmrd:([0-9a-f ]+)"),
    "wmwr": re.compile(r"U wmwr:([0-9a-f ]+)"),
    "wreq": re.compile(r"U wreq:([0-9a-f ]+)"),
    "wdbg": re.compile(r"U wdbg:([0-9a-f ]+)"),
    "s2sr": re.compile(r"U s2sr:([0-9a-f ]+)"),
}
X_RX = re.compile(r"X evt_n=(\d+)")


class Board:
    def __init__(self, port, wait=1.8):
        self.s = serial.Serial(port, 9600, timeout=0.05)
        self.wait = wait
        time.sleep(0.8)
        self.s.reset_input_buffer()

    def cmd(self, c, wait=None):
        self.s.reset_input_buffer()
        self.s.write(c.encode("ascii"))
        self.s.flush()
        t0 = time.time()
        buf = b""
        w = self.wait if wait is None else wait
        while time.time() - t0 < w:
            buf += self.s.read(4096)
        return buf.decode("latin-1", errors="replace")

    def state_i(self):
        txt = self.cmd("I", wait=1.4)
        m = I_RX.search(txt)
        if not m:
            return None
        return {"wr": int(m.group(1)), "rd": int(m.group(2)), "drop": int(m.group(3))}

    def state_full(self):
        txt = self.cmd("U", wait=2.0)
        out = {}
        for k, rx in U_RX.items():
            m = rx.search(txt)
            if m:
                toks = [t for t in m.group(1).split() if len(t) == 8]
                out[k] = toks[0] if toks else None
        return out

    def evt_n(self):
        txt = self.cmd("X", wait=2.6)
        m = X_RX.search(txt)
        return int(m.group(1)) if m else None

    def close(self):
        self.s.close()


def wait_quiet(b, max_polls=18, sleep_s=0.45, need_stable=2):
    prev = None
    stable = 0
    last = None
    for _ in range(max_polls):
        cur = b.state_i()
        if cur is None:
            return {"ok": False, "reason": "no-response-I", "last": last}
        last = cur
        if prev is not None and cur == prev:
            stable += 1
            if stable >= need_stable - 1:
                return {"ok": True, "state": cur}
        else:
            stable = 0
        prev = cur
        time.sleep(sleep_s)
    return {"ok": False, "reason": "not-quiet", "last": last}


def parse_storm(out):
    res = {"summary": None, "recv": None, "chunks": None, "lost": None, "corrupt": None,
           "rtt_avg_ms": None, "send_s": None}
    for line in out.splitlines():
        if line.startswith("JSON_STORM_SUMMARY:"):
            try:
                res["summary"] = json.loads(line.split(":", 1)[1].strip())
            except Exception:
                pass
    s = res["summary"] or {}
    res["recv"] = s.get("recv")
    res["chunks"] = s.get("chunks")
    res["lost"] = s.get("lost")
    res["corrupt"] = s.get("corrupt")
    res["rtt_avg_ms"] = s.get("rtt_avg_ms")
    res["send_s"] = s.get("dur_send_s") or s.get("send_s")
    # 兜底: 从中文报告行解析
    m = re.search(r"发送片数\s*:\s*(\d+)", out)
    if m and res["chunks"] is None:
        res["chunks"] = int(m.group(1))
    m = re.search(r"收到片数\s*:\s*(\d+)", out)
    if m and res["recv"] is None:
        res["recv"] = int(m.group(1))
    m = re.search(r"发送用时\s*:\s*([\d.]+)s", out)
    if m:
        res["send_s"] = float(m.group(1))
    return res


def run_tier(b, args, pace_us, limit_bytes, tier_log):
    quiet0 = wait_quiet(b)
    i0 = b.state_i()
    u0 = b.state_full()
    e0 = b.evt_n()
    t0 = time.perf_counter()
    cmd = [args.py, args.storm, args.data, "--chunk", str(args.chunk),
           "--pace-us", str(pace_us), "--limit-bytes", str(limit_bytes), "--gap-ms", "0"]
    cp = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                        timeout=args.timeout_s)
    out = (cp.stdout or "") + "\n" + (cp.stderr or "")
    tret = time.perf_counter()
    with open(tier_log, "w", encoding="utf-8") as f:
        f.write("# CMD: " + " ".join(cmd) + "\n# EXIT: %d\n\n" % cp.returncode)
        f.write(out)
    quiet1 = wait_quiet(b)
    i1 = b.state_i()
    u1 = b.state_full()
    e1 = b.evt_n()
    t1 = time.perf_counter()
    st = parse_storm(out)
    row = {
        "pace_us": pace_us, "limit_bytes": limit_bytes, "storm_exit": cp.returncode,
        "storm": st,
        "board_i0": i0, "board_i1": i1, "board_u0": u0, "board_u1": u1,
        "evt0": e0, "evt1": e1,
        "t_storm_s": round(tret - t0, 3),
        "t_total_s": round(t1 - t0, 3),
        "quiet_after": quiet1,
    }
    if i0 and i1:
        dwr = i1["wr"] - i0["wr"]
        drd = i1["rd"] - i0["rd"]
        row["board_dwr"] = dwr
        row["board_drd"] = drd
        row["board_wr_rate"] = round(dwr / max(1e-9, t1 - t0), 1)
        row["board_rd_rate"] = round(drd / max(1e-9, t1 - t0), 1)
        row["board_drop"] = i1["drop"] - i0["drop"]
    if e0 is not None and e1 is not None:
        row["evt_delta"] = e1 - e0
        if i0 and i1 and (i1["rd"] - i0["rd"]) > 0:
            row["evt_per_readout"] = round((e1 - e0) / (i1["rd"] - i0["rd"]), 3)
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM5")
    ap.add_argument("--py", default=sys.executable)
    ap.add_argument("--storm", default=r"D:\FPGA\prj\project_9\scripts\json_storm.py")
    ap.add_argument("--data", default=r"D:\FPGA\prj\project_9\testdata\session_full.jsonl")
    ap.add_argument("--chunk", type=int, default=1466)
    ap.add_argument("--tiers", default="1000:10293111")
    ap.add_argument("--timeout-s", type=int, default=60)
    ap.add_argument("--out", default="")
    ap.add_argument("--log", default="")
    ap.add_argument("--tierdir", default="")
    a = ap.parse_args()

    tiers = []
    for part in a.tiers.split(","):
        pace, lim = part.split(":")
        tiers.append((float(pace), int(lim)))

    b = Board(a.port)
    rows = []
    try:
        for pace_us, limit in tiers:
            tlog = os.path.join(a.tierdir or os.path.dirname(a.log or "."),
                                "R3_tier_pace%s_us.log" % (int(pace_us) if pace_us == int(pace_us) else pace_us))
            print("== tier pace=%sus limit=%d ==" % (pace_us, limit), flush=True)
            row = run_tier(b, a, pace_us, limit, tlog)
            rows.append(row)
            st = row["storm"]
            print("   storm: recv=%s/%s lost=%s corrupt=%s rtt_avg=%sms t_storm=%ss" % (
                st["recv"], st["chunks"], st["lost"], st["corrupt"], st["rtt_avg_ms"], row["t_storm_s"]), flush=True)
            print("   board: dwr=%s drd=%s drop+%s  wr_rate=%s rd_rate=%s fps  evt/frame=%s  total=%.2fs" % (
                row.get("board_dwr"), row.get("board_drd"), row.get("board_drop"),
                row.get("board_wr_rate"), row.get("board_rd_rate"),
                row.get("evt_per_readout"), row["t_total_s"]), flush=True)
            if not row.get("quiet_after", {}).get("ok"):
                print("   !! board not quiet after tier: %s" % row.get("quiet_after"), flush=True)
                break
            # 若板卡失联（两次 I 无响应），提前停
            if row["board_i1"] is None:
                print("   !! board unresponsive, stop", flush=True)
                break
    finally:
        b.close()
    doc = {"tiers": rows,
           "meta": {"chunk": a.chunk, "storm": a.storm, "data": a.data,
                    "port": a.port, "when": time.strftime("%Y-%m-%d %H:%M:%S")}}
    text = json.dumps(doc, ensure_ascii=False, indent=2)
    if a.out:
        os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
        open(a.out, "w", encoding="utf-8").write(text + "\n")
        print("JSON_OUT:", a.out)
    if a.log:
        os.makedirs(os.path.dirname(a.log) or ".", exist_ok=True)
        open(a.log, "w", encoding="utf-8").write(text + "\n")
        print("LOG_OUT:", a.log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
