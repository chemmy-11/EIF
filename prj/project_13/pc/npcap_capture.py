#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
npcap_capture.py — prj12 P1: 用 Npcap 运行时（wpcap.dll）在 PC 上直接抓包，
不依赖 dumpcap / Wireshark（无需管理员，只要 Npcap 运行时已安装）。

为什么需要：PC1/PC2 都可能没有 dumpcap（Wireshark 未装，装它要管理员）。
2026-11-06 实测两台机器都有 `C:\\Windows\\System32\\wpcap.dll`，用 ctypes 直接调
pcap_findalldevs / pcap_open_live / pcap_next_ex 就能落标准 classic pcap，
`twin_recv.py --from-pcap` 可直接解析。

用法:
  py pc\\npcap_capture.py -D                       # 列网卡（名字 + 描述）
  py pc\\npcap_capture.py --iface Realtek --seconds 30 --out out\\pc1.pcap
  py pc\\npcap_capture.py --iface 以太网 --seconds 30 --out out\\pc1.pcap --promisc
  py pc\\npcap_capture.py --iface Realtek --seconds 5 --out out\\x.pcap --dry-run

退出码: 0 = 抓包完成且写出文件；1 = 失败；2 = 参数/环境问题。
"""
import argparse
import ctypes
import ctypes.util
import os
import struct
import sys
import time

PCAP_ERRBUF_SIZE = 256
PCAP_IF_LOOPBACK = 0x1


class PcapError(Exception):
    pass


class pcap_addr(ctypes.Structure):
    pass


pcap_addr._fields_ = [("next", ctypes.POINTER(pcap_addr)),
                      ("addr", ctypes.c_void_p),
                      ("netmask", ctypes.c_void_p),
                      ("broadaddr", ctypes.c_void_p),
                      ("dstaddr", ctypes.c_void_p)]


class pcap_if(ctypes.Structure):
    pass


pcap_if._fields_ = [
    ("next", ctypes.POINTER(pcap_if)),
    ("name", ctypes.c_char_p),
    ("description", ctypes.c_char_p),
    ("addresses", ctypes.POINTER(pcap_addr)),
    ("flags", ctypes.c_uint),
    ("errbuf", ctypes.c_char * PCAP_ERRBUF_SIZE),
]


class pcap_pkthdr(ctypes.Structure):
    _fields_ = [
        ("ts_sec", ctypes.c_uint32),
        ("ts_usec", ctypes.c_uint32),
        ("caplen", ctypes.c_uint32),
        ("len", ctypes.c_uint32),
    ]


def load_wpcap():
    for cand in ("wpcap.dll", r"C:\Windows\System32\wpcap.dll", r"C:\Windows\SysWOW64\wpcap.dll"):
        try:
            lib = ctypes.WinDLL(cand)
            break
        except OSError:
            lib = None
    if lib is None:
        raise PcapError("wpcap.dll 未找到：本机没装 Npcap/WinPcap 运行时（装 Wireshark 或 Npcap 运行时即可，无需管理员用本脚本）")
    lib.pcap_findalldevs.argtypes = [ctypes.POINTER(ctypes.POINTER(pcap_if)), ctypes.c_char_p]
    lib.pcap_findalldevs.restype = ctypes.c_int
    lib.pcap_freealldevs.argtypes = [ctypes.POINTER(pcap_if)]
    lib.pcap_open_live.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_char_p]
    lib.pcap_open_live.restype = ctypes.c_void_p
    lib.pcap_next_ex.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.POINTER(pcap_pkthdr)),
                                 ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte))]
    lib.pcap_next_ex.restype = ctypes.c_int
    lib.pcap_close.argtypes = [ctypes.c_void_p]
    lib.pcap_datalink.argtypes = [ctypes.c_void_p]
    lib.pcap_datalink.restype = ctypes.c_int
    return lib


def list_devices(lib):
    alldevs = ctypes.POINTER(pcap_if)()
    errbuf = ctypes.create_string_buffer(PCAP_ERRBUF_SIZE)
    if lib.pcap_findalldevs(ctypes.byref(alldevs), errbuf) != 0:
        raise PcapError("pcap_findalldevs failed: %s" % errbuf.value.decode("utf-8", "replace"))
    devs = []
    p = alldevs
    while p:
        d = p.contents
        name = (d.name or b"").decode("utf-8", "replace")
        desc = (d.description or b"").decode("utf-8", "replace")
        devs.append((name, desc, d.flags))
        p = d.next
    lib.pcap_freealldevs(alldevs)
    return devs


def pick_device(devs, needle):
    needle_l = needle.lower()
    for name, desc, flags in devs:
        if needle_l in name.lower() or needle_l in desc.lower():
            return name, desc
    return None, None


def main():
    ap = argparse.ArgumentParser(description="Npcap (wpcap.dll) pcap capture, no dumpcap needed")
    ap.add_argument("-D", "--list", action="store_true", help="只列网卡")
    ap.add_argument("--iface", default=None, help="网卡名或描述的子串（如 Realtek / 以太网）")
    ap.add_argument("--seconds", type=float, default=30.0, help="抓包时长")
    ap.add_argument("--out", default=None, help="输出 classic pcap 路径")
    ap.add_argument("--snaplen", type=int, default=65535)
    ap.add_argument("--promisc", action="store_true", help="混杂模式（默认开；--no-promisc 关）")
    ap.add_argument("--no-promisc", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    try:
        lib = load_wpcap()
    except PcapError as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        return 2

    devs = list_devices(lib)
    if args.list or not args.iface:
        print("=== Npcap devices ===")
        for name, desc, flags in devs:
            print("  %-42s  %s%s" % (name, desc, "  [loopback]" if flags & PCAP_IF_LOOPBACK else ""))
        if not args.iface:
            print("HINT: 用 --iface <名字子串> 选网卡（如 --iface Realtek 或 --iface 以太网）")
            return 0

    name, desc = pick_device(devs, args.iface)
    if name is None:
        print("FAIL: 没有匹配 '%s' 的网卡；-D 看列表" % args.iface, file=sys.stderr)
        return 2
    print("iface : %s  (%s)" % (name, desc))

    if args.out is None:
        args.out = os.path.join("out", "npcap_%s.pcap" % time.strftime("%Y%m%d_%H%M%S"))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    promisc = 0 if args.no_promisc else 1
    print("out   : %s" % args.out)
    print("dur   : %.1f s   promisc=%d" % (args.seconds, promisc))
    if args.dry_run:
        print("DRY_RUN: 未抓包")
        return 0

    errbuf = ctypes.create_string_buffer(PCAP_ERRBUF_SIZE)
    handle = lib.pcap_open_live(name.encode(), args.snaplen, promisc, 1000, errbuf)
    if not handle:
        print("FAIL: pcap_open_live: %s" % errbuf.value.decode("utf-8", "replace"), file=sys.stderr)
        return 1
    linktype = lib.pcap_datalink(handle)
    print("linktype: %d (1=Ethernet)" % linktype)
    if linktype != 1:
        print("WARN: 非 Ethernet linktype，twin_recv 只支持 EN10MB", file=sys.stderr)

    fh = open(args.out, "wb")
    fh.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, args.snaplen, linktype))

    hdr = ctypes.POINTER(pcap_pkthdr)()
    data = ctypes.POINTER(ctypes.c_ubyte)()
    count = 0
    t0 = time.time()
    try:
        while time.time() - t0 < args.seconds:
            rc = lib.pcap_next_ex(handle, ctypes.byref(hdr), ctypes.byref(data))
            if rc == 0:          # timeout
                continue
            if rc == -1:         # error
                print("WARN: pcap_next_ex error", file=sys.stderr)
                break
            if rc == -2:         # breakloop (not used)
                break
            h = hdr.contents
            buf = ctypes.string_at(data, h.caplen)
            fh.write(struct.pack("<IIII", h.ts_sec, h.ts_usec, h.caplen, h.len))
            fh.write(buf)
            count += 1
    finally:
        fh.close()
        lib.pcap_close(handle)

    size = os.path.getsize(args.out)
    print("CAPTURE_OK: %s  frames=%d  bytes=%d  elapsed=%.1fs" % (args.out, count, size, time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
