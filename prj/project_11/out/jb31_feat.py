# -*- coding: utf-8 -*-
"""J_B3-1 判别10: 写特征帧(512B, byte[i]=(i//4)&0xff -> 每 4B 组=beat序号) → dump DMA 视角"""
import sys, time, struct
sys.path.insert(0, r"D:\FPGA\prj\project_10\prj_loop\scripts")
from j3_random_read import CmdClient, DataPlane, MODE_SEQ, warmup_link
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

def read_i():
    s.reset_input_buffer()
    s.write(b"I")
    for _ in range(30):
        line = uart_line(0.3)
        if line and "[B2] ID=" in line:
            return line
    return None

cli = CmdClient("192.168.1.102")
dm = DataPlane("192.168.1.102")
cli.set_mode(MODE_SEQ)
warmup_link(dm.dst[0], dm.dst[1], enabled=True, settle_s=0.8, bind_ip="192.168.1.102")
time.sleep(0.3); dm.drain(0.3)

# feature frame: 512 bytes, byte[i] = (i>>2)&0xFF  => each 32-bit word k = k repeated
MARK = 0xCAFEBABE
payload = bytearray(512)
struct.pack_into('<I', payload, 0, MARK)
for i in range(4, 512):
    payload[i] = (i >> 2) & 0xFF
dm.send(bytes(payload))
echo = dm.drain(2.0)
print("feature frame sent, echo=%d" % len(echo))
print(read_i())
print("DONE")
