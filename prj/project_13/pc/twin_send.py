#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
twin_send.py — prj13 P2: PC-side UDP sender + 1 Gbps send-path benchmark.

Two jobs:
  1) traffic source for the twin-board relay (P1 echo / P2 transparent forward);
  2) `--bench`: frame-length vs fps vs Mbps table + 10 MiB time estimate.

Design constraints (unchanged from P1):
  * standard library only, plain UDP socket, no admin / no Npcap;
  * payload carries its own checkable structure (magic/seq/count/run_id/fill) so
    the peer side can judge bytes, not just frame counts;
  * --dry-run prints the plan AND the exact 42 B ethernet+IPv4+UDP header that
    would go on the wire, without sending anything (works with no board and no
    adapter bound).

payload layout (big endian):
   0..3   b"TWIN"
   4..5   seq (uint16)
   6..7   count (uint16)
   8..11  run_id (uint32)
   12..   fill[i] = (seq + i) & 0xFF
min 12 B; --len default 100.

ADDRESS SCHEMES (see docs/M1_P2 address+ARP plan v0.2, section 1-3):
  handbook : ADJUDICATED plan (project owner 2026-11-08 20:40)
             PC1 10.10.0.1 / PC2 10.10.0.2 / board A .11 / board B .12  [DEFAULT]
  protocol : historical protocol_v1.md 2.2 (192.168.50.x) -- no longer default,
             the deliverable repo gets synced at product stage
  p1       : P1 baseline bitstream only (192.168.1.10 / 00:11:22:33:44:55)
BITSTREAM GUARD: handbook/protocol need a P2 bitstream (RTL address params are
  hardcoded); against the current P1 bitstream those addresses silently drop.

usage:
  py pc\\twin_send.py --dry-run
  py pc\\twin_send.py --dry-run --pair B
  py pc\\twin_send.py --dry-run --scheme protocol          # historical .50.x
  py pc\\twin_send.py --dry-run --scheme p1               # P1 baseline bitstream
  py pc\\twin_send.py --dry-run --dst-ip 10.10.0.11 --dst-mac 02:00:00:00:0A:01 --src-mac A8-2B-DD-76-DF-A2
  py pc\\twin_send.py --dst-port 1234 --count 20 --len 100 --run-id 0x1 --interval-ms 20
  py pc\\twin_send.py --bench --bench-out out\\evidence_x\\bench.txt
