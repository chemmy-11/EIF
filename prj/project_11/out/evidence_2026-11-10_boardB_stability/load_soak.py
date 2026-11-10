# -*- coding: utf-8 -*-
"""load_soak.py -- Board B load phase: sustained UDP frames + echo tally (ASCII only)

Usage: py load_soak.py <dst_ip> <dst_port> <local_port> <fps> <duration_s> <payload_len> <logfile>

Writes one marker line every 30 s:
    T+<s> SENT=<n> ECHO=<n> ECHO_RATIO=<pct> SENT_RATE=<actual fps>
and a final LOAD_DONE line. Judge by these lines only (drop != reset).
"""
import socket, sys, time

dst_ip = sys.argv[1]
dst_port = int(sys.argv[2])
lport = int(sys.argv[3])
fps = float(sys.argv[4])
dur = float(sys.argv[5])
plen = int(sys.argv[6])
logf = sys.argv[7]

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setblocking(False)
sock.bind(("", lport))

base = bytes([(i & 0xFF) for i in range(256)])
payload = (base * (plen // 256 + 1))[:plen]

sent = 0
echo = 0
f = open(logf, "a")
def mark(s):
    f.write(s + "\n")
    f.flush()
    print(s)

t0 = time.perf_counter()
mark("LOAD_START %s fps=%g dur=%g len=%d dst=%s:%d lport=%d"
     % (time.strftime("%Y-%m-%d %H:%M:%S"), fps, dur, plen, dst_ip, dst_port, lport))

period = 1.0 / fps
next_tx = t0
next_log = t0

while True:
    now = time.perf_counter()
    el = now - t0
    if el > dur:
        break
    if now >= next_tx:
        try:
            sock.sendto(payload, (dst_ip, dst_port))
            sent += 1
        except OSError:
            pass
        next_tx += period
        if next_tx < now - 0.05:
            next_tx = now + period
    while True:
        try:
            sock.recvfrom(2048)
            echo += 1
        except BlockingIOError:
            break
        except OSError:
            break
    if now - next_log >= 30.0:
        next_log = now
        mark("T+%d SENT=%d ECHO=%d ECHO_RATIO=%.2f%% SENT_RATE=%.1f"
             % (int(el), sent, echo, (100.0 * echo / sent if sent else 0.0), sent / el if el else 0.0))
    time.sleep(0.0004)

while True:
    try:
        sock.recvfrom(2048)
        echo += 1
    except BlockingIOError:
        break
    except OSError:
        break

el = time.perf_counter() - t0
mark("LOAD_DONE elapsed=%.1f SENT=%d ECHO=%d ECHO_RATIO=%.2f%% SENT_RATE=%.1f"
     % (el, sent, echo, (100.0 * echo / sent if sent else 0.0), sent / el if el else 0.0))
f.close()
sock.close()
