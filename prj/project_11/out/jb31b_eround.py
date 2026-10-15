# -*- coding: utf-8 -*-
"""B3-1b 'E' round v2: tag-matched echo compare (stray LAN frames immune).
Judge: every B31B payload echoed byte-exact (tag matched); rd delta == wr delta;
E-DONE served>=1 stall=0; E-ARL vs expected (last served burst)."""
import socket, time, serial, re

SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
N = 16
LENS = [64, 100, 26, 512, 1472, 128, 200, 65, 512, 63, 300, 1472, 64, 512, 100, 1466]
TAG = b"B31B-E-"

def make_payload(n, i):
    t = ("B31B-E-%03d-L%04d-" % (i, n)).encode()
    return (t * ((n // len(t)) + 1))[:n]

s = serial.Serial("COM5", 9600, timeout=0.1)
def uart_read(t):
    t0 = time.time(); buf = b""
    while time.time() - t0 < t:
        buf += s.read(4096)
    return buf.decode("ascii", errors="replace")
def read_i():
    s.reset_input_buffer(); s.write(b"I")
    t0 = time.time(); out = ""
    while time.time() - t0 < 4:
        d = s.read(4096)
        if d:
            out += d.decode("ascii", errors="replace")
            if "\n" in out: break
    try:
        line = out.strip().splitlines()[-1]
        wr = int(line.split("wr=")[1].split()[0])
        rd = int(line.split("rd=")[1].split()[0])
        return wr, rd
    except Exception:
        return -1, -1

wr0, rd0 = read_i()
print("baseline: wr=%d rd=%d" % (wr0, rd0))

sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sk.bind((SRC_IP, SRC_PORT))
for _ in range(3):
    sk.sendto(b"probe", (DST_IP, DST_PORT)); time.sleep(0.2)
sk.settimeout(0.5)
try:
    while True: sk.recvfrom(2048)
except socket.timeout:
    pass

s.reset_input_buffer()
s.write(b"E")
time.sleep(0.02)

payloads = [make_payload(LENS[i], i) for i in range(N)]
for p in payloads:
    sk.sendto(p, (DST_IP, DST_PORT))
    time.sleep(0.08)

echoes = []
t0 = time.time()
while time.time() - t0 < 20 and len([e for e in echoes if e.startswith(TAG)]) < N:
    try:
        d, _ = sk.recvfrom(2048)
        echoes.append(d)
    except socket.timeout:
        pass

uart = uart_read(10.0)
print("UART>>>"); print(uart); print("<<<UART")
wr1, rd1 = read_i()
print("after: wr=%d rd=%d (d=%+d/%+d)" % (wr1, rd1, wr1 - wr0, rd1 - rd0))

errs = 0
# judge 1: tag-matched byte-exact
hits = {}
for e in echoes:
    if e.startswith(TAG):
        idx = int(e[7:10])
        hits[idx] = hits.get(idx, 0) + 1
        if e != payloads[idx]:
            d = next((k for k in range(min(len(e), len(payloads[idx]))) if e[k] != payloads[idx][k]), -1)
            print("[FAIL] echo#%d firstdiff@%d len=%d/%d" % (idx, d, len(e), len(payloads[idx])))
            errs += 1
missing = [i for i in range(N) if i not in hits]
dup = [i for i in hits if hits[i] > 1]
if missing: print("[FAIL] missing echoes: %s" % missing); errs += 1
if dup: print("[FAIL] duplicated: %s" % dup); errs += 1
print("ECHO: %d/%d tag-matched byte-exact, %d stray ignored"
      % (len(hits) - len([i for i in hits if hits[i] > 1]), N, len(echoes) - len(hits)))

# judge 2: accounting
if wr1 - wr0 < N: print("[FAIL] wr delta %d < %d" % (wr1 - wr0, N)); errs += 1
if rd1 - rd0 != wr1 - wr0: print("[FAIL] rd delta %+d != wr delta %+d" % (rd1 - rd0, wr1 - wr0)); errs += 1

# judge 3: E-DONE fields
served = stall = -1
for line in uart.splitlines():
    if "E-DONE" in line:
        served = int(line.split("served=")[1].split()[0])
        stall = int(line.split("stall=")[1].strip())
if served < 1 or stall != 0:
    print("[FAIL] E-DONE served=%d stall=%d" % (served, stall)); errs += 1
else:
    print("E-DONE: served=%d stall=0" % served)

# judge 4: E-ARL (last burst of last transfer)
# 修复 (10-15): ARL 与 EMIT 两行 UART 打印无换行粘连 -> 旧 split("arl=") 尾部
# 带 "[B2] E-EMIT ..." 导致 int() 崩; 改为只抠 hex 前缀。
arl = ""
for line in uart.splitlines():
    m = re.search(r"arl=([0-9a-fA-F]+)", line)
    if m:
        arl = m.group(1)
if arl and wr1 > wr0:
    last_slot = (wr1 - 1) & 0xff
    last_len = LENS[-1] if (wr1 - wr0) == N else None
    sa = 0x100000 + last_slot * 4096
    got = int(arl, 16)
    note = "unknown-len(stray last)" if last_len is None else \
           ("SA+128 (2nd burst of LEN=%d -> AR exact, 窗口偏移在数据侧)" % (last_len + 8)
            if got == sa + 128 and last_len + 8 > 128 else
            ("==SA (single-burst, AR exact)" if got == sa else "check"))
    print("E-ARL: got=%08x last-slot-SA=%08x -> %s" % (got, sa, note))
else:
    print("[WARN] no E-ARL parse")

print("==== B31B_E_ROUND: %d errors ====" % errs)
print("B31B_E_ROUND: " + ("PASS" if errs == 0 else "FAIL"))
s.close(); sk.close()
