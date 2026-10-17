# -*- coding: utf-8 -*-
"""uart_probe.py -- 通用 UART 探针: 打开串口, 可选排空, 发命令, 收窗口, 打印。

用法:
  py uart_probe.py --cmd L --wait 3
  py uart_probe.py --cmd E --wait 60 --raw
约定: 命令 'I'/'L'/'S'/'d' 单字节; M/A/B 需要紧跟补码字节 (--pair)。
"""
import argparse
import sys
import time

import serial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM5")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--cmd", default="L")
    ap.add_argument("--pair", action="store_true", help="给 M/A/B 追加补码字节")
    ap.add_argument("--wait", type=float, default=3.0, help="发命令后的收窗口(秒)")
    ap.add_argument("--preboot", type=float, default=0.0, help="打开串口后先等多久再排空(秒)")
    ap.add_argument("--drain", type=float, default=0.3, help="排空时长(秒)")
    ap.add_argument("--no-drain", action="store_true")
    ap.add_argument("--raw", action="store_true", help="直接打印文本而非 repr")
    ap.add_argument("--repeat", type=int, default=1)
    a = ap.parse_args()

    s = serial.Serial(a.port, a.baud, timeout=0.2)
    time.sleep(a.preboot) if a.preboot else None
    if not a.no_drain and a.drain > 0:
        s.reset_input_buffer()
        t0 = time.time()
        junk = b""
        while time.time() - t0 < a.drain:
            junk += s.read(4096)
        if junk:
            print("[drain] %r" % junk, flush=True)

    payload = a.cmd.encode("latin-1")
    if a.pair and a.cmd:
        c = ord(a.cmd[0])
        payload += bytes([(~c) & 0xFF])

    for k in range(a.repeat):
        print("[tx] %r" % payload, flush=True)
        s.write(payload)
        s.flush()
        t0 = time.time()
        out = b""
        while time.time() - t0 < a.wait:
            chunk = s.read(4096)
            if chunk:
                out += chunk
                t0 = time.time()
        if a.raw:
            sys.stdout.write(out.decode("latin-1"))
            print("", flush=True)
        else:
            print("[rx%d] %r" % (k, out), flush=True)
    s.close()


if __name__ == "__main__":
    main()
