# -*- coding: utf-8 -*-
"""f_verify.py — B3-1b v4: 用软核 'F' 命令量 DMA 流起点相对帧首的字节偏移。

原理:
  1) 桥模式(engine=0)下 PC 发的帧会被逐字节回显 ⇒ 回显帧 = 槽内存里该帧的真值;
  2) 发两帧已知自描述载荷(A: byte[i]=i&0xFF, B: byte[i]=(i+0x80)&0xFF) → 末帧在槽 S;
  3) 软核 'F' 在 SA-64 / SA / SA+64 三点各做一笔 MM2S(64B=1拍), 回读 dma_sink q1
     (= 该笔流首拍低 32bit = 流起点 4 字节 LE);
  4) 在已知帧字节里定位这 4 字节 ⇒ 得"流起点相对帧首的偏移" r;
     对 base=SA 那点, r0 就是 shim 正确的 DROP_BYTES 口径(现为 8)。
"""
import re
import socket
import subprocess
import sys
import time

import serial

SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
LEN = 1472


def pay_a(n):
    return bytes((i & 0xFF) for i in range(n))


def pay_b(n):
    return bytes(((i + 0x80) & 0xFF) for i in range(n))


def uart(s, cmd, wait=2.5, drain_first=True):
    if drain_first:
        s.reset_input_buffer()
    s.write(cmd.encode())
    t0 = time.time()
    buf = b""
    while time.time() - t0 < wait:
        buf += s.read(4096)
        if b"\n" in buf:
            break
    return buf.decode("ascii", errors="replace").strip()


def main():
    s = serial.Serial("COM5", 9600, timeout=0.2)
    print("before:", uart(s, "I"))

    # ARP 预热用 ping(IP 层, 不占槽)
    subprocess.run(["ping", "-n", "1", "-w", "1000", DST_IP],
                   capture_output=True)

    sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sk.bind((SRC_IP, SRC_PORT))
    sk.settimeout(1.0)

    def send_and_collect(payload):
        sk.sendto(payload, (DST_IP, DST_PORT))
        got = []
        t0 = time.time()
        while time.time() - t0 < 2.0 and not got:
            try:
                d, _ = sk.recvfrom(2048)
                if d == payload:
                    got.append(d)
            except socket.timeout:
                pass
        return got[0] if got else None

    fa = send_and_collect(pay_a(LEN))
    wr_a = int(re.search(r"wr=(\d+)", uart(s, "I")).group(1))
    time.sleep(0.3)
    fb = send_and_collect(pay_b(LEN))
    wr_b = int(re.search(r"wr=(\d+)", uart(s, "I")).group(1))

    print("frame A echo: %s (len=%s)" % (fa is not None, len(fa) if fa else 0))
    print("frame B echo: %s (len=%s)" % (fb is not None, len(fb) if fb else 0))
    print("wr after A = %d (slot %d), wr after B = %d (slot %d)"
          % (wr_a, (wr_a - 1) & 0xFF, wr_b, (wr_b - 1) & 0xFF))

    line = uart(s, "F", wait=6.0)
    print("F line:", line)
    m = re.search(r"slot=(\d+)\s+q1\[-64\]=([0-9a-fA-F]+)\s+q1\[0\]=([0-9a-fA-F]+)\s+q1\[\+64\]=([0-9a-fA-F]+)", line)
    if not m:
        print("F PARSE FAIL")
        return 1
    slot, q1m64, q1z, q1p64 = int(m.group(1)), int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16)
    probes = [(-64, q1m64), (0, q1z), (64, q1p64)]

    refs = {}
    if fb:
        refs["B(末帧,槽%d)" % slot] = fb
    if fa:
        refs["A(前一帧,槽%d)" % ((slot - 1) & 0xFF)] = fa

    print("\n--- 反解 ---")
    for d, val in probes:
        b = val.to_bytes(4, "little")
        hit = None
        for name, ref in refs.items():
            i = ref.find(b)
            while i >= 0:
                hit = (name, i)
                break
            if hit:
                break
        # 自描述载荷兜底: 连续递增序列
        cons = ((b[1] - b[0]) & 0xFF, (b[2] - b[1]) & 0xFF, (b[3] - b[2]) & 0xFF)
        tail = ""
        if cons == (1, 1, 1):
            pa = b[0]                     # 若来自 A: payload offset = b[0]
            pb = (b[0] - 0x80) & 0xFF     # 若来自 B: payload offset
            tail = "  连续序列: A@pay[%d] / B@pay[%d]" % (pa, pb)
        if hit:
            print("probe base=SA%+d  q1=%08x  bytes=%s  ⇒ 命中 %s 帧内偏移 %d  %s"
                  % (d, val, " ".join("%02x" % x for x in b), hit[0], hit[1], tail))
        else:
            print("probe base=SA%+d  q1=%08x  bytes=%s  ⇒ 未命中已知帧字节 %s"
                  % (d, val, " ".join("%02x" % x for x in b), tail))
    return 0


if __name__ == "__main__":
    sys.exit(main())
