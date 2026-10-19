# -*- coding: utf-8 -*-
"""r3c_pingprobe.py -- per-ping counter reconciliation on R2 board.

Usage: py r3c_pingprobe.py --port COM5 --n 4 --mode U
Sends 'U' (or 'I') snapshot, then one ping, then snapshot again, prints deltas.
"""
import argparse
import re
import subprocess
import time

import serial


def read_snapshot(s, wait=1.6):
    s.reset_input_buffer()
    s.write(b"U")
    s.flush()
    t0 = time.time()
    buf = b""
    while time.time() - t0 < wait:
        buf += s.read(4096)
    return buf.decode("latin-1", errors="replace")


REQ = re.compile(r"U req:([0-9a-f ]+)")
WMRD = re.compile(r"U wmrd:([0-9a-f ]+)")
WMWR = re.compile(r"U wmwr:([0-9a-f ]+)")
S2SR = re.compile(r"U s2sr:([0-9a-f ]+)")
WREQ = re.compile(r"U wreq:([0-9a-f ]+)")
WDBG = re.compile(r"U wdbg:([0-9a-f ]+)")
UST = re.compile(r"U ust:([0-9a-f ]+)")
STAT = re.compile(r"U stat:([0-9a-f ]+)")


def parse(txt):
    out = {}
    for name, rx in [("req", REQ), ("wmrd", WMRD), ("wmwr", WMWR), ("s2sr", S2SR),
                     ("wreq", WREQ), ("wdbg", WDBG), ("ust", UST), ("stat", STAT)]:
        m = rx.search(txt)
        if m:
            toks = [t for t in m.group(1).split() if len(t) == 8]
            out[name] = toks[0] if toks else "?"
    return out


def snap_keys(x):
    return "req=%s wmrd=%s wmwr=%s wreq=%s wdbg=%s s2sr=%s" % (
        x.get("req"), x.get("wmrd"), x.get("wmwr"), x.get("wreq"), x.get("wdbg"), x.get("s2sr"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM5")
    ap.add_argument("--n", type=int, default=4)
    ap.add_argument("--wait", type=float, default=1.6)
    a = ap.parse_args()

    s = serial.Serial(a.port, 9600, timeout=0.05)
    time.sleep(1.0)

    prev = parse(read_snapshot(s, a.wait))
    print("[base]", snap_keys(prev), flush=True)
    for i in range(1, a.n + 1):
        r = subprocess.run(["ping", "-n", "1", "-w", "900", "192.168.1.10"],
                           capture_output=True, text=True, timeout=15)
        ok = ("TTL=" in r.stdout)
        time.sleep(1.2)
        cur = parse(read_snapshot(s, a.wait))
        def d(k):
            try:
                return int(cur[k], 16) - int(prev[k], 16)
            except Exception:
                return None
        print("[ping %d] ok=%s  d_wmwr=%s d_wmrd=%s d_drop(req)=%s  req=%s wmwr=%s wmrd=%s s2sr=%s wreq=%s" % (
            i, ok, d("wmwr"), d("wmrd"), d("req"), cur.get("req"), cur.get("wmwr"),
            cur.get("wmrd"), cur.get("s2sr"), cur.get("wreq")), flush=True)
        prev = cur
    s.close()


if __name__ == "__main__":
    main()
