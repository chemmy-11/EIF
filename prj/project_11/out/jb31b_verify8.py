# send one tagged frame, learn its slot, then 'D'-style DMA sink read at SA=base+50
import socket, time, serial
SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
p = (b"B31B-V88-0000-L0100-" * 7)[:100]
sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sk.bind((SRC_IP, SRC_PORT)); sk.settimeout(1.0)
for _ in range(2): sk.sendto(b"warm", (DST_IP, DST_PORT)); time.sleep(0.2)
try:
    while True: sk.recvfrom(2048)
except socket.timeout: pass
s = serial.Serial("COM5", 9600, timeout=0.1)
def rd_i():
    s.reset_input_buffer(); s.write(b"I")
    t0 = time.time(); out = ""
    while time.time() - t0 < 4:
        d = s.read(4096)
        if d:
            out += d.decode("ascii", errors="replace")
            if "\n" in out: break
    return out.strip().splitlines()[-1]
w0 = rd_i().split("wr=")[1].split()[0]
sk.sendto(p, (DST_IP, DST_PORT))
time.sleep(1.5)
w1 = int(rd_i().split("wr=")[1].split()[0])
print("wr %s -> %d (my frame should be slot %d if last)" % (w0, w1, (w1-1) & 0xff))
with open("jb31b_slot.txt", "w") as f: f.write(str((w1 - 1) & 0xff))
s.close(); sk.close()
