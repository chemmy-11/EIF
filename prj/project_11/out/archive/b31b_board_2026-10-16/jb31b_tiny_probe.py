# -*- coding: utf-8 -*-
"""tiny_probe.py — 单拍判别: 2 字节载荷(帧 44B → len_tab 56 → DMA 传输 64B = 恰好 1 拍)。

判据: 桥模式(对照) 与 E 模式 是否回显这 2 字节。
  · 桥 ✓ / E ✗  ⇒ 与"跨拍装配"无关, 问题在单拍内的字节级(丢拍/丢弃/发射)
  · 桥 ✓ / E ✓  ⇒ 问题只在多拍路径(beat 序列/背压)
"""
import socket
import sys
import time

import serial

SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
PAY = b"\xaa\x55"


def wait_echo(sk, timeout=8.0, n=1):
    got = []
    t0 = time.time()
    while time.time() - t0 < timeout and len(got) < n:
        try:
            d, _ = sk.recvfrom(2048)
            got.append(d)
        except socket.timeout:
            pass
    return got


def drain(sk, quiet=1.2):
    """排空到静默 quiet 秒为止（清掉预热/ARP 等残留回显）。"""
    n = 0
    while True:
        try:
            sk.recvfrom(2048)
            n += 1
        except socket.timeout:
            break
    return n


def main():
    s = serial.Serial("COM5", 9600, timeout=0.2)
    sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sk.bind((SRC_IP, SRC_PORT))
    sk.settimeout(0.3)
    s.reset_input_buffer()
    for _ in range(3):
        sk.sendto(b"warm", (DST_IP, DST_PORT))
        time.sleep(0.2)
    print("drained after warmup: %d" % drain(sk))

    # --- 桥模式对照 ---
    s.reset_input_buffer()
    sk.sendto(PAY, (DST_IP, DST_PORT))
    br = wait_echo(sk, 6.0)
    print("BRIDGE(engine=0): echo=%d  %s" % (len(br), [x.hex() for x in br]))
    print("  match: %s" % ("YES" if any(x == PAY for x in br) else "NO"))
    drain(sk)

    # --- E 模式 ---
    s.reset_input_buffer()
    s.write(b"E")
    time.sleep(0.1)
    s.reset_input_buffer()
    sk.sendto(PAY, (DST_IP, DST_PORT))
    e = wait_echo(sk, 8.0)
    uart = b""
    t0 = time.time()
    while time.time() - t0 < 6:
        uart += s.read(4096)
    print("E(engine=DMA): echo=%d  %s" % (len(e), [x.hex() for x in e]))
    print("  match: %s" % ("YES" if any(x == PAY for x in e) else "NO"))
    print("UART>>>")
    print(uart.decode("ascii", errors="replace"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
