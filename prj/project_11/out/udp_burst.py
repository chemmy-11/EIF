# -*- coding: utf-8 -*-
"""udp_burst.py -- 在 ARP 已解析的前提下发 N 个 UDP 数据帧, 统计回显。"""
import socket, sys, time

n = int(sys.argv[1]) if len(sys.argv) > 1 else 20
size = int(sys.argv[2]) if len(sys.argv) > 2 else 64

tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
tx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tx.bind(("", 1236))
tx.settimeout(0.3)

got = 0
for k in range(n):
    payload = bytes([k & 0xFF]) + bytes(size - 1)
    tx.sendto(payload, ("192.168.1.10", 1234))
    t0 = time.time()
    while time.time() - t0 < 0.15:
        try:
            tx.recvfrom(2048)
            got += 1
        except socket.timeout:
            break
    time.sleep(0.005)
t0 = time.time()
while time.time() - t0 < 1.5:
    try:
        tx.recvfrom(2048)
        got += 1
    except socket.timeout:
        pass
print("sent=%d echo=%d" % (n, got), flush=True)
tx.close()
