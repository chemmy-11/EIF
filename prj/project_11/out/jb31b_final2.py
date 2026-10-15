import socket, time
SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
p = (b"B31B-FIN-000-L0100-" * 7)[:100]
sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sk.bind((SRC_IP, SRC_PORT)); sk.settimeout(1.0)
for _ in range(2): sk.sendto(b"warm", (DST_IP, DST_PORT)); time.sleep(0.2)
try:
    while True: sk.recvfrom(2048)
except socket.timeout: pass
time.sleep(10)
print("SEND 100B tagged")
sk.sendto(p, (DST_IP, DST_PORT))
t0 = time.time(); got = []
while time.time() - t0 < 45:
    try:
        d, _ = sk.recvfrom(2048)
        got.append(d)
        print("ECHO[%d]: %s" % (len(d), d[:24].hex()))
    except socket.timeout: pass
print("total:", len(got))
