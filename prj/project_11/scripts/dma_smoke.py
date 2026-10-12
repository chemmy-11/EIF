#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dma_smoke.py — prj11 B3-1a 板上冒烟（AXI DMA MM2S 通路一笔验证）

一次性验完: 时钟域(控制 100M / MM2S 300M 与 MIG 同域) + 512b 位宽 + 地址映射
(SA = 0x0010_0000 + slot*4096) + TKEEP 语义 + 仲裁器 S02 真连。

步骤:
  1) PC 发 1 帧 64B(seq 已知) -> 桥① 写入最后一帧槽 (SEQ 回显确认提交)
  2) PC 发 'D' -> C: 复位 DMA -> RS -> SA=最后帧槽 -> LENGTH=64(触发)
     -> 等 Idle -> 读 dma_sink 回读 -> 打印 "[B2] DMA sa=.. sr=.. q0=.. q1=.. q2=.."
  3) PC 判据:
     q0 == 0x00010040  (beats=1, bytes=64)
     q1 == seq         (首拍低 32bit = 载荷前 4 字节 = seq LE)
     q2 == 0x01800000  (done_cnt=1, tlast_seen=1, busy=0)
     sr  Idle=1 且 err 位(bit12/13/14)=0

用法: set PYTHONUTF8=1 & python dma_smoke.py --seq 70001
"""
from __future__ import annotations

import argparse
import re
import sys
import time

sys.path.insert(0, r"D:\FPGA\prj\project_10\prj_loop\scripts")
from j3_random_read import (CmdClient, DataPlane, build_payload,  # noqa: E402
                            MODE_SEQ, warmup_link)

SERIAL = None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--seq", type=int, default=70001)
    p.add_argument("--com", default="COM5")
    a = p.parse_args()

    import serial
    s = serial.Serial(a.com, 9600, timeout=0.2)

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

    cli = CmdClient("192.168.1.102")
    dm = DataPlane("192.168.1.102")

    print("=== B3-1a DMA 冒烟 ===")
    cli.set_mode(MODE_SEQ)
    warmup_link(dm.dst[0], dm.dst[1], enabled=True, settle_s=0.8,
                bind_ip="192.168.1.102")
    time.sleep(0.3)
    dm.drain(0.3)

    # 1) 写一帧 64B (seq 已知), 等回显确认提交
    dm.send(build_payload(a.seq, 9, 64))
    echo = dm.drain(1.5)
    print("写帧 seq=%d, 回显 %d 帧 (SEQ 确认提交)" % (a.seq, len(echo)))
    if not echo:
        print("DMA_SMOKE: FAIL (帧未提交/未回显)")
        return 1
    time.sleep(0.3)

    # 2) 触发 C 侧 'D'
    s.reset_input_buffer()
    s.write(b"D")
    line = None
    for _ in range(60):
        line = uart_line(0.2)
        if line and "[B2] DMA" in line:
            break
    print("C 行: %s" % line)
    if not line:
        print("DMA_SMOKE: FAIL (未收到 DMA 行)")
        return 1

    m = re.search(r"sa=([0-9a-f]+) sr=([0-9a-f]+) q0=([0-9a-f]+) "
                  r"q1=([0-9a-f]+) q2=([0-9a-f]+)", line)
    if not m:
        print("DMA_SMOKE: FAIL (行解析失败)")
        return 1
    sa, sr, q0, q1, q2 = (int(x, 16) for x in m.groups())

    errs = []
    if q0 != 0x00010040:
        errs.append("q0=%08x != 00010040 (beats/bytes)" % q0)
    if q1 != (a.seq & 0xFFFFFFFF):
        errs.append("q1=%08x != seq %08x (首拍内容)" % (q1, a.seq & 0xFFFFFFFF))
    if q2 != 0x01800000:
        errs.append("q2=%08x != 01800000 (done/tlast)" % q2)
    if not (sr & 0x2):
        errs.append("sr=%04x Idle 未置位" % sr)
    if sr & 0x7000:
        errs.append("sr=%04x err 位置位" % sr)

    print("-" * 60)
    if errs:
        print("DMA_SMOKE: FAIL")
        for e in errs:
            print("  - %s" % e)
        return 1
    print("DMA_SMOKE: PASS (时钟域/512b/地址映射/TKEEP/S02 全通)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
