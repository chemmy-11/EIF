# -*- coding: utf-8 -*-
"""J_B3-1 判别7: 写 seq 已知帧 -> DMA 读 slot+0x40 -> q1 应等于 seq (验证 64B 前导假设)"""
import sys, time
sys.path.insert(0, r"D:\FPGA\prj\project_10\prj_loop\scripts")
from j3_random_read import CmdClient, DataPlane, build_payload, MODE_SEQ, warmup_link
import serial

s = serial.Serial("COM5", 9600, timeout=0.2)
def uart_line(t=6.0):
    t0 = time.time(); buf = s.read(1)
    while time.time() - t0 < t:
        d = s.read(256)
        if d:
            buf += d
            if b"\n" in buf:
                line, _ = buf.split(b"\n", 1)
                return line.strip(b"\r").decode("ascii", errors="replace")
    return None

cli = CmdClient("192.168.1.102")
dm = DataPlane("192.168.1.102")
cli.set_mode(MODE_SEQ)
warmup_link(dm.dst[0], dm.dst[1], enabled=True, settle_s=0.8, bind_ip="192.168.1.102")
time.sleep(0.3); dm.drain(0.3)

seq = 70020
dm.send(build_payload(seq, 9, 64))
echo = dm.drain(1.5)
print("frame seq=%d echo=%d" % (seq, len(echo)))
time.sleep(0.3)

s.reset_input_buffer()
s.write(b"I")
for _ in range(30):
    line = uart_line(0.3)
    if line and "[B2] ID=" in line:
        print("I: %s" % line)
        break
print("DONE")
