# -*- coding: utf-8 -*-
"""manual_round.py -- 最小化"手动 M 轮"驱动: 串口 + UDP 一体, 打印板卡原始行。
目的: 绕开 j3_soft_verify.py 的解析层, 拿到板卡自己打印的 READY/DONE 真值。"""
import socket, sys, threading, time
import serial

COM = sys.argv[1] if len(sys.argv) > 1 else "COM5"
NSL = int(sys.argv[2]) if len(sys.argv) > 2 else 256
SIZE = 64

ser = serial.Serial(COM, 9600, timeout=0.05)
time.sleep(0.3)
ser.reset_input_buffer()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("", 1236))
sock.settimeout(0.05)

echo = [0]
stop = [False]

def rx_thread():
    while not stop[0]:
        try:
            sock.recvfrom(2048)
            echo[0] += 1
        except socket.timeout:
            pass

th = threading.Thread(target=rx_thread, daemon=True)
th.start()

def read_until(marker, timeout):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        buf += ser.read(4096)
        if marker.encode() in buf:
            return buf, True
    return buf, False

ser.write(b"M\xb2")
buf, ok = read_until("SEQOK", 5.0)
print("[phase0] SEQOK=%s  tail=%r" % (ok, buf[-60:]), flush=True)

ser.write(b"M\xb2")
buf, ok = read_until("READY", 8.0)
print("[phase1] READY=%s  tail=%r" % (ok, buf[-80:]), flush=True)

t0 = time.time()
for k in range(NSL):
    sock.sendto(bytes([k & 0xFF]) + bytes(SIZE - 1), ("192.168.1.10", 1234))
    time.sleep(0.0012)
print("[tx] %d frames in %.2fs" % (NSL, time.time() - t0), flush=True)

t0 = time.time()
out = b""
while time.time() - t0 < 90.0:
    out += ser.read(4096)
    if b"DONE" in out or b"STALL" in out or b"FAIL" in out:
        out += ser.read(4096)
        break
stop[0] = True
text = out.decode("latin-1", "replace")
print("=== board console ===", flush=True)
print(text[-1500:], flush=True)
print("=== echo=%d ===" % echo[0], flush=True)
ser.close()
