# -*- coding: utf-8 -*-
"""rdcap_warm.py — 捕获前的预热(不进 ILA 窗口): ping 解 ARP + 两帧暖机 + 排空回显。"""
import socket
import subprocess
import time

SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234

sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sk.bind((SRC_IP, SRC_PORT))
sk.settimeout(0.3)

print("ping:", subprocess.run(["ping", "-n", "1", "-w", "1000", DST_IP],
                              capture_output=True).returncode)
for _ in range(2):
    sk.sendto(b"warm", (DST_IP, DST_PORT))
    time.sleep(0.2)
n = 0
t0 = time.time()
while time.time() - t0 < 2.0:
    try:
        sk.recvfrom(2048)
        n += 1
    except socket.timeout:
        pass
print("warm drained:", n)
