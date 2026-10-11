# -*- coding: utf-8 -*-
"""J_B1 ② 串口捕获 v2: COM5@9600, 读 40 秒, 落 jb1_uart.log"""
import serial, time, io

s = serial.Serial("COM5", 9600, timeout=1)
t0 = time.time()
buf = []
while time.time() - t0 < 40:
    d = s.read(512)
    if d:
        buf.append(d)
        print(d.decode("ascii", errors="replace"), end="", flush=True)
s.close()
raw = b"".join(buf)
with io.open(r"D:\FPGA\prj\project_11\out\jb1_uart.log", "wb") as f:
    f.write(raw)
print("\n--- UART_CAPTURE_DONE: %d bytes ---" % len(raw))
