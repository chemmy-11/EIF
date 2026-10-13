# -*- coding: utf-8 -*-
"""J_B3-1 现场探查: 读 'I' 计数器 + 连发 3 帧 + 再读, 弄清 wm 与提交数关系"""
import sys, time
sys.path.insert(0, r"D:\FPGA\prj\project_10\prj_loop\scripts")
from j3_random_read import CmdClient, DataPlane, build_payload, MODE_SEQ, warmup_link
import serial

s = serial.Serial("COM5", 9600, timeout=0.2)

def uart_line(timeout_s=6.0):
    t0 = time.time()
    buf = s.read(1)
    while time.time() - t0 < timeout_s:
        d = s.read(256)
        if d:
            buf += d
            if b"\n" in buf:
                line, buf2 = buf.split(b"\n", 1)
                return line.strip(b"\r").decode("ascii", errors="replace")
    return None

def read_i(tag):
    s.reset_input_buffer()
    s.write(b"I")
    for _ in range(30):
        line = uart_line(0.3)
        if line and "[B2] ID=" in line:
            print("[%s] %s" % (tag, line))
            return line
    print("[%s] no I line" % tag)
    return None

cli = CmdClient("192.168.1.102")
dm = DataPlane("192.168.1.102")

read_i("before-warmup")
cli.set_mode(MODE_SEQ)
warmup_link(dm.dst[0], dm.dst[1], enabled=True, settle_s=0.8, bind_ip="192.168.1.102")
time.sleep(0.3)
dm.drain(0.3)
read_i("after-warmup")
seq0 = 71000
for i in range(3):
    dm.send(build_payload(seq0 + i, 9, 64))
    dm.drain(1.0)
read_i("after-3-frames")
print("DONE")
