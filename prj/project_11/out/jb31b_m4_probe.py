# -*- coding: utf-8 -*-
"""m4_probe.py —— 3aa600aa + f8175c32(驻留服务): 区分"UART RX 丢失"与"软核真死"。
先等软核启动(3s), 然后宽窗读 TX(软核开机横幅会立即出现, 若死了则完全没有)。"""
import serial
import time

s = serial.Serial("COM5", 9600, timeout=0.2)
time.sleep(3.0)          # 等 ELF 跑起来 + 开机横幅打出
buf = b""
t0 = time.time()
while time.time() - t0 < 8.0:
    buf += s.read(4096)
print("开机横幅/自发性输出(8s 宽窗): %r" % buf[-300:] if buf else "(无任何自发输出)")

# 再发命令试应答
s.reset_input_buffer()
for trial in range(3):
    s.write(b"I")
    t0 = time.time()
    out = b""
    while time.time() - t0 < 6.0:
        out += s.read(4096)
        if b"\n" in out:
            break
    print("trial%d 'I' 应答: %r" % (trial, out))
    time.sleep(1.0)
