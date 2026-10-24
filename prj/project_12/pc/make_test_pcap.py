#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_test_pcap.py — prj12 P1: 造一份"假 pcap"来离线验证 PC2 判据脚本

为什么需要: 板卡不在场时，twin_recv.py 的解析/判据逻辑必须能被证明"不是橡皮图章"。
本脚本按 P1 的真实帧形状造帧（src=板卡 MAC、dst=PC1 网卡 MAC、UDP、payload=twin_send 格式）：
  --mode good  : 全部帧合法 -> twin_recv 应 PASS
  --mode bad   : 第 2 帧 fill 破坏 -> twin_recv 应 FAIL（负向对照）
  --mode none  : 只有无关帧      -> twin_recv 应 FAIL（空集对照）

用法:
  py pc\\make_test_pcap.py --out out/mock_pc2_good.pcap --mode good --count 5
  py pc\\twin_recv.py --from-pcap out/mock_pc2_good.pcap --expect-count 5      # 期望 PASS
  py pc\\make_test_pcap.py --out out/mock_pc2_bad.pcap --mode bad --count 5
  py pc\\twin_recv.py --from-pcap out/mock_pc2_bad.pcap                        # 期望 FAIL
"""
import argparse
import struct
import sys

from twin_send import build_payload

BOARD_MAC = bytes.fromhex("001122334455")          # 回显帧的源 MAC（板卡）
PC1_MAC = bytes.fromhex("aabbccddeeff")            # 回显帧的目的 MAC（PC1）
PC1_IP = bytes([192, 168, 1, 102])
BOARD_IP = bytes([192, 168, 1, 10])


def _ip_checksum(hdr):
    s = 0
    for i in range(0, len(hdr), 2):
        s += (hdr[i] << 8) + (hdr[i + 1] if i + 1 < len(hdr) else 0)
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def build_eth_ip_udp(payload, dst_mac=PC1_MAC, src_mac=BOARD_MAC,
                     src_ip=BOARD_IP, dst_ip=PC1_IP, sport=1234, dport=1234):
    udp_len = 8 + len(payload)
    udp = struct.pack(">HHHH", sport, dport, udp_len, 0) + payload
    ip_len = 20 + udp_len
    ip = struct.pack(">BBHHHBBH4s4s", 0x45, 0, ip_len, 0x1234, 0, 64, 17, 0,
                     src_ip, dst_ip)
    ip = ip[:10] + struct.pack(">H", _ip_checksum(ip)) + ip[12:]
    eth = dst_mac + src_mac + struct.pack(">H", 0x0800)
    return eth + ip + udp


def write_pcap(path, frames):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        ts = 1700000000
        for i, fr in enumerate(frames):
            f.write(struct.pack("<IIII", ts + i, i * 1000, len(fr), len(fr)))
            f.write(fr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=["good", "bad", "none"], default="good")
    ap.add_argument("--count", type=int, default=5)
    ap.add_argument("--len", type=int, default=100)
    args = ap.parse_args()

    frames = []
    for seq in range(args.count):
        p = bytearray(build_payload(seq, args.count, 0x00000001, args.len))
        if args.mode == "bad" and seq == 1 and len(p) > 20:
            p[20] ^= 0xFF           # 破坏第 2 帧的 fill 区，twin_recv 必须发现
        frames.append(build_eth_ip_udp(bytes(p)))
    if args.mode == "none":
        frames = [build_eth_ip_udp(b"OTHERDATA" * 5, src_mac=bytes.fromhex("001122334466"))]

    write_pcap(args.out, frames)
    print(f"MOCK_PCAP: {args.out} mode={args.mode} frames={len(frames)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
