import socket, time, subprocess, threading
SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
p = (b"B31B-EM-0000-L0100-" * 7)[:100]
sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sk.bind((SRC_IP, SRC_PORT)); sk.settimeout(0.4)
for _ in range(2): sk.sendto(b"warm", (DST_IP, DST_PORT)); time.sleep(0.2)
try:
    while True: sk.recvfrom(2048)
except socket.timeout: pass
time.sleep(4)
print("SEND 100B tagged frame")
sk.sendto(p, (DST_IP, DST_PORT))
time.sleep(2)
print("check JTAG log now")
