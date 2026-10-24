#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
twin_send.py — prj12 P1: PC1 侧 UDP 发送器（P1-03/P1-04 的"流量源"）

设计约束（来自 prj11/草案）:
  * 只用标准库，普通 UDP socket，不需要管理员/Npcap；
  * payload 自带可校验结构（magic/seq/count/run_id/fill），让 PC2 侧抓到后能逐字节判真伪，
    而不是"数帧数"；
  * --dry-run 只打印计划（板卡不在场时可验参数与 payload 构造）。

payload 布局（大端）:
   0..3   b"TWIN"
   4..5   seq (uint16)
   6..7   count (uint16)
   8..11  run_id (uint32)
   12..   fill[i] = (seq + i) & 0xFF
最小 12 B；--len 默认 100（覆盖帧长 %8 的多种余数由 --len 变化实现）。

用法:
  py pc\\twin_send.py --dst-ip 192.168.1.10 --dst-port 1234 --count 20 --len 100
  py pc\\twin_send.py --dry-run            # 不发包，打印计划 + 前 3 个 payload 的 hex
"""
import argparse
import socket
import sys
import time

MAGIC = b"TWIN"
MIN_LEN = 12


def build_payload(seq, total, run_id, length):
    if length < MIN_LEN:
        raise ValueError(f"--len must be >= {MIN_LEN}")
    head = MAGIC + seq.to_bytes(2, "big") + total.to_bytes(2, "big") + run_id.to_bytes(4, "big")
    body = bytes(((seq + i) & 0xFF) for i in range(MIN_LEN, length))
    return head + body


def main():
    ap = argparse.ArgumentParser(description="prj12 P1 UDP sender (PC1 side)")
    ap.add_argument("--dst-ip", default="192.168.1.10", help="板卡 IP（默认 192.168.1.10）")
    ap.add_argument("--dst-port", type=int, default=1234, help="板卡 UDP 端口（默认 1234）")
    ap.add_argument("--src-ip", default=None, help="绑定本机源 IP（默认由路由决定）")
    ap.add_argument("--count", type=int, default=20, help="发送帧数")
    ap.add_argument("--len", type=int, default=100, help="每帧 UDP payload 长度（>=12）")
    ap.add_argument("--run-id", type=lambda s: int(s, 0), default=0x00000001, help="本次运行 ID")
    ap.add_argument("--interval-ms", type=float, default=20.0, help="帧间隔（ms）")
    ap.add_argument("--dry-run", action="store_true", help="只打印计划，不发包")
    args = ap.parse_args()

    if args.len < MIN_LEN:
        print(f"FAIL: --len {args.len} < {MIN_LEN}", file=sys.stderr)
        return 1
    if not (0 <= args.count <= 65535):
        print("FAIL: --count must be 0..65535", file=sys.stderr)
        return 1

    print("=== twin_send ===")
    print(f"dst      : {args.dst_ip}:{args.dst_port}/udp")
    print(f"count    : {args.count}  len={args.len}  run_id=0x{args.run_id:08X}")
    print(f"interval : {args.interval_ms} ms")
    for seq in range(min(3, args.count)):
        p = build_payload(seq, args.count, args.run_id, args.len)
        print(f"  seq={seq:5d} len={len(p):4d} head={p[:24].hex()}")

    if args.dry_run:
        print("DRY_RUN: 未发包。去掉 --dry-run 才真正发送。")
        return 0

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.src_ip:
        sock.bind((args.src_ip, 0))
    sent = 0
    try:
        for seq in range(args.count):
            p = build_payload(seq, args.count, args.run_id, args.len)
            sock.sendto(p, (args.dst_ip, args.dst_port))
            sent += 1
            if args.interval_ms > 0:
                time.sleep(args.interval_ms / 1000.0)
    except OSError as e:
        print(f"FAIL: send error after {sent} frames: {e}", file=sys.stderr)
        return 1
    finally:
        sock.close()
    print(f"SEND_OK: {sent}/{args.count} frames to {args.dst_ip}:{args.dst_port}")
    print("NOTE: P1 语义 = 回显帧从**对端板**网口出去（目的仍是本机），PC1 本机不应收到回包。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
