#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""m1a_inject.py -- prj12 M1-A 错误注入器（raw Ethernet L2，Npcap sendpacket，免管理员）。

WHY: M1-A-6 要求"错误可报告"，但 pc/twin_send.py 只能改 --len，造不出
     坏 IP checksum / 坏 EtherType / 截断帧 / 超长帧。本工具用 Npcap
     pcap_sendpacket 直接注入二层帧（不经过 OS 栈，不需要 IP/路由/ARP/管理员），
     payload 与 twin_send.py 完全同构（TWIN/seq/count/run_id/fill），
     因此 pc/twin_recv.py --from-pcap 的判据仍适用。

MODES:
  ok            正常帧（对照；用于确认注入器本身可被 twins 判据识别）
  oversize      超长帧：frame 1560 B（> MAX_LEN 1538），IP total_len 1546（>1500）
  truncate      runt 帧：只发前 --truncate-to 字节（默认 50 B）
  bad-ipcsum    IP 头 checksum 故意写错（其余合法）
  bad-ethertype EtherType 改成 0x86DD（IPv6），内容仍是 IPv4
  bad-udplen    UDP len 字段 < 实际（IP total_len 仍对）

USAGE（在 prj/project_12 下）:
  py pc\\m1a_inject.py --list
  py pc\\m1a_inject.py --iface {GUID} --mode ok --count 1 --len 100 --dry-run
  py pc\\m1a_inject.py --iface {GUID} --mode bad-ipcsum --count 1 --run-id 0x95
