#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_fake_pcaps.py — 为 p13_pcap_audit.py 造三组负向对照（不需网卡/不需要板）

N1 正常帧      cap == ip.len + 14            -> 审计应 PASS
N2 截断帧      cap <  ip.len + 14（短 64 B）  -> 审计应 FAIL（判据1）
N3 ARP 帧      以太类型 0x0806                -> 审计应 FAIL（判据3）

输出目录由 --outdir 指定（默认 .tmp\dryrun-<today>），文件名 fake_*.pcap。
"""
import argparse
import os
import struct
import time

ETH = 14


def csum(d):
    if len(d) % 2:
        d += b"\x00"
    s = sum(struct.unpack("!%dH" % (len(d) // 2), d))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def eth(dst, src, etype):
    return dst + src + struct.pack("!H", etype)


def mac(s):
    return bytes(int(x, 16) for x in s.split(":"))


def ipv4(src, dst, payload, proto=17):
    total = 20 + len(payload)
    hdr = struct.pack("!BBHHHBBH4s4s", 0x45, 0, total, 0, 0x4000, 64, proto, 0,
                      bytes(int(x) for x in src.split(".")),
                      bytes(int(x) for x in dst.split(".")))
    hdr = hdr[:10] + struct.pack("!H", csum(hdr)) + hdr[12:]
    return hdr + payload


def udp(sport, dport, data):
    return struct.pack("!HHHH", sport, dport, 8 + len(data), 0) + data


BOARD_MAC = "02:00:00:00:0a:01"   # 板 A
PC_MAC    = "08:3c:03:a0:26:96"   # PC1 网卡
BOARD_IP  = "10.10.0.11"
PC_IP     = "10.10.0.1"


def frame_udp(payload_len=100, truncate=0):
    """板卡发出的一帧（src=板 MAC，dst=PC MAC）——与 frame_arp 保持同源，才能被 --src-mac 一致收窄。"""
    body = b"TWIN" + struct.pack("!HH", 0, 1) + struct.pack("!I", 0x1) + b"\x00" * (payload_len - 12)
    l3 = ipv4(BOARD_IP, PC_IP, udp(47001, 47001, body))
    f = eth(mac(PC_MAC), mac(BOARD_MAC), 0x0800) + l3
    if truncate:
        f = f[:-truncate]
    return f


def frame_arp():
    a = struct.pack("!HHBBH6s4s6s4s", 1, 0x0800, 6, 4, 1,
                    mac(BOARD_MAC), bytes([10, 10, 0, 11]),
                    mac(PC_MAC), bytes([10, 10, 0, 1]))
    return eth(mac("ff:ff:ff:ff:ff:ff"), mac(BOARD_MAC), 0x0806) + a


def write_pcap(path, frames):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        t0 = int(time.time())
        for i, fr in enumerate(frames):
            f.write(struct.pack("<IIII", t0 + i, 0, len(fr), len(fr)))
            f.write(fr)
    return os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="")
    a = ap.parse_args()
    outdir = a.outdir or os.path.join(".", "dryrun")
    os.makedirs(outdir, exist_ok=True)

    n1 = [frame_udp(100) for _ in range(3)]
    p1 = os.path.join(outdir, "fake_n1_ok.pcap")

    n2 = [frame_udp(100, truncate=64) for _ in range(3)]
    p2 = os.path.join(outdir, "fake_n2_trunc64.pcap")

    n3 = [frame_udp(100) for _ in range(2)] + [frame_arp() for _ in range(2)]
    p3 = os.path.join(outdir, "fake_n3_arp.pcap")

    for p, fr in ((p1, n1), (p2, n2), (p3, n3)):
        sz = write_pcap(p, fr)
        print("%s  frames=%d bytes=%d  first_len=%d" % (p, len(fr), sz, len(fr[0])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
