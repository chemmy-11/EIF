# -*- coding: utf-8 -*-
"""B3-1b board: COM5 banner check + optional single-char command"""
import sys, time, serial
s = serial.Serial("COM5", 9600, timeout=0.2)
def drain(t=3.0):
    t0 = time.time(); buf = b""
    while time.time() - t0 < t:
        buf += s.read(4096)
    return buf
s.reset_input_buffer()
banner = drain(3.0)
print("BANNER:", banner.decode("ascii", errors="replace"))
if len(sys.argv) > 1:
    s.write(sys.argv[1].encode())
    out = drain(6.0)
    print("CMD_OUT:", out.decode("ascii", errors="replace"))
s.close()
