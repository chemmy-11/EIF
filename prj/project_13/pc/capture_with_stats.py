#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
capture_with_stats.py -- Npcap capture with pcap_stats readout (prj13 A1/A2 evidence).

Why this tool exists (EIF #18 "采集/烧录/配置" item):
  the stock npcap_capture.py has no statistics interface, so it cannot prove whether
  the kernel dropped packets during the capture window; therefore it cannot be used as
  the formal tool for continuity sign-off (T8) and for negative-case evidence.
  This script captures through the same wpcap.dll runtime and reads pcap_stats once
  BEFORE closing the handle, printing ps_recv / ps_drop / ps_ifdrop.

Usage (same conventions as the rest of this project):
  py -u capture_with_stats.py --list
  py -u capture_with_stats.py --iface "<GUID or description substring>" --seconds 30 --out out/pc1.pcap --promisc
  py -u capture_with_stats.py --iface Realtek --seconds 5 --out x.pcap --dry-run

stdout contract (one grep-able line per item):
  IFACE <name> | <description>
  CAPTURE_BEGIN <name> seconds=<n> promisc=<0|1> out=<path>
  PCAP_STATS: rc=0 ps_recv=<n> ps_drop=<n> ps_ifdrop=<n>
  CAPTURE_OK <out> bytes=<n> packets=<n> seconds=<n>
On failure: "PCAP_STATS: rc=<n> ..." and exit 1; bad args/environment exit 2.

Exit codes: 0 = captured and wrote the file; 1 = runtime failure; 2 = args/env problem.

Notes:
  * pure ctypes on wpcap.dll: no scapy / dumpcap / Wireshark, no admin rights needed.
  * classic pcap output (libpcap native). Whether the 8-byte preamble is included is
    decided by the NIC driver, exactly as with the stock tool.
  * ps_recv = packets handed to this process; ps_drop = packets dropped because the
    kernel buffer overflowed; ps_ifdrop = drops reported by the NIC (usually 0 on Windows).
"""

import argparse
import ctypes
import ctypes.util
import os
import struct
import sys
import time

PCAP_ERRBUF_SIZE = 256


class pcap_addr(ctypes.Structure):
    pass


pcap_addr._fields_ = [
    ("next", ctypes.POINTER(pcap_addr)),
    ("addr", ctypes.c_void_p),
    ("netmask", ctypes.c_void_p),
    ("broadaddr", ctypes.c_void_p),
    ("dstaddr", ctypes.c_void_p),
]


class pcap_if(ctypes.Structure):
    pass


pcap_if._fields_ = [
    ("next", ctypes.POINTER(pcap_if)),
    ("name", ctypes.c_char_p),
    ("description", ctypes.c_char_p),
    ("addresses", ctypes.POINTER(pcap_addr)),
    ("flags", ctypes.c_uint),
]


class timeval(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]


class pcap_pkthdr(ctypes.Structure):
    _fields_ = [("ts", timeval), ("caplen", ctypes.c_uint), ("len", ctypes.c_uint)]


class pcap_stat(ctypes.Structure):
    _fields_ = [("ps_recv", ctypes.c_uint),
                ("ps_drop", ctypes.c_uint),
                ("ps_ifdrop", ctypes.c_uint)]


class PcapError(Exception):
    pass


def _load_wpcap():
    for cand in (r"C:\Windows\System32\Npcap\wpcap.dll",
                 r"C:\Windows\System32\wpcap.dll",
                 r"C:\Windows\SysWOW64\Npcap\wpcap.dll"):
        if os.path.exists(cand):
            return ctypes.WinDLL(cand)
    found = ctypes.util.find_library("wpcap")
    if found:
        return ctypes.WinDLL(found)
    raise PcapError("wpcap.dll not found (Npcap runtime not installed?)")


def _devices(pcap):
    pcap.pcap_findalldevs.restype = ctypes.c_int
    pcap.pcap_findalldevs.argtypes = [ctypes.POINTER(ctypes.POINTER(pcap_if)),
                                      ctypes.c_char_p]
    pcap.pcap_freealldevs.restype = None
    pcap.pcap_freealldevs.argtypes = [ctypes.POINTER(pcap_if)]
    head = ctypes.POINTER(pcap_if)()
    err = ctypes.create_string_buffer(PCAP_ERRBUF_SIZE)
    if pcap.pcap_findalldevs(ctypes.byref(head), err) != 0:
        raise PcapError("pcap_findalldevs failed: %s" % err.value.decode("mbcs", "replace"))
    out = []
    node = head
    while node:
        rec = node.contents
        name = rec.name.decode("mbcs", "replace") if rec.name else ""
        desc = rec.description.decode("mbcs", "replace") if rec.description else ""
        out.append((name, desc, rec.flags))
        node = rec.next
    pcap.pcap_freealldevs(head)
    return out


def _pick(devs, want):
    """Exact GUID first, then unique substring on name/description. Never guess."""
    if want is None:
        for name, desc, flags in devs:
            if not (flags & 0x1):
                return name, desc
        raise PcapError("no non-loopback device available")
    hits = [(n, d) for n, d, _ in devs if n == want]
    if not hits:
        hits = [(n, d) for n, d, _ in devs
                if want.lower() in n.lower() or want.lower() in d.lower()]
    if len(hits) == 1:
        return hits[0]
    if not hits:
        raise PcapError("no device matches %r" % want)
    raise PcapError("%d devices match %r; be more specific" % (len(hits), want))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", default=None,
                    help="device GUID/name or description substring")
    ap.add_argument("--seconds", type=float, default=10.0)
    ap.add_argument("--out", default=None, help="output .pcap path")
    ap.add_argument("--promisc", action="store_true")
    ap.add_argument("--snaplen", type=int, default=65535)
    ap.add_argument("--list", action="store_true", help="list devices and exit")
    ap.add_argument("--dry-run", action="store_true", help="resolve device only")
    args = ap.parse_args(argv)

    try:
        pcap = _load_wpcap()
        devs = _devices(pcap)
    except PcapError as e:
        sys.stderr.write("ERR %s\n" % e)
        return 2

    if args.list:
        for name, desc, flags in devs:
            print("IFACE %s | %s%s" % (name, desc, " [loopback]" if flags & 0x1 else ""))
        return 0

    try:
        name, desc = _pick(devs, args.iface)
    except PcapError as e:
        sys.stderr.write("ERR %s\n" % e)
        return 2
    print("IFACE %s | %s" % (name, desc))
    if args.dry_run:
        print("DRY_RUN_OK iface=%s" % name)
        return 0

    if not args.out:
        sys.stderr.write("ERR --out is required unless --list/--dry-run\n")
        return 2
    outdir = os.path.dirname(os.path.abspath(args.out))
    if outdir and not os.path.isdir(outdir):
        os.makedirs(outdir, exist_ok=True)

    pcap.pcap_open_live.restype = ctypes.c_void_p
    pcap.pcap_open_live.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int,
                                    ctypes.c_int, ctypes.c_char_p]
    pcap.pcap_next_ex.restype = ctypes.c_int
    pcap.pcap_next_ex.argtypes = [ctypes.c_void_p,
                                  ctypes.POINTER(ctypes.POINTER(pcap_pkthdr)),
                                  ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte))]
    pcap.pcap_stats.restype = ctypes.c_int
    pcap.pcap_stats.argtypes = [ctypes.c_void_p, ctypes.POINTER(pcap_stat)]
    pcap.pcap_close.restype = None
    pcap.pcap_close.argtypes = [ctypes.c_void_p]
    pcap.pcap_geterr.restype = ctypes.c_char_p
    pcap.pcap_geterr.argtypes = [ctypes.c_void_p]

    err = ctypes.create_string_buffer(PCAP_ERRBUF_SIZE)
    h = pcap.pcap_open_live(name.encode("mbcs"), args.snaplen,
                            1 if args.promisc else 0, 200, err)
    if not h:
        sys.stdout.write("PCAP_STATS: rc=1 ps_recv=0 ps_drop=0 ps_ifdrop=0 err=open_failed\n")
        sys.stderr.write("ERR pcap_open_live: %s\n"
                         % err.value.decode("mbcs", "replace"))
        return 1

    print("CAPTURE_BEGIN %s seconds=%.1f promisc=%d out=%s"
          % (name, args.seconds, 1 if args.promisc else 0, args.out))

    try:
        fh = open(args.out, "wb")
    except OSError as e:
        pcap.pcap_close(h)
        sys.stdout.write("PCAP_STATS: rc=1 ps_recv=0 ps_drop=0 ps_ifdrop=0 err=open_out\n")
        sys.stderr.write("ERR cannot open %s: %s\n" % (args.out, e))
        return 1

    # classic pcap global header; Windows Npcap ethernet devices use linktype 1
    fh.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, args.snaplen, 1))
    fh.flush()

    hdr_p = ctypes.POINTER(pcap_pkthdr)()
    dat_p = ctypes.POINTER(ctypes.c_ubyte)()
    packets = 0
    t0 = time.time()
    deadline = t0 + args.seconds
    rc_stat = 0
    while time.time() < deadline:
        n = pcap.pcap_next_ex(h, ctypes.byref(hdr_p), ctypes.byref(dat_p))
        if n == 0:
            continue
        if n == 1:
            hdr = hdr_p.contents
            data = bytes(bytearray(dat_p[:hdr.caplen]))
            fh.write(struct.pack("<IIII", hdr.ts.tv_sec, hdr.ts.tv_usec,
                                 hdr.caplen, hdr.len))
            fh.write(data)
            packets += 1
        elif n == -2:
            break
        else:
            rc_stat = 2
            sys.stderr.write("ERR pcap_next_ex rc=%d: %s\n"
                             % (n, pcap.pcap_geterr(h).decode("mbcs", "replace")))
            break

    elapsed = time.time() - t0
    st = pcap_stat()
    stats_ok = pcap.pcap_stats(h, ctypes.byref(st)) == 0
    fh.flush()
    fh.close()
    pcap.pcap_close(h)

    if not stats_ok:
        sys.stdout.write("PCAP_STATS: rc=1 ps_recv=0 ps_drop=0 ps_ifdrop=0 "
                         "err=pcap_stats_failed\n")
        return 1
    print("PCAP_STATS: rc=%d ps_recv=%d ps_drop=%d ps_ifdrop=%d"
          % (rc_stat, st.ps_recv, st.ps_drop, st.ps_ifdrop))
    size = os.path.getsize(args.out)
    if rc_stat == 0 and size > 24:
        print("CAPTURE_OK %s bytes=%d packets=%d seconds=%.1f"
              % (args.out, size, packets, elapsed))
        return 0
    sys.stderr.write("ERR capture produced no usable output (size=%d)\n" % size)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