"""
import argparse
import math
import socket
import struct
import sys
import time

MAGIC = b"TWIN"
MIN_LEN = 12
FRAME_OVERHEAD = 14 + 20 + 8          # eth + ipv4 + udp headers (no FCS)
FCS = 4
MIN_ETH_FRAME = 64                    # FCS included
GIGE_BPS = 1_000_000_000              # 1 GbE line rate
PREAMBLE_SFD_IFG = 8 + 12             # 7 preamble + 1 SFD + 12 IFG

# ----------------------------------------------------------------- address presets
# MACs are board identity, so protocol/handbook share them; p1 keeps the
# bitstream-hardcoded 00:11:22:33:44:55 (rtl/aurora_mem_bridge.v:98-101).
SCHEMES = {
    "handbook": {
        "_doc": "ADJUDICATED plan (project owner decision 2026-11-08 20:40): 10.10.0.11/.12 + PC 10.10.0.1/.2",
        "A": {"board_ip": "10.10.0.11", "board_mac": "02:00:00:00:0A:01",
              "pc_ip": "10.10.0.1", "peer_ip": "10.10.0.2", "peer_mac": "02:00:00:00:0B:01"},
        "B": {"board_ip": "10.10.0.12", "board_mac": "02:00:00:00:0B:01",
              "pc_ip": "10.10.0.2", "peer_ip": "10.10.0.1", "peer_mac": "02:00:00:00:0A:01"},
    },
    "protocol": {
        "_doc": "HISTORICAL protocol_v1.md 2.2 (192.168.50.x) -- no longer the default; deliverable repo syncs at product stage",
        "A": {"board_ip": "192.168.50.11", "board_mac": "02:00:00:00:0A:01",
              "pc_ip": "192.168.50.1", "peer_ip": "192.168.50.2", "peer_mac": "02:00:00:00:0B:01"},
        "B": {"board_ip": "192.168.50.12", "board_mac": "02:00:00:00:0B:01",
              "pc_ip": "192.168.50.2", "peer_ip": "192.168.50.1", "peer_mac": "02:00:00:00:0A:01"},
    },
    "p1": {
        "_doc": "P1 BASELINE BITSTREAM only (rtl hardcodes 192.168.1.10 / 00:11:22:33:44:55)",
        "A": {"board_ip": "192.168.1.10", "board_mac": "00:11:22:33:44:55",
              "pc_ip": "192.168.1.102", "peer_ip": "192.168.1.102", "peer_mac": "00:11:22:33:44:55"},
        "B": {"board_ip": "192.168.1.10", "board_mac": "00:11:22:33:44:55",
              "pc_ip": "192.168.1.102", "peer_ip": "192.168.1.102", "peer_mac": "00:11:22:33:44:55"},
    },
}

BITSTREAM_GUARD = {
    "handbook": "requires a P2 bitstream -- RTL BOARD_IP must be 10.10.0.11/.12 and PEER_IP 10.10.0.2/.1;\n"
                "           against a P1 bitstream (192.168.1.10) these addresses silently drop frames",
    "protocol": "requires a P2 bitstream built with 192.168.50.x -- NOT the adjudicated plan any more;\n"
                "           against a P1 bitstream (192.168.1.10) these addresses silently drop frames",
    "p1": "P1 baseline bitstream (192.168.1.10 / 00:11:22:33:44:55) -- use ONLY against the\n"
          "           currently burned P1 bitstream; a P2 bitstream does NOT answer on these addresses",
}

# fill pattern cache: fill[i] = (seq + i) & 0xFF  ->  rotated byte ramp.
_RAMP = bytes(range(256))


def build_payload(seq, total, run_id, length):
    """Byte-identical to the P1 reference below, much faster: measured 2026-11-08 on
    this host 0.49 us vs 3.42 us/frame at len=100, 0.82 us vs 53.88 us/frame at
    len=1472 (the P1 generator cost 53.9 us/frame -> capped 1472 B at ~18.5 kfps)."""
    if length < MIN_LEN:
        raise ValueError(f"--len must be >= {MIN_LEN}")
    head = MAGIC + seq.to_bytes(2, "big") + total.to_bytes(2, "big") + run_id.to_bytes(4, "big")
    n = length - MIN_LEN
    if n == 0:
        return head
    # body[k] must equal (seq + MIN_LEN + k) & 0xFF  (the P1 reference starts at
    # absolute payload offset MIN_LEN, i.e. i runs over range(MIN_LEN, length))
    off = (seq + MIN_LEN) & 0xFF
    rot = _RAMP[off:] + _RAMP[:off]
    body = (rot * (n // 256 + 1))[:n]
    return head + body


def _old_build_payload(seq, total, run_id, length):
    """P1 reference implementation, kept only for the self-check."""
    head = MAGIC + seq.to_bytes(2, "big") + total.to_bytes(2, "big") + run_id.to_bytes(4, "big")
    return head + bytes(((seq + i) & 0xFF) for i in range(MIN_LEN, length))


# ----------------------------------------------------------------- frame header
def parse_mac(text):
    """'AA:BB:CC:DD:EE:FF' / 'AA-BB-...' / 'AABB.CCDD.EEFF' -> 6 bytes, or None."""
    if not text:
        return None
    h = str(text).replace(":", "").replace("-", "").replace(".", "").replace(" ", "")
    if len(h) != 12:
        return None
    try:
        return bytes.fromhex(h)
    except ValueError:
        return None


def ip_bytes(text):
    p = str(text).split(".")
    if len(p) != 4:
        raise ValueError(f"bad IPv4 {text!r}")
    out = bytearray()
    for x in p:
        v = int(x)
        if not 0 <= v <= 255:
            raise ValueError(f"bad IPv4 {text!r}")
        out.append(v)
    return bytes(out)


def ip_checksum(hdr):
    s = 0
    for i in range(0, len(hdr), 2):
        s += (hdr[i] << 8) | (hdr[i + 1] if i + 1 < len(hdr) else 0)
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def build_frame_header(dst_mac, src_mac, src_ip, dst_ip, sport, dport, payload_len):
    """Return (42 B ethernet+ipv4+udp header, field dict). UDP checksum left 0 (kernel fills)."""
    eth = dst_mac + src_mac + struct.pack(">H", 0x0800)
    tot = 20 + 8 + payload_len
    ip = bytearray(20)
    ip[0] = 0x45
    ip[1] = 0x00
    struct.pack_into(">H", ip, 2, tot)
    struct.pack_into(">H", ip, 4, 0x0000)      # id: kernel picks the real value
    struct.pack_into(">H", ip, 6, 0x4000)      # DF
    ip[8] = 64                                 # ttl (kernel default 128 on Windows)
    ip[9] = 17                                 # udp
    ip[12:16] = src_ip
    ip[16:20] = dst_ip
    struct.pack_into(">H", ip, 10, ip_checksum(bytes(ip)))
    udp = struct.pack(">HHHH", sport, dport, 8 + payload_len, 0)
    hdr = eth + bytes(ip) + udp
    fields = {
        "ethertype": "0x0800",
        "ip_total_len": tot,
        "ip_id": "0x0000 (kernel chooses)",
        "ip_flags_frag": "0x4000 = DF, frag offset 0",
        "ip_ttl": 64,
        "ip_proto": "17/UDP",
        "ip_csum": "0x%04X (recomputed by the kernel in the real send)" % struct.unpack(">H", bytes(ip[10:12]))[0],
        "udp_len": 8 + payload_len,
        "udp_csum": "0x0000 = 'not computed' in the plan; the kernel fills the real value",
    }
    return hdr, fields


def hexdump(data, indent="   "):
    out = []
    for off in range(0, len(data), 16):
        chunk = data[off:off + 16]
        hexs = " ".join("%02x" % b for b in chunk)
        txt = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        out.append("%s%04x  %-47s  |%s|" % (indent, off, hexs, txt))
    return "\n".join(out)


def wire_bytes_for(payload_len):
    """Bytes on the wire per frame: preamble+SFD+frame(with FCS)+IFG."""
    frame = max(MIN_ETH_FRAME, FRAME_OVERHEAD + payload_len + FCS)
    return frame + PREAMBLE_SFD_IFG


def gige_theory(payload_len):
    """(fps, payload Mbps, line Mbps) at ideal 1 GbE, no other traffic."""
    wire = wire_bytes_for(payload_len)
    fps = GIGE_BPS / (8.0 * wire)
    frame = wire - PREAMBLE_SFD_IFG
    return fps, payload_len * 8 * fps / 1e6, frame * 8 * fps / 1e6


# ----------------------------------------------------------------- bench
def bench(args):
    lens = []
    for tok in str(args.bench_lens).split(","):
        tok = tok.strip()
        if tok:
            lens.append(int(tok))
    lens = [L for L in lens if L >= MIN_LEN]
    if not lens:
        print("FAIL: --bench-lens empty (need payload lengths >= %d)" % MIN_LEN, file=sys.stderr)
        return 1
    n = args.bench_count
    if n < 10:
        print("FAIL: --bench-count must be >= 10", file=sys.stderr)
        return 1

    target = None
    sink = None
    if args.bench_target == "loopback":
        sink = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sink.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
        except OSError:
            pass
        sink.bind(("127.0.0.1", 0))
        target = sink.getsockname()
    elif args.bench_target == "board":
        target = (args.dst_ip, args.dst_port)
    # 'none' -> construction only

    lines = []
    lines.append("=== twin_send --bench ===")
    lines.append("mode       : %s" % args.bench_target)
    lines.append("scheme/pair: %s / %s" % (args.scheme, args.pair))
    lines.append("bitstream  : %s" % BITSTREAM_GUARD[args.scheme].replace("\n           ", " "))
    if target:
        lines.append("target     : %s:%d/udp" % target)
    lines.append("frames/len : %d" % n)
    lines.append("interval   : 0 ms (bench never sleeps; --interval-ms is ignored here)")
    lines.append("")
    lines.append("EVIDENCE LEVEL: L1 (no board present; see AGENTS.md 6a -- this is NOT a board measurement)")
    lines.append("  * 'GbE theory' columns = ideal 1 Gbps linear model (preamble/SFD/IFG + min 64 B frame).")
    lines.append("  * 'socket path' columns = measured on THIS host: payload construction + sendto() syscall")
    lines.append("    (%s). Loopback is NOT a GbE wire; it only bounds the per-frame host overhead." % args.bench_target)
    lines.append("  * MUST be re-measured with `--bench --bench-target board` once the board is on line (that is L2/L3).")
    lines.append("")

    hdr = ["payload B", "frame B", "wire B", "GbE fps", "GbE Mbps(payload)", "GbE Mbps(line)",
           "construct us/frame", "loop us/frame", "socket fps", "socket Mbps(payload)"]
    rows = []
    measured = {}
    for L in lens:
        pkts = [build_payload(i & 0xFFFF, n, args.run_id, L) for i in range(n)]
        t0 = time.perf_counter()
        for i in range(n):
            pkts[i] = build_payload(i & 0xFFFF, n, args.run_id, L)
        t_cons = time.perf_counter() - t0

        sock = None
        t_loop = float("nan")
        if target is not None:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            t0 = time.perf_counter()
            try:
                for i in range(n):
                    sock.sendto(pkts[i], target)
            except OSError as e:
                lines.append("FAIL: sendto to %s:%d -> %s" % (target[0], target[1], e))
                if args.bench_target == "board":
                    lines.append("      (no board? use --bench-target loopback / none)")
                sock.close()
                if sink:
                    sink.close()
                print("\n".join(lines), file=sys.stderr)
                return 1
            t_loop = time.perf_counter() - t0
            sock.close()

        fps_t, mbps_t, line_t = gige_theory(L)
        wire = wire_bytes_for(L)
        frame = wire - PREAMBLE_SFD_IFG
        cons_us = t_cons / n * 1e6
        loop_us = t_loop / n * 1e6 if target is not None else float("nan")
        fps_s = n / t_loop if target is not None and t_loop > 0 else float("nan")
        mbps_s = n * L * 8 / t_loop / 1e6 if target is not None and t_loop > 0 else float("nan")
        measured[L] = (cons_us, loop_us, fps_s)
        rows.append((L, frame, wire, fps_t, mbps_t, line_t, cons_us, loop_us, fps_s, mbps_s))

    lines.append("| " + " | ".join(hdr) + " |")
    lines.append("|" + "|".join(["---"] * len(hdr)) + "|")
    for r in rows:
        cells = []
        for i, v in enumerate(r):
            if i in (0, 1, 2):
                cells.append("%d" % v)
            elif i in (3,):
                cells.append("%.1f" % v)
            elif i in (4, 5, 8, 9):
                cells.append("nan" if isinstance(v, float) and math.isnan(v) else "%.2f" % v)
            else:
                cells.append("nan" if isinstance(v, float) and math.isnan(v) else "%.3f" % v)
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")
    if 1472 in measured and not (isinstance(measured[1472][2], float) and math.isnan(measured[1472][2])):
        ratio = measured[1472][2] / gige_theory(1472)[0]
        lines.append("NOTE: 'socket Mbps(payload)' can exceed 1000 -- loopback bypasses the PHY, so that column")
        lines.append("      bounds HOST overhead only, never a wire rate. Compare fps instead: at 1472 B the")
        lines.append("      measured socket path is %.2fx the GbE frame budget (>1.0 = the host can saturate a" % ratio)
        lines.append("      real 1 GbE wire; <1.0 = the host itself is the bottleneck).")
        lines.append("")

    # ---- 10 MiB estimate (1472 B payload, the P2 bulk shape)
    total = 10 * 1024 * 1024
    bulk = 1472
    frames = int(math.ceil(total / float(bulk)))
    last = total - (frames - 1) * bulk
    fps_t, mbps_t, _line = gige_theory(bulk)
    opt_s = frames / fps_t
    cons_us = measured.get(bulk, (float("nan"), float("nan"), float("nan")))[1]
    if isinstance(cons_us, float) and not math.isnan(cons_us):
        per_frame = max(1.0 / fps_t, cons_us / 1e6)
    else:
        per_frame = 1.0 / fps_t
    cons_s = frames * per_frame * args.bench_margin

    lines.append("=== 10 MiB unidirectional estimate (1472 B payload, interval 0 ms) ===")
    lines.append("10 MiB                        : %d B" % total)
    lines.append("frames                        : %d  (ceil(%d/1472); last frame %d B)"
                 % (frames, total, last))
    lines.append("  NOTE startup manual 3/P0-3 writes 7125 frames; exact ceil is %d." % frames)
    lines.append("       %d x 1472 = %d B >= %d B, so %d frames already covers 10 MiB "
                 "(7125 also covers it with 1 spare frame)." % (frames, frames * bulk, total, frames))
    lines.append("optimistic  (GbE line rate)   : %.1f ms  = %.2f MiB/s  (%.0f Mbps payload)"
                 % (opt_s * 1e3, total / opt_s / (1024.0 * 1024), mbps_t))
    lines.append("conservative (x%.2f margin, host loop %s us/frame measured)"
                 % (args.bench_margin, "n/a" if isinstance(cons_us, float) and math.isnan(cons_us) else "%.3f" % cons_us))
    lines.append("                              : %.1f ms  = %.2f MiB/s"
                 % (cons_s * 1e3, total / cons_s / (1024.0 * 1024)))
    lines.append("")
    lines.append("CAVEATS (all L1):")
    lines.append("  * board RX -> Aurora -> peer board TX path is NOT in any number above;")
    lines.append("    P1 measured DMA per-frame soft-core writes bound the real rate (guide 6.1: route B ~23 Mbps).")
    lines.append("  * Windows socket buffer / firewall / offload can reduce the send-path fps;")
    lines.append("    the conservative column only covers host send overhead, not board back-pressure.")
    lines.append("  * a 1 GbE link cannot beat ~957 Mbps UDP goodput at 1472 B payload (%.0f fps)." % fps_t)

    text = "\n".join(lines)
    print(text)
    if args.bench_out:
        with open(args.bench_out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text + "\n")
        print("\nWROTE: %s" % args.bench_out)
    if sink:
        sink.close()
    return 0


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(
        description="prj13 P2 PC-side UDP sender + send-path benchmark",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="defaults are the adjudicated handbook shape (10.10.0.11 / 02:00:00:00:0A:01, project owner 2026-11-08 20:40).\n"
               "P1 baseline bitstream present? add --scheme p1 (192.168.1.10 / 00:11:22:33:44:55).")
    ap.add_argument("--scheme", choices=sorted(SCHEMES), default="handbook",
                    help="address scheme preset (default handbook = ADJUDICATED 2026-11-08 20:40; "
                         "protocol = historical .50.x; p1 = P1 baseline bitstream)")
    ap.add_argument("--pair", choices=["A", "B"], default="A",
                    help="which board/PC side this run belongs to (default A = PC1->board A)")
    ap.add_argument("--dst-ip", default=None, help="destination IP (default = preset board_ip)")
    ap.add_argument("--dst-port", type=int, default=1234,
                    help="destination UDP port (default 1234 = P1 board echo; P2 business port is 47001)")
    ap.add_argument("--src-ip", default=None,
                    help="bind source IP; default None = kernel routing decides. The header summary then "
                         "shows the preset pc_ip marked '(planned)'")
    ap.add_argument("--dst-mac", default=None, help="destination MAC for the header summary (default = preset board_mac)")
    ap.add_argument("--src-mac", default=None,
                    help="source MAC for the header summary (default = unknown; pass the PC NIC MAC, "
                         "e.g. from Get-NetAdapter)")
    ap.add_argument("--iface", default="", help="NIC name, informational only (kernel picks the route)")
    ap.add_argument("--count", type=int, default=20, help="frames to send (default 20)")
    ap.add_argument("--len", type=int, default=100, help="UDP payload bytes per frame (default 100, >= 12)")
    ap.add_argument("--run-id", type=lambda s: int(s, 0), default=0x00000001,
                    help="run id stamped into the payload (default 0x1; PC2->PC1 uses 0x2)")
    ap.add_argument("--interval-ms", type=float, default=20.0,
                    help="sleep between frames (default 20 ms; use 0 for the 10 MiB bulk run)")
    ap.add_argument("--dry-run", action="store_true", help="print plan + 42 B frame header, send nothing")
    ap.add_argument("--bench", action="store_true", help="run the send-path benchmark instead of sending")
    ap.add_argument("--bench-lens", default="64,128,256,512,1024,1472",
                    help="payload lengths for --bench (default 64,128,256,512,1024,1472)")
    ap.add_argument("--bench-count", type=int, default=2000, help="frames per length for --bench (default 2000)")
    ap.add_argument("--bench-target", choices=["loopback", "none", "board"], default="loopback",
                    help="--bench sink: loopback (default, measures construct+sendto), none (construct only), "
                         "board (real board; only with the board on line)")
    ap.add_argument("--bench-margin", type=float, default=1.20, help="safety factor for the conservative estimate")
    ap.add_argument("--bench-out", default=None, help="write the --bench markdown report to this path (UTF-8)")
    ap.add_argument("--selfcheck", action="store_true",
                    help="verify build_payload output is byte-identical to the P1 reference implementation")
    args = ap.parse_args()

    preset = SCHEMES[args.scheme][args.pair]
    dst_ip = args.dst_ip or preset["board_ip"]
    dst_mac_text = args.dst_mac or preset["board_mac"]
    src_ip_planned = preset["pc_ip"]

    # ---- parameter validation (no board, no adapter needed)
    if args.len < MIN_LEN:
        print("FAIL: --len %d < %d" % (args.len, MIN_LEN), file=sys.stderr)
        return 1
    if not (0 <= args.count <= 65535):
        print("FAIL: --count must be 0..65535", file=sys.stderr)
        return 1
    if not (0 <= args.run_id <= 0xFFFFFFFF):
        print("FAIL: --run-id must be 0..0xFFFFFFFF", file=sys.stderr)
        return 1
    if not (0 <= args.dst_port <= 65535):
        print("FAIL: --dst-port must be 0..65535", file=sys.stderr)
        return 1
    if args.len > 1472:
        print("WARN: --len %d > 1472 -> the IPv4 packet exceeds a 1500 B MTU and will fragment"
              % args.len, file=sys.stderr)
    try:
        ip_bytes(dst_ip)
    except ValueError as e:
        print("FAIL: %s" % e, file=sys.stderr)
        return 1
    dst_mac = parse_mac(dst_mac_text)
    if dst_mac is None:
        print("FAIL: bad --dst-mac %r (want AA:BB:CC:DD:EE:FF)" % dst_mac_text, file=sys.stderr)
        return 1
    src_mac = parse_mac(args.src_mac) if args.src_mac else None
    if args.src_mac and src_mac is None:
        print("FAIL: bad --src-mac %r (want AA:BB:CC:DD:EE:FF)" % args.src_mac, file=sys.stderr)
        return 1

    if args.selfcheck:
        bad = 0
        for L in (12, 13, 26, 64, 100, 255, 256, 512, 1472):
            for seq in (0, 1, 255, 256, 257, 4097):
                a = build_payload(seq, 20, 0xDEADBEEF, L)
                b = _old_build_payload(seq, 20, 0xDEADBEEF, L)
                if a != b:
                    bad += 1
                    print("MISMATCH len=%d seq=%d" % (L, seq))
        print("SELFCHECK: %s (%d case(s) mismatched)"
              % ("PASS" if bad == 0 else "FAIL", bad))
        if bad:
            return 1
        if not args.bench and not args.dry_run:
            return 0

    if args.bench:
        return bench(args)

    # ---- plan banner
    print("=== twin_send (prj13 P2) ===")
    print("scheme   : %s / pair %s" % (args.scheme, args.pair))
    print("  (%s)" % SCHEMES[args.scheme]["_doc"])
    print("note     : handbook is the ADJUDICATED plan (project owner 2026-11-08 20:40); "
          "protocol = historical; p1 = P1 baseline bitstream only")
    print("BITSTREAM: %s" % BITSTREAM_GUARD[args.scheme])
    print("dst      : %s:%d/udp" % (dst_ip, args.dst_port))
    print("src-ip   : %s" % (args.src_ip if args.src_ip else "%s (planned from scheme; NOT bound)" % src_ip_planned))
    print("iface    : %s" % (args.iface if args.iface else "(not given; kernel routing decides)"))
    print("count    : %d  len=%d  run_id=0x%08X  interval=%.1f ms"
          % (args.count, args.len, args.run_id, args.interval_ms))
    if args.scheme == "p1":
        print("NOTE     : scheme=p1 = P1 BASELINE BITSTREAM (192.168.1.10 / 00:11:22:33:44:55).")
        print("           P1 semantics: the echo frame leaves the PEER board's port, so this PC")
        print("           should NOT receive a reply. Cross-board ping is expected to FAIL in P1")
        print("           and only works in P2 (transparent forward).")
    else:
        print("NOTE     : scheme=%s needs a P2 bitstream; against the current P1 bitstream"
              % args.scheme)
        print("           the frames aimed at %s are silently dropped." % dst_ip)
    if dst_mac == b"\xff" * 6:
        print("WARN     : dst mac is broadcast -- the P1 broadcast-echo shape is RETIRED for P2;")
        print("           P2 frames must carry dst = the local board MAC.")

    # ---- frame header summary (always printed; this is the dry-run payload of evidence)
    sport = 40000  # planning placeholder: the kernel picks the real ephemeral source port
    hdr, fields = build_frame_header(
        dst_mac,
        src_mac if src_mac else b"\x00" * 6,
        ip_bytes(src_ip_planned),
        ip_bytes(dst_ip),
        sport, args.dst_port, args.len)
    print("---")
    print("planned on-wire header (%d B, payload %d B, frame %d B):"
          % (len(hdr), args.len, max(MIN_ETH_FRAME, FRAME_OVERHEAD + args.len + FCS)))
    print("  eth dst  : %s%s" % (dst_mac_text,
                                 "  (preset board mac)" if not args.dst_mac else ""))
    print("  eth src  : %s" % (args.src_mac if src_mac else "<unknown: pass --src-mac (shown as 00:00:00:00:00:00)>"))
    print("  ethertype: %s" % fields["ethertype"])
    print("  ip       : ver=4 ihl=5 total_len=%d id=%s flags=%s ttl=%d proto=%s csum=%s"
          % (fields["ip_total_len"], fields["ip_id"], fields["ip_flags_frag"],
             fields["ip_ttl"], fields["ip_proto"], fields["ip_csum"]))
    print("  ip src   : %s%s" % (src_ip_planned,
                                 "  (planned; the kernel fills the real source address)" if not args.src_ip else ""))
    print("  ip dst   : %s" % dst_ip)
    print("  udp      : sport=%d (placeholder) dport=%d len=%d csum=%s"
          % (sport, args.dst_port, fields["udp_len"], fields["udp_csum"]))
    print("  hexdump  :")
    print(hexdump(hdr))
    print("---")
    for seq in range(min(3, args.count)):
        p = build_payload(seq, args.count, args.run_id, args.len)
        print("  seq=%5d payload_len=%4d head=%s" % (seq, len(p), p[:24].hex()))

    if args.dry_run:
        print("---")
        print("DRY_RUN: nothing sent. Drop --dry-run to transmit.")
        print("         validated: scheme/pair, IPv4 literals, MAC literals, len/count/run_id/port bounds.")
        return 0

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.src_ip:
        sock.bind((args.src_ip, 0))
    sent = 0
    t0 = time.perf_counter()
    try:
        for seq in range(args.count):
            p = build_payload(seq, args.count, args.run_id, args.len)
            sock.sendto(p, (dst_ip, args.dst_port))
            sent += 1
            if args.interval_ms > 0:
                time.sleep(args.interval_ms / 1000.0)
    except OSError as e:
        print("FAIL: send error after %d frames: %s" % (sent, e), file=sys.stderr)
        print("HINT: in P1 the board ARP reply crosses the fiber, so this PC never gets it ->", file=sys.stderr)
        print("      bind a static ARP first:", file=sys.stderr)
        print("      powershell -NoProfile -ExecutionPolicy Bypass -File pc\\static_arp.ps1 "
              "-BoardPcPair %s -Scheme %s -Apply -IfAlias \"<nic name>\"" % (args.pair, args.scheme),
              file=sys.stderr)
        print("      in P2 a plain static ARP is still required (no proxy ARP by default).", file=sys.stderr)
        return 1
    finally:
        sock.close()
    dt = time.perf_counter() - t0
    print("SEND_OK: %d/%d frames to %s:%d in %.1f ms (%.0f fps, %.2f Mbps payload)"
          % (sent, args.count, dst_ip, args.dst_port, dt * 1e3,
             sent / dt if dt > 0 else 0.0, sent * args.len * 8 / dt / 1e6 if dt > 0 else 0.0))
    print("NOTE: P1 semantics = the echo leaves the PEER board's port, so this PC should not see a reply.")
    print("      P2 semantics = a frame to the peer PC IP is forwarded and MUST come back to the peer PC.")
    print("      Bench the send path (no board needed): py pc\\twin_send.py --bench")
    return 0


if __name__ == "__main__":
    sys.exit(main())
