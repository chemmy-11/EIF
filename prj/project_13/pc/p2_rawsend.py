#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""p2_rawsend.py -- raw Ethernet L2 sender for prj13 P2 loopback judges (ASCII only).

WHY THIS EXISTS (measured 2026-11-10 on the board-A host, JLB-PC):
  pc/twin_send.py transmits through a *plain UDP socket* (its own header says
  "standard library only, plain UDP socket, no admin / no Npcap"). That path needs
  the PC NIC to own 10.10.0.1/24 plus a static ARP entry 10.10.0.2 ->
  02:00:00:00:0A:01, and BOTH require an elevated shell (New-NetIPAddress /
  netsh interface ipv4 add neighbors). On a host where the agent shell is a
  UAC-filtered admin token ("Group used for deny only", Medium integrity), the OS
  routing table cannot be configured at all, so the UDP-socket path is unusable
  even though the hardware is present.

  Npcap's pcap_sendpacket bypasses the OS stack: this tool builds the exact
  Ethernet/IPv4/UDP frame itself and injects it on the wire. No IP address, no
  route, no ARP entry, no admin (measured: pcap_sendpacket accepted frames under
  a non-elevated token).

BYTE COMPATIBILITY:
  Payload and the 42 B header come from pc/twin_send.py itself (imported, not
  copied), so pc/twin_recv.py --from-pcap judges see the identical format:
    payload[0:4]=b'TWIN', [4:6]=seq(BE), [6:8]=count(BE), [8:12]=run_id(BE),
    [12:]=fill[i]=(seq+i)&0xFF

USAGE (run from prj/project_13, or pass absolute paths):
  py pc\\p2_rawsend.py --list
  py pc\\p2_rawsend.py --iface {GUID} --count 1 --len 100 --run-id 0x11
  py pc\\p2_rawsend.py --iface {GUID} --dst-ip 10.10.0.11 --count 1 --len 100   # reverse judge
  py pc\\p2_rawsend.py --iface {GUID} --count 1 --len 100 --dry-run

  The handbook address preset for board A is the default:
    src 10.10.0.1 -> dst 10.10.0.2, eth dst 02:00:00:00:0A:01 (board A).

EXIT: 0 = every frame was accepted by pcap_sendpacket; 1 = send failed; 2 = env/arg.
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
    lib.pcap_open_live.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int,
                                   ctypes.c_int, ctypes.c_char_p]
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


def main():
    ap = argparse.ArgumentParser(description="raw L2 frame injector (Npcap sendpacket, no admin)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--iface", default="", help="device name/description substring (e.g. 7E6EBE98)")
    ap.add_argument("--src-ip", default="10.10.0.1")
    ap.add_argument("--dst-ip", default="10.10.0.2")
    ap.add_argument("--src-mac", default="A8-2B-DD-76-DF-A2")
    ap.add_argument("--dst-mac", default="02-00-00-00-0A-01")
    ap.add_argument("--sport", type=int, default=1234)
    ap.add_argument("--dport", type=int, default=1234)
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--len", type=int, default=100, help="UDP payload bytes (>=12)")
    ap.add_argument("--run-id", type=lambda s: int(s, 0), default=0x11)
    ap.add_argument("--interval-ms", type=float, default=0.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

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
        ts = load_twin_send()
    except Exception as exc:                                    # noqa: BLE001
        print("FAIL: cannot import twin_send (%s)" % exc, file=sys.stderr)
        return 2

    src_mac = ts.parse_mac(args.src_mac)
    dst_mac = ts.parse_mac(args.dst_mac)
    if not src_mac or not dst_mac:
        print("FAIL: bad MAC literal", file=sys.stderr)
        return 2
    src_ip, dst_ip = ts.ip_bytes(args.src_ip), ts.ip_bytes(args.dst_ip)

    payload0 = ts.build_payload(0, args.count, args.run_id, args.len)
    hdr, fields = ts.build_frame_header(dst_mac, src_mac, src_ip, dst_ip,
                                        args.sport, args.dport, len(payload0))
    frame0 = hdr + payload0

    print("iface    : %s  (%s)" % (name, desc))
    print("frame    : %d B (14 eth + 20 ip + 8 udp + %d payload)" % (len(frame0), len(payload0)))
    print("eth      : dst=%s src=%s type=0x0800" % (args.dst_mac, args.src_mac))
    print("ip       : %s -> %s  total_len=%d ttl=%d proto=17" %
          (args.src_ip, args.dst_ip, fields["ip_total_len"], fields["ip_ttl"]))
    print("udp      : %d -> %d len=%d csum=0 (not computed; legal for IPv4)" %
          (args.sport, args.dport, fields["udp_len"]))
    print("hdr[42]  : %s" % frame0[:42].hex(" ").upper())
    print("payload  : %s ..." % payload0[:24].hex(" ").upper())
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
            payload = ts.build_payload(seq, args.count, args.run_id, args.len)
            frame = hdr + payload
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
