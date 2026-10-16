# -*- coding: utf-8 -*-
"""rdcap_send.py — 给「发射字节流」ILA 捕获配一个已知帧(桥模式或 E 模式各跑一次)。

用法: python rdcap_send.py --mode bridge|e [--com COM5]
判据: 桥模式应回显逐字节一致(正对照); E 模式预期 0 回显(现象复现)。
载荷 = 自描述模式 byte[i] = i & 0xFF (1472B) —— 帧内任意 4 字节窗口可反解偏移。
"""
import argparse
import socket
import subprocess
import sys
import time

import serial

SRC_IP, SRC_PORT = "192.168.1.102", 1234
DST_IP, DST_PORT = "192.168.1.10", 1234
LEN = 1472


def payload():
    return bytes((i & 0xFF) for i in range(LEN))


def drain(sk):
    n = 0
    while True:
        try:
            sk.recvfrom(2048)
            n += 1
        except socket.timeout:
            break
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["bridge", "e"], required=True)
    ap.add_argument("--com", default="COM5")
    a = ap.parse_args()

    s = serial.Serial(a.com, 9600, timeout=0.2)
    sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sk.bind((SRC_IP, SRC_PORT))
    sk.settimeout(0.3)

    # 预热(ARP/暖机)已在捕获武装之前由 rdcap_warm.py 完成 —— 此处只发目标帧,
    # 保证「武装后第一次发射」就是目标帧(否则触发点会落在 ping 应答/暖机帧上)。
    if a.mode == "e":
        s.reset_input_buffer()
        s.write(b"E")
        time.sleep(0.1)

    s.reset_input_buffer()
    sk.sendto(payload(), (DST_IP, DST_PORT))
    got = []
    t0 = time.time()
    while time.time() - t0 < 6.0 and not got:
        try:
            d, _ = sk.recvfrom(2048)
            got.append(d)
        except socket.timeout:
            pass
    uart = b""
    t0 = time.time()
    while time.time() - t0 < 4.0:
        uart += s.read(4096)
    print("MODE=%s echo=%d match=%s"
          % (a.mode, len(got), "YES" if got and got[0] == payload() else "NO"))
    if uart.strip():
        print("UART:", uart.decode("ascii", errors="replace").strip().replace("\r\n", " | "))
    return 0


if __name__ == "__main__":
    sys.exit(main())
