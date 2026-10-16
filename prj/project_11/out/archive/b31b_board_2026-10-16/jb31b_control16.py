# -*- coding: utf-8 -*-
"""对照: 同 16 帧载荷, 不发 'E'(engine=0 桥引擎), 验证 16/16 回显 (阳性对照)。"""
import socket, time

SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
N = 16
LENS = [64, 100, 26, 512, 1472, 128, 200, 65, 512, 63, 300, 1472, 64, 512, 100, 1466]
TAG = b"B31B-E-"


def make_payload(n, i):
    t = ("B31B-E-%03d-L%04d-" % (i, n)).encode()
    return (t * ((n // len(t)) + 1))[:n]


sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sk.bind((SRC_IP, SRC_PORT))
for _ in range(3):
    sk.sendto(b"probe", (DST_IP, DST_PORT))
    time.sleep(0.2)
sk.settimeout(0.5)
try:
    while True:
        sk.recvfrom(2048)
except socket.timeout:
    pass

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

errs = 0
hits = {}
for e in echoes:
    if e.startswith(TAG):
        idx = int(e[7:10])
        hits[idx] = hits.get(idx, 0) + 1
        if e != payloads[idx]:
            errs += 1
            print("[FAIL] echo#%d mismatch len=%d/%d" % (idx, len(e), len(payloads[idx])))
missing = [i for i in range(N) if i not in hits]
if missing:
    print("[FAIL] missing echoes: %s" % missing)
    errs += 1
print("ECHO: %d/%d tag-matched byte-exact, %d stray ignored"
      % (len(hits), N, len(echoes) - len(hits)))
print("==== BRIDGE_MODE_CONTROL: %d errors ====" % errs)
print("BRIDGE_MODE_CONTROL: %s" % ("PASS" if errs == 0 else "FAIL"))
