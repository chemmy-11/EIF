# -*- coding: utf-8 -*-
"""single-frame DMA-serve experiment: PC sends 1 tagged frame, JTAG serves"""
import socket, time, serial, sys
SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
p = (b"B31B-SIG-0000-L0100-" * 7)[:100]
sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sk.bind((SRC_IP, SRC_PORT)); sk.settimeout(1.0)
for _ in range(2): sk.sendto(b"warm", (DST_IP, DST_PORT)); time.sleep(0.2)
try:
    while True: sk.recvfrom(2048)
except socket.timeout: pass
s = serial.Serial("COM5", 9600, timeout=0.1)
s.write(b"I"); time.sleep(1.0)
s.reset_input_buffer()
print("SENDING...")
sk.sendto(p, (DST_IP, DST_PORT))
time.sleep(1.0)
print("sent; now JTAG serves (external)")
got = []
t0 = time.time()
while time.time() - t0 < 25:
    try:
        d, _ = sk.recvfrom(2048)
        got.append(d)
        print("ECHO[%d]: %s..." % (len(d), d[:32].hex()))
    except socket.timeout:
        pass
print("total echoes:", len(got))
s.close(); sk.close()
