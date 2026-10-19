# -*- coding: utf-8 -*-
"""r3c_serial_ping_session.py -- round3c board rehearsal: UART capture across 'U'/'d'/'W' + ping 1.

Usage: py r3c_serial_ping_session.py --port COM5 --out <logfile>
Prints timestamped serial chunks; also runs one ping after arming the reader.
Never injects AXI reads during printing (pit #44 family): only serial + OS ping.
"""
import argparse
import subprocess
import threading
import time

import serial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM5")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--out", default="")
    ap.add_argument("--ping", default="192.168.1.10")
    ap.add_argument("--post-wait", type=float, default=12.0)
    a = ap.parse_args()

    log_lines = []

    def emit(s):
        log_lines.append(s)
        print(s, flush=True)

    s = serial.Serial(a.port, a.baud, timeout=0.05)
    s.reset_input_buffer()

    buf = []
    lock = threading.Lock()
    stop = {"v": False}
    t0 = time.time()

    def reader():
        while not stop["v"]:
            try:
                chunk = s.read(4096)
            except Exception:
                break
            if chunk:
                with lock:
                    buf.append((time.time() - t0, chunk))

    th = threading.Thread(target=reader, daemon=True)
    th.start()

    def drain_print(tag):
        time.sleep(0.3)
        with lock:
            items = list(buf)
            buf.clear()
        text = b"".join(c for _, c in items)
        emit("[%s] t=%.3f..%.3f bytes=%d" % (tag, items[0][0] if items else -1,
                                             items[-1][0] if items else -1, len(text)))
        emit("[%s] %r" % (tag, text))

    def send(cmd, wait, tag):
        emit("[TX %s] %r" % (tag, cmd))
        s.write(cmd)
        s.flush()
        time.sleep(wait)
        drain_print(tag)

    # boot drain
    time.sleep(2.0)
    drain_print("BOOT")
    send(b"U", 2.5, "U")
    send(b"d", 1.5, "d")
    send(b"W", 2.0, "W-pre")

    emit("[PING] ping -n 1 -w 900 %s" % a.ping)
    try:
        r = subprocess.run(["ping", "-n", "1", "-w", "900", a.ping],
                           capture_output=True, text=True, timeout=15)
        emit("[PING] rc=%d out=%r" % (r.returncode, (r.stdout or "").strip()[-220:]))
    except Exception as e:
        emit("[PING] EXC %r" % (e,))
    time.sleep(a.post_wait)
    drain_print("post-ping")

    # try W again (may be silent / garbage if wedged)
    send(b"W", 2.5, "W-post")
    send(b"U", 2.5, "U-post")

    stop["v"] = True
    th.join(timeout=1.0)
    s.close()
    emit("[DONE]")

    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(log_lines) + "\n")


if __name__ == "__main__":
    main()