注：注入器只负责"发坏帧"，计数器增量由 ILA/串口/判据脚本在板上读取并前后对账。
"""
import argparse
import ctypes
import importlib.util
import os
import struct
import sys
import time

PCAP_ERRBUF_SIZE = 256
HERE = os.path.dirname(os.path.abspath(__file__))
TWIN_SEND = os.path.join(HERE, "twin_send.py")
MIN_LEN = 12


class pcap_addr(ctypes.Structure):
    pass


pcap_addr._fields_ = [("next", ctypes.POINTER(pcap_addr)),
                      ("addr", ctypes.c_void_p),
                      ("netmask", ctypes.c_void_p),
                      ("broadaddr", ctypes.c_void_p),
                      ("dstaddr", ctypes.c_void_p)]


class pcap_if(ctypes.Structure):
    pass


pcap_if._fields_ = [("next", ctypes.POINTER(pcap_if)),
                    ("name", ctypes.c_char_p),
                    ("description", ctypes.c_char_p),
                    ("addresses", ctypes.POINTER(pcap_addr)),
                    ("flags", ctypes.c_uint),
                    ("errbuf", ctypes.c_char * PCAP_ERRBUF_SIZE)]


def load_wpcap():
    last = None
    for cand in ("wpcap.dll", r"C:\Windows\System32\wpcap.dll", r"C:\Windows\SysWOW64\wpcap.dll"):
        try:
            lib = ctypes.WinDLL(cand)
            break
        except OSError as exc:
            lib, last = None, exc
    if lib is None:
        raise RuntimeError("wpcap.dll not found: %s" % last)
    lib.pcap_findalldevs.argtypes = [ctypes.POINTER(ctypes.POINTER(pcap_if)), ctypes.c_char_p]
    lib.pcap_findalldevs.restype = ctypes.c_int
    lib.pcap_freealldevs.argtypes = [ctypes.POINTER(pcap_if)]
    lib.pcap_open_live.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_char_p]
    lib.pcap_open_live.restype = ctypes.c_void_p
    lib.pcap_close.argtypes = [ctypes.c_void_p]
    lib.pcap_sendpacket.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    lib.pcap_sendpacket.restype = ctypes.c_int
    lib.pcap_geterr.argtypes = [ctypes.c_void_p]
    lib.pcap_geterr.restype = ctypes.c_char_p
    return lib


def list_devices(lib):
    alldevs = ctypes.POINTER(pcap_if)()
    errbuf = ctypes.create_string_buffer(PCAP_ERRBUF_SIZE)
    if lib.pcap_findalldevs(ctypes.byref(alldevs), errbuf) != 0:
        raise RuntimeError("pcap_findalldevs: %s" % errbuf.value.decode("utf-8", "replace"))
    out, p = [], alldevs
    while p:
        d = p.contents
        out.append(((d.name or b"").decode("utf-8", "replace"),
                    (d.description or b"").decode("utf-8", "replace")))
        p = d.next
    lib.pcap_freealldevs(alldevs)
    return out


def load_twin_send():
    spec = importlib.util.spec_from_file_location("twin_send", TWIN_SEND)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_mac(text):
    parts = text.replace(":", "-").split("-")
    if len(parts) != 6:
        raise ValueError("bad MAC: %r" % text)
    return bytes(int(p, 16) for p in parts)


def ip_checksum(header):
    s = 0
    for i in range(0, len(header), 2):
        s += (header[i] << 8) | header[i + 1]
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def build_ipv4(src_ip, dst_ip, payload_len, ident, ttl=64, proto=17):
    total_len = 20 + 8 + payload_len
    hdr = struct.pack("!BBHHHBBH4s4s", 0x45, 0, total_len, ident, 0, ttl, proto, 0,
                      src_ip, dst_ip)
    csum = ip_checksum(hdr)
    hdr = hdr[:10] + struct.pack("!H", csum) + hdr[12:]
    return hdr, csum, total_len


def build_frame(args, mod, seq):
    payload = mod.build_payload(seq, args.count, args.run_id, args.len)
    ip_hdr, ip_csum, ip_total = build_ipv4(args.src_ip_b, args.dst_ip_b, len(payload),
                                           args.ident, proto=17)
    udp_len = 8 + len(payload)
    udp = struct.pack("!HHHH", args.sport, args.dport, udp_len, 0) + payload
    eth_type = 0x0800
    note = []
    if args.mode == "oversize":
        # 放大 payload 到 frame=1560（IP total_len=1546 > 1500，也 > MAX_LEN 1538）
        extra = 1560 - (14 + 20 + 8 + len(payload))
        payload = payload + bytes([(seq + i) & 0xFF for i in range(max(0, extra))])
        udp = struct.pack("!HHHH", args.sport, args.dport, 8 + len(payload), 0) + payload
        ip_hdr, ip_csum, ip_total = build_ipv4(args.src_ip_b, args.dst_ip_b, len(payload),
                                               args.ident, proto=17)
        note.append("oversize: frame=%d ip_total=%d" % (14 + 20 + len(udp), ip_total))
    elif args.mode == "bad-ipcsum":
        bad = (~ip_csum) & 0xFFFF
        ip_hdr = ip_hdr[:10] + struct.pack("!H", bad) + ip_hdr[12:]
        note.append("bad-ipcsum: stored=0x%04X real=0x%04X" % (bad, ip_csum))
    elif args.mode == "bad-ethertype":
        eth_type = 0x86DD
        note.append("bad-ethertype=0x86DD")
    elif args.mode == "bad-udplen":
        udp = struct.pack("!HHHH", args.sport, args.dport, 8, 0) + payload
        note.append("bad-udplen: udp_len=8 real=%d" % (8 + len(payload)))
    eth = args.dst_mac_b + args.src_mac_b + struct.pack("!H", eth_type)
    frame = eth + ip_hdr + udp
    if args.mode == "truncate":
        frame = frame[:args.truncate_to]
        note.append("truncate: sent=%d B" % len(frame))
    return frame, note, ip_total


def main():
    ap = argparse.ArgumentParser(description="prj12 M1-A bad-frame injector (Npcap, no admin)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--iface", default="", help="device name/description substring")
    ap.add_argument("--mode", default="ok",
                    choices=["ok", "oversize", "truncate", "bad-ipcsum", "bad-ethertype", "bad-udplen"])
    ap.add_argument("--src-ip", default="192.168.1.102")
    ap.add_argument("--dst-ip", default="192.168.1.10")
    ap.add_argument("--src-mac", default="08-3C-03-A0-26-96", help="PC 侧 MAC（可任意，仅作帧源）")
    ap.add_argument("--dst-mac", default="00-11-22-33-44-55", help="板卡 MAC")
    ap.add_argument("--sport", type=int, default=1234)
    ap.add_argument("--dport", type=int, default=1234)
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--len", type=int, default=100, help="UDP payload bytes (>=12)")
    ap.add_argument("--run-id", type=lambda s: int(s, 0), default=0x95)
    ap.add_argument("--ident", type=int, default=0x4D31, help="IPv4 identification")
    ap.add_argument("--truncate-to", type=int, default=50, help="truncate 模式发送字节数")
    ap.add_argument("--interval-ms", type=float, default=0.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.len < MIN_LEN:
        print("FAIL: --len must be >= %d" % MIN_LEN, file=sys.stderr)
        return 2
    try:
        args.src_mac_b = parse_mac(args.src_mac)
        args.dst_mac_b = parse_mac(args.dst_mac)
        args.src_ip_b = bytes(int(x) for x in args.src_ip.split("."))
        args.dst_ip_b = bytes(int(x) for x in args.dst_ip.split("."))
    except ValueError as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        return 2

    try:
        lib = load_wpcap()
        devs = list_devices(lib)
    except RuntimeError as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        return 2
    if args.list or not args.iface:
        print("=== Npcap devices ===")
        for name, desc in devs:
            print("  %-46s %s" % (name, desc))
        return 0 if args.list else 2
    needle = args.iface.lower()
    name = desc = None
    for n, d in devs:
        if needle in n.lower() or needle in d.lower():
            name, desc = n, d
            break
    if name is None:
        print("FAIL: no device matches %r" % args.iface, file=sys.stderr)
        return 2

    try:
        mod = load_twin_send()
    except Exception as exc:                                 # noqa: BLE001
        print("FAIL: cannot import twin_send (%s)" % exc, file=sys.stderr)
        return 2

    frame, notes, ip_total = build_frame(args, mod, 0)
    print("iface    : %s  (%s)" % (name, desc))
    print("mode     : %s  %s" % (args.mode, "; ".join(notes)))
    print("frame    : %d B  ip_total=%d  (MAX_LEN=1538, MTU payload limit=1500)" % (len(frame), ip_total))
    print("eth      : dst=%s src=%s" % (args.dst_mac, args.src_mac))
    print("ip       : %s -> %s  ident=0x%04X" % (args.src_ip, args.dst_ip, args.ident))
    print("head[42] : %s" % frame[:42].hex(" ").upper())
    print("plan     : count=%d len=%d run_id=0x%X interval=%.1f ms" %
          (args.count, args.len, args.run_id, args.interval_ms))
    if args.dry_run:
        print("DRY_RUN: nothing sent")
        return 0

    errbuf = ctypes.create_string_buffer(PCAP_ERRBUF_SIZE)
    handle = lib.pcap_open_live(name.encode(), 65535, 1, 1000, errbuf)
    if not handle:
        print("FAIL: pcap_open_live: %s" % errbuf.value.decode("utf-8", "replace"), file=sys.stderr)
        return 1
    ok = bad = 0
    try:
        for seq in range(args.count):
            frame, _notes, _ip = build_frame(args, mod, seq)
            rc = lib.pcap_sendpacket(handle, frame, len(frame))
            if rc == 0:
                ok += 1
            else:
                bad += 1
                err = lib.pcap_geterr(handle)
                print("FAIL: seq=%d rc=%d err=%s" %
                      (seq, rc, (err or b"").decode("utf-8", "replace")), file=sys.stderr)
                if bad >= 3:
                    break
            if args.interval_ms > 0:
                time.sleep(args.interval_ms / 1000.0)
    finally:
        lib.pcap_close(handle)
    print("SEND_DONE: ok=%d bad=%d" % (ok, bad))
    return 0 if bad == 0 and ok == args.count else 1


if __name__ == "__main__":
    sys.exit(main())
