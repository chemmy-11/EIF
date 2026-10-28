#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_test_pcap.py — prj12 P1: 造"假 pcap"离线压测 twin_recv.py 的判据

为什么需要：板卡不在场时，抓包判据脚本必须被证明"不是橡皮图章"。本脚本按 P1 真实帧形状造帧
（src=板卡 MAC、dst=PC1 网卡 MAC、UDP、payload=twin_send 结构），并覆盖现场可能出现的坏形状。

--shape 取值：
  good    全部合法（期望 twin_recv PASS）
  badfill 第 2 帧 fill 破坏（期望 FAIL：fill BAD）
  none    只有无关帧（期望 FAIL：matched=0）
  vlan    全部带 802.1Q 标签（期望 PASS + WARN vlan）
  fcs     全部尾部多 4B FCS（期望 PASS + INFO auto-trim）
  ooo     乱序（期望 PASS：seq 集合完整）
  dup     重复一帧（期望 FAIL，除非 --allow-dup）
  trunc   最后一帧被截断（期望 --expect-len 时 FAIL）
  lens    长度矩阵 26/40/63/100/200/1200/1496（配 --expect-len 判）
  mixed   5 好 + 1 坏 fill + 1 外来 MAC（期望 FAIL）

用法：
  py pc\\make_test_pcap.py --out out/mock_good.pcap --shape good --count 5
  py pc\\twin_recv.py --from-pcap out/mock_good.pcap --expect-count 5 --expect-len 100
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
                     src_ip=BOARD_IP, dst_ip=PC1_IP, sport=1234, dport=1234,
                     vlan=False, fcs=False):
    udp_len = 8 + len(payload)
    udp = struct.pack(">HHHH", sport, dport, udp_len, 0) + payload
    ip_len = 20 + udp_len
    ip = struct.pack(">BBHHHBBH4s4s", 0x45, 0, ip_len, 0x1234, 0, 64, 17, 0,
                     src_ip, dst_ip)
    ip = ip[:10] + struct.pack(">H", _ip_checksum(ip)) + ip[12:]
    if vlan:
        eth = dst_mac + src_mac + struct.pack(">HHH", 0x8100, 0x0064, 0x0800)
    else:
        eth = dst_mac + src_mac + struct.pack(">H", 0x0800)
    frame = eth + ip + udp
    if fcs:
        frame += b"\xde\xad\xbe\xef"
    return frame


def write_pcap(path, frames):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        ts = 1700000000
        for i, fr in enumerate(frames):
            f.write(struct.pack("<IIII", ts + i, i * 1000, len(fr), len(fr)))
            f.write(fr)


def payload_for(seq, total, length):
    return bytes(build_payload(seq, total, 0x00000001, length))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--shape", choices=["good", "badfill", "none", "vlan", "fcs",
                                       "ooo", "dup", "trunc", "lens", "mixed"],
                    default="good")
    ap.add_argument("--mode", choices=["good", "bad", "none"], default=None,
                    help="(旧参数名，等价于 --shape good/badfill/none)")
    ap.add_argument("--count", type=int, default=5)
    ap.add_argument("--len", type=int, default=100)
    args = ap.parse_args()

    shape = args.shape
    if args.mode:
        shape = {"good": "good", "bad": "badfill", "none": "none"}[args.mode]

    frames = []
    if shape == "lens":
        lens = [26, 40, 63, 100, 200, 1200, 1496]
        for i, L in enumerate(lens):
            frames.append(build_eth_ip_udp(payload_for(i, len(lens), L)))
        print("LENS:", lens)
    else:
        for seq in range(args.count):
            p = bytearray(payload_for(seq, args.count, args.len))
            if shape in ("badfill", "mixed") and seq == 1 and len(p) > 20:
                p[20] ^= 0xFF
            frames.append(build_eth_ip_udp(bytes(p),
                                           vlan=(shape == "vlan"),
                                           fcs=(shape == "fcs")))
        if shape == "none":
            frames = [build_eth_ip_udp(b"OTHERDATA" * 5, src_mac=bytes.fromhex("001122334466"))]
        elif shape == "ooo":
            order = list(range(len(frames)))
            order[0], order[1], order[2] = order[2], order[0], order[1]
            frames = [frames[i] for i in order]
        elif shape == "dup":
            frames.append(frames[1])
        elif shape == "trunc" and frames:
            frames[-1] = frames[-1][:-10]          # 截掉尾部 10B（udp_len 仍声明完整）
        elif shape == "mixed":
            frames.append(build_eth_ip_udp(payload_for(99, 100, args.len),
                                           src_mac=bytes.fromhex("001122334466")))

    write_pcap(args.out, frames)
    print(f"MOCK_PCAP: {args.out} shape={shape} frames={len(frames)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
