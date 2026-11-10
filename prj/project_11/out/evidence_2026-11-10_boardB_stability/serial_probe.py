# -*- coding: utf-8 -*-
"""serial_probe.py -- 参数化串口探针（板B 稳定性测试用）

用法: py serial_probe.py <COMx> <baud> <drain_s> [cmd]
  cmd 为 '-' 或省略时只读 banner，不发命令。

判据由外部按返回文本判定，本脚本只做无损回显（不裁剪、不猜测）。
注意: 板卡固件的 'd' 是**翻转**命令（DMA <-> PIO），连发两次会回到原状态。
"""
import sys, time, serial

if len(sys.argv) < 4:
    print("USAGE: serial_probe.py <COMx> <baud> <drain_s> [cmd|-]")
    sys.exit(2)

port = sys.argv[1]
baud = int(sys.argv[2])
drain_s = float(sys.argv[3])
cmd = sys.argv[4] if len(sys.argv) > 4 else "-"

s = serial.Serial(port, baud, timeout=0.2)
time.sleep(0.3)
s.reset_input_buffer()

def drain(t):
    t0 = time.time()
    buf = b""
    while time.time() - t0 < t:
        n = s.in_waiting
        buf += s.read(n if n else 1)
    return buf

print("PORT: %s BAUD: %d" % (port, baud))
banner = drain(drain_s)
print("BANNER_BYTES: %d" % len(banner))
print("BANNER: %s" % repr(banner))

if cmd not in ("-", ""):
    s.write(cmd.encode())
    out = drain(6.0)
    print("CMD: %r" % cmd)
    print("CMD_BYTES: %d" % len(out))
    print("CMD_OUT: %s" % repr(out))

s.close()
print("SERIAL_PROBE_DONE")
