#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
p1_judge.py -- prj13 M1: multi-size matrix + 10 MiB one-way data-plane judge.

Why a second judge next to pc/twin_recv.py (prj12 P1):
  twin_recv.py answers "did the P1 echo show up at all" (>= N frames, any len).
  M1 needs the *strict* form:
      * --expect-len as a multi-value WHITELIST (26/64/100/512/1024/1472),
      * exact count + zero duplicate (10 MiB one-way: 1472 B x 7125 frames),
      * fill pattern byte-exact against twin_send.py's builder,
      * per-direction run_id,
      * throughput / elapsed summary from the pcap timestamps,
      * a stable one-line verdict tail that a shell script can grep:
            JUDGE: PASS key=...        /        JUDGE: FAIL key=...
  Parsing is hand-rolled on purpose (stdlib only, no scapy): Ethernet / IPv4 /
  UDP per RFC, single or double VLAN tag, optional trailing FCS, IPv4 fragment
  awareness.

Criteria alignment with prj12 P1 (see 操作文档/prj12_双板上板操作手册 §3/§4):
  * hit  = eth.src in --board-mac  AND  UDP port matches --port-direction/--port
  * eth.dst is IGNORED on purpose: with an empty board ARP table the echo frame
    degrades to Ethernet broadcast (dst=ff:ff:ff:ff:ff:ff); judging dst_mac
    would produce a false FAIL (2026-11-06 measured).
  * payload must be the twin_send.py structure, fill verified byte by byte:
        "TWIN" | seq(u16 BE) | count(u16 BE) | run_id(u32 BE) | fill[i]=(seq+12+i)&0xFF
  * direction is carried by run_id (PC1 sends 0x1, PC2 sends 0x2).

Usage:
  py scripts\\p1_judge.py --from-pcap out\\rx.pcap --expect-count 20 --expect-len 100 \\
      --expect-run-id 0x1 --board-mac 00:11:22:33:44:55 --port 1234 --allow-dup 0
  py scripts\\p1_judge.py --from-pcap out\\m10.pcap --expect-count 7125 \\
      --expect-len 1472 --expect-run-id 0x1 --allow-dup 0 --json-out out\\m10.json

Exit codes: 0 = JUDGE PASS, 1 = JUDGE FAIL, 2 = usage / file / format error.
All runtime stdout is ASCII on purpose (Windows console codepage safety).
"""

import argparse
import json
import re
import struct
import sys

MAGIC = b"TWIN"
MIN_LEN = 12
DEFAULT_BOARD_MAC = "00:11:22:33:44:55"
VLAN_TPIDS = (0x8100, 0x88A8, 0x9100)


# --------------------------------------------------------------------- pcap io
def read_pcap(path):
    """Classic pcap -> ([(ts_float, frame_bytes)], linktype)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 24:
        raise ValueError("file too short for a pcap header")
    magic = struct.unpack("<I", data[:4])[0]
    if magic == 0xA1B2C3D4:
        endian, nano = "<", False
    elif magic == 0xD4C3B2A1:
        endian, nano = ">", False
    elif magic == 0xA1B23C4D:
        endian, nano = "<", True
    elif magic == 0x4D3CB2A1:
        endian, nano = ">", True
    else:
        raise ValueError("not a classic pcap (magic=0x%08X)" % magic)
    linktype = struct.unpack(endian + "I", data[20:24])[0]
    if linktype != 1:
        raise ValueError("unsupported linktype %d (need 1 = EN10MB)" % linktype)
    scale = 1e9 if nano else 1e6
    off, out = 24, []
    while off + 16 <= len(data):
        ts_s, ts_u, caplen, _orig = struct.unpack(endian + "IIII", data[off:off + 16])
        off += 16
        if off + caplen > len(data):
            break
        out.append((ts_s + ts_u / scale, data[off:off + caplen]))
        off += caplen
    return out, linktype


def read_pcapng(path):
    """pcapng -> ([(ts_int, frame_bytes)], 1). Only EPB/SPB are decoded."""
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 12 or struct.unpack("<I", data[:4])[0] != 0x0A0D0D0A:
        raise ValueError("not a pcapng")
    endian = "<" if struct.unpack("<I", data[8:12])[0] == 0x1A2B3C4D else ">"
    out, off = [], 0
    while off + 8 <= len(data):
        btype, blen = struct.unpack(endian + "II", data[off:off + 8])
        if blen < 12 or off + blen > len(data):
            break
        body = data[off + 8:off + blen - 4]
        if btype == 6 and len(body) >= 20:            # Enhanced Packet Block
            _iid, ts_h, ts_l, caplen, _orig = struct.unpack(endian + "IIIII", body[:20])
            out.append((float((ts_h << 32) | ts_l), body[20:20 + caplen]))
        elif btype == 3 and len(body) >= 4:           # Simple Packet Block
            out.append((0.0, body[4:]))
        off += blen
    return out, 1


def read_capture(path):
    with open(path, "rb") as fh:
        first = fh.read(4)
    if first == b"\x0a\x0d\x0d\x0a":
        frames, linktype = read_pcapng(path)
        return frames, "pcapng", linktype
    frames, linktype = read_pcap(path)
    return frames, "pcap", linktype


# ------------------------------------------------------------------ dissection
def mac_str(b):
    return ":".join("%02x" % x for x in b)


def normalize_mac(text):
    t = (text or "").strip().lower().replace("-", ":").replace(".", ":")
    return t


def parse_frame(frame):
    """Ethernet/IPv4/UDP dissection. Always returns a dict (never None)."""
    d = {"flen": len(frame), "dst_mac": None, "src_mac": None, "etype": None,
         "vlan": 0, "fcs": 0, "frag": 0, "ip": None, "udp": None}
    if len(frame) < 14:
        return d
    d["dst_mac"] = mac_str(frame[0:6])
    d["src_mac"] = mac_str(frame[6:12])
    etype = struct.unpack(">H", frame[12:14])[0]
    l3 = 14
    while etype in VLAN_TPIDS and len(frame) >= l3 + 4:
        d["vlan"] += 1
        etype = struct.unpack(">H", frame[l3 + 2:l3 + 4])[0]
        l3 += 4
    d["etype"] = etype
    if etype != 0x0800 or len(frame) < l3 + 20:
        return d
    ip = frame[l3:]
    if (ip[0] >> 4) != 4:
        return d
    ihl = (ip[0] & 0x0F) * 4
    if ihl < 20 or len(ip) < ihl:
        return d
    tot = struct.unpack(">H", ip[2:4])[0]
    if len(frame) == l3 + tot + 4:                    # trailing FCS (4 B)
        frame = frame[:-4]
        ip = frame[l3:]
        d["fcs"] = 4
    if tot < ihl:
        return d
    frag = struct.unpack(">H", ip[6:8])[0]
    d["frag"] = frag & 0x1FFF                         # non-zero: not first fragment
    d["ip"] = {"src": ".".join(str(b) for b in ip[12:16]),
               "dst": ".".join(str(b) for b in ip[16:20]),
               "proto": ip[9], "tot": tot, "ihl": ihl, "ttl": ip[8],
               "mflag": bool(frag & 0x2000)}
    if ip[9] != 17 or d["frag"] != 0 or len(ip) < ihl + 8:
        return d
    udp = ip[ihl:]
    sport, dport, ulen = struct.unpack(">HHH", udp[:6])
    avail = len(udp) - 8
    declared = (ulen - 8) if ulen >= 8 else -1
    plen = avail if declared < 0 else max(0, min(avail, declared))
    d["udp"] = {"sport": sport, "dport": dport, "ulen": ulen,
                "payload": udp[8:8 + plen], "declared": declared,
                "truncated": (declared >= 0 and avail < declared)}
    return d


def check_twin(payload):
    """twin_send.py payload check. Returns None for a non-TWIN payload."""
    if len(payload) < MIN_LEN or payload[:4] != MAGIC:
        return None
    seq, total = struct.unpack(">HH", payload[4:8])
    run_id = struct.unpack(">I", payload[8:12])[0]
    fill = payload[MIN_LEN:]
    expect = bytes(((seq + i) & 0xFF) for i in range(MIN_LEN, MIN_LEN + len(fill)))
    fill_ok = (fill == expect)
    bad_at = -1
    if not fill_ok:
        for i, (x, y) in enumerate(zip(fill, expect)):
            if x != y:
                bad_at = i
                break
        if bad_at < 0:
            bad_at = min(len(fill), len(expect))
    return {"seq": seq, "total": total, "run_id": run_id,
            "fill_ok": fill_ok, "bad_at": bad_at, "plen": len(payload)}


# ----------------------------------------------------------------------- utils
def split_multi(values):
    """argparse append list -> flat list, splitting on , ; and whitespace."""
    out = []
    for v in values or []:
        for chunk in re.split(r"[,;\s]+", str(v)):
            chunk = chunk.strip()
            if chunk:
                out.append(chunk)
    return out


def seq_ranges(nums):
    """[0,1,2,5,7,8] -> '0-2,5,7-8' (bounded, never silently truncated)."""
    if not nums:
        return "none"
    nums = sorted(set(nums))
    parts, start, prev = [], nums[0], nums[0]
    for n in nums[1:]:
        if n == prev + 1:
            prev = n
            continue
        parts.append(str(start) if start == prev else "%d-%d" % (start, prev))
        start = prev = n
    parts.append(str(start) if start == prev else "%d-%d" % (start, prev))
    return ",".join(parts)


def fmt_hex(v):
    return "0x%x" % v


# ------------------------------------------------------------------------ main
def build_parser():
    ap = argparse.ArgumentParser(
        description="prj13 M1 data-plane judge (multi-size whitelist + 10 MiB zero-loss)")
    ap.add_argument("--from-pcap", dest="from_pcap", required=True,
                    help="classic pcap or pcapng captured on the receiving NIC")
    ap.add_argument("--board-mac", dest="board_mac", action="append", default=None,
                    help="board MAC as eth.src criterion (repeatable; default %s)"
                         % DEFAULT_BOARD_MAC)
    ap.add_argument("--port", type=int, default=1234, help="expected UDP port (default 1234)")
    ap.add_argument("--port-direction", dest="port_direction",
                    choices=["any", "sport", "dport"], default="any",
                    help="any = sport OR dport hits (P1 default: echo is sport=1234)")
    ap.add_argument("--expect-count", dest="expect_count", type=int, default=0,
                    help="expected matched frame count (0 = do not check)")
    ap.add_argument("--count-mode", dest="count_mode", choices=["exact", "min"],
                    default="exact",
                    help="exact = 0-loss/0-dup criterion (default); min = twin_recv '>=' legacy")
    ap.add_argument("--expect-len", dest="expect_len", action="append", default=None,
                    help="payload length WHITELIST, multi-value (e.g. 26,64,100 or 1472)")
    ap.add_argument("--len-mode", dest="len_mode", choices=["subset", "cover"],
                    default="subset",
                    help="subset = every observed len must be whitelisted (default); "
                         "cover = every whitelisted len must appear")
    ap.add_argument("--expect-run-id", dest="expect_run_id", action="append", default=None,
                    help="expected run_id (0x1 PC1->PC2, 0x2 PC2->PC1); alias --run-id")
    ap.add_argument("--run-id", dest="expect_run_id", action="append",
                    help=argparse.SUPPRESS)
    ap.add_argument("--allow-dup", dest="allow_dup", type=int, nargs="?", const=1, default=0,
                    help="how many duplicate seqs are tolerated (default 0 = none)")
    ap.add_argument("--no-check-total", dest="check_total", action="store_false", default=True,
                    help="do not require the payload 'count' field to equal --expect-count")
    ap.add_argument("--print-frames", dest="print_frames", type=int, default=20,
                    help="per-frame detail lines (default 20; 0 = every matched frame)")
    ap.add_argument("--json-out", dest="json_out", default="",
                    help="write a machine-readable verdict JSON here")
    return ap


def main(argv=None):
    ap = build_parser()
    args = ap.parse_args(argv)

    path = args.from_pcap
    print("=== p1_judge ===")
    print("capture  : %s" % path)

    try:
        frames, kind, linktype = read_capture(path)
    except (OSError, ValueError) as exc:
        print("FAIL: cannot read capture: %s" % exc, file=sys.stderr)
        print("JUDGE: FAIL key=capture=FAIL(unreadable)")
        return 2

    board = {normalize_mac(x) for x in split_multi(args.board_mac) if x} or {DEFAULT_BOARD_MAC}
    want_lens = sorted({int(x, 0) for x in split_multi(args.expect_len)})
    want_rids = sorted({int(x, 0) for x in split_multi(args.expect_run_id)})

    print("format   : %s linktype=%d frames=%d" % (kind, linktype, len(frames)))
    print("filters  : board-mac=%s port=%d(%s) count=%s expect-len=%s%s runid=%s allow-dup=%d"
          % (",".join(sorted(board)), args.port, args.port_direction,
             ("%d/%s" % (args.expect_count, args.count_mode)) if args.expect_count > 0 else "off",
             ",".join(str(x) for x in want_lens) if want_lens else "off",
             ("/%s" % args.len_mode) if want_lens else "",
             ",".join(fmt_hex(x) for x in want_rids) if want_rids else "off",
             args.allow_dup))

    # ---- filter + dissect -------------------------------------------------
    matched = []
    other = nonudp = nonip = vlan_n = fcs_n = other_mac = 0
    for ts, fr in frames:
        d = parse_frame(fr)
        vlan_n += 1 if d["vlan"] else 0
        fcs_n += 1 if d["fcs"] else 0
        if d["src_mac"] is None:
            other += 1
            continue
        if d["src_mac"] not in board:
            other_mac += 1
            other += 1
            continue
        if d["ip"] is None:
            nonip += 1
            other += 1
            continue
        if d["udp"] is None:
            nonudp += 1
            other += 1
            continue
        sport, dport = d["udp"]["sport"], d["udp"]["dport"]
        if args.port_direction == "sport":
            port_hit = (sport == args.port)
        elif args.port_direction == "dport":
            port_hit = (dport == args.port)
        else:
            port_hit = (sport == args.port) or (dport == args.port)
        if not port_hit:
            other += 1
            continue
        payload = d["udp"]["payload"]
        info = check_twin(payload)
        matched.append({"ts": ts, "dst_mac": d["dst_mac"], "src_mac": d["src_mac"],
                        "src_ip": d["ip"]["src"], "dst_ip": d["ip"]["dst"],
                        "sport": sport, "dport": dport,
                        "plen": len(payload), "declared": d["udp"]["declared"],
                        "trunc": d["udp"]["truncated"], "vlan": d["vlan"],
                        "fcs": d["fcs"], "flen": d["flen"], "twin": info})

    twin_hits = [m for m in matched if m["twin"]]
    nontwin = len(matched) - len(twin_hits)
    print("matched  : %d frame(s) src=%s port=%d(%s); other=%d (other-mac=%d non-ip=%d non-udp=%d)"
          % (len(matched), ",".join(sorted(board)), args.port, args.port_direction,
             other, other_mac, nonip, nonudp))
    if vlan_n:
        print("           vlan-tagged=%d (parsed as 802.1Q; the board emits untagged)" % vlan_n)
    if fcs_n:
        print("           trailing-FCS trimmed on %d frame(s)" % fcs_n)

    lens = sorted({m["plen"] for m in twin_hits})
    if lens:
        print("payload  : lens=%s (declared/truncated mismatches: %d)"
              % (lens, len([m for m in twin_hits if m["trunc"]])))
    seqs = [m["twin"]["seq"] for m in twin_hits]
    uniq = sorted(set(seqs))
    dup = len(seqs) - len(uniq)
    if seqs:
        print("seq      : min=%d max=%d unique=%d dup=%d"
              % (min(seqs), max(seqs), len(uniq), dup))
    totals = sorted({m["twin"]["total"] for m in twin_hits})
    if totals:
        print("total    : count-field=%s" % totals)
    rids = sorted({m["twin"]["run_id"] for m in twin_hits})
    if rids:
        print("runid    : seen=%s" % ",".join(fmt_hex(x) for x in rids))

    bad_fill = [m for m in twin_hits if not m["twin"]["fill_ok"]]
    if twin_hits:
        if bad_fill:
            first = bad_fill[0]
            print("fill     : BAD on %d/%d frame(s); first seq=%d bad_at=fill[%d]"
                  % (len(bad_fill), len(twin_hits), first["twin"]["seq"],
                     first["twin"]["bad_at"]))
        else:
            print("fill     : ok (%d/%d frames byte-exact vs twin_send pattern)"
                  % (len(twin_hits), len(twin_hits)))
    if nontwin:
        print("payload  : %d matched frame(s) do not carry the TWIN structure" % nontwin)

    # ---- expected sequence / loss map -------------------------------------
    expected_total = args.expect_count if args.expect_count > 0 else (totals[0] if len(totals) == 1 else 0)
    if expected_total > 0:
        missing = sorted(set(range(expected_total)) - set(uniq))
        print("missing  : %d seq(s) never seen%s"
              % (len(missing), ("" if not missing else " -> " + seq_ranges(missing))))
        extra = sorted(set(uniq) - set(range(expected_total)))
        if extra:
            print("extra    : %d seq(s) outside 0..%d -> %s"
                  % (len(extra), expected_total - 1, seq_ranges(extra)))

    # ---- throughput / elapsed (from capture timestamps) --------------------
    tp = {}
    if twin_hits:
        ordered = sorted(twin_hits, key=lambda m: m["ts"])
        span = ordered[-1]["ts"] - ordered[0]["ts"]
        payload_bytes = sum(m["plen"] for m in ordered)
        wire_bytes = sum(m["flen"] for m in ordered)
        n = len(ordered)
        tp = {"frames": n, "payload_bytes": payload_bytes, "wire_bytes": wire_bytes,
              "span_s": span}
        if span > 0:
            tp["fps"] = (n - 1) / span if n > 1 else 0.0
            tp["mbps_payload"] = payload_bytes * 8.0 / span / 1e6
            tp["mbps_wire"] = wire_bytes * 8.0 / span / 1e6
            print("throughput: frames=%d payload=%d B wire=%d B span=%.6f s "
                  "fps=%.2f mbps_payload=%.3f mbps_wire=%.3f"
                  % (n, payload_bytes, wire_bytes, span, tp["fps"],
                     tp["mbps_payload"], tp["mbps_wire"]))
        else:
            print("throughput: frames=%d payload=%d B wire=%d B span=0 s "
                  "(timestamps tied; rate not computable)" % (n, payload_bytes, wire_bytes))
        tp["mib_payload"] = payload_bytes / (1024.0 * 1024.0)

    # ---- per-frame detail (head + tail, never silently dropped) -----------
    if matched:
        limit = args.print_frames if args.print_frames > 0 else len(matched)
        head = matched[:limit]
        tail = []
        if len(matched) > limit + 5:
            tail = matched[-5:]
        for m in head:
            _print_frame(m)
        if tail:
            print("  ... %d frame(s) not printed one by one (--print-frames 0 to list all)"
                  % (len(matched) - limit - len(tail)))
            for m in tail:
                _print_frame(m)

    # ---- checks -----------------------------------------------------------
    checks = []

    def add(name, ok, text):
        checks.append({"name": name, "ok": bool(ok), "text": text})

    add("frames", True, str(len(matched)))
    if args.expect_count > 0:
        if args.count_mode == "exact":
            add("count", len(matched) == args.expect_count,
                "FAIL(%d!=%d)" % (len(matched), args.expect_count)
                if len(matched) != args.expect_count else "exact(%d)" % args.expect_count)
        else:
            add("count", len(matched) >= args.expect_count,
                "FAIL(%d<%d)" % (len(matched), args.expect_count)
                if len(matched) < args.expect_count else "min(%d,%d)" % (len(matched), args.expect_count))
    else:
        add("count", True, "skip")
    add("unique", len(uniq) > 0, str(len(uniq)) if uniq else "FAIL(0)")
    add("dup", dup <= args.allow_dup,
        "FAIL(%d>%d)" % (dup, args.allow_dup) if dup > args.allow_dup else str(dup))
    add("fill", len(bad_fill) == 0,
        "FAIL(%d bad)" % len(bad_fill) if bad_fill else ("ok" if twin_hits else "FAIL(0 frames)"))
    if want_lens:
        if not lens:
            add("len", False, "FAIL(no payload)")
        elif args.len_mode == "cover":
            missing_len = [x for x in want_lens if x not in lens]
            add("len", not missing_len,
                "FAIL(missing %s)" % missing_len if missing_len
                else "cover(%s)" % ",".join(str(x) for x in sorted(lens)))
        else:
            bad_len = [x for x in lens if x not in want_lens]
            add("len", not bad_len,
                "FAIL(%s not in %s)" % (bad_len, want_lens) if bad_len
                else (str(lens[0]) if len(lens) == 1 else "subset(%s)" % ",".join(str(x) for x in lens)))
    else:
        add("len", True, "skip")
    if want_rids:
        bad_rid = [x for x in rids if x not in want_rids]
        add("runid", (len(rids) > 0) and not bad_rid,
            "FAIL(%s != %s)" % ([fmt_hex(x) for x in rids], [fmt_hex(x) for x in want_rids])
            if (bad_rid or not rids) else ",".join(fmt_hex(x) for x in rids))
    else:
        add("runid", True, "skip")
    if args.expect_count > 0 and args.check_total and totals:
        add("total", totals == [args.expect_count],
            "FAIL(%s!=%d)" % (totals, args.expect_count) if totals != [args.expect_count]
            else str(args.expect_count))
    add("payload", nontwin == 0,
        "FAIL(%d non-twin)" % nontwin if nontwin else ("ok" if twin_hits else "FAIL(0 frames)"))
    if expected_total > 0:
        miss = sorted(set(range(expected_total)) - set(uniq))
        add("loss", len(miss) == 0, "FAIL(%d missing)" % len(miss) if miss else "0")
    else:
        add("loss", True, "skip")

    ok = all(c["ok"] for c in checks)
    key = " ".join("%s=%s" % (c["name"], c["text"]) for c in checks)
    verdict = "PASS" if ok else "FAIL"

    for c in checks:
        if not c["ok"]:
            print("CHECK-FAIL: %s=%s" % (c["name"], c["text"]))
    print("JUDGE: %s key=%s" % (verdict, key))

    if args.json_out:
        summary = {"capture": path, "format": kind, "linktype": linktype,
                   "verdict": verdict, "checks": checks,
                   "filters": {"board_mac": sorted(board), "port": args.port,
                               "port_direction": args.port_direction,
                               "expect_count": args.expect_count,
                               "count_mode": args.count_mode,
                               "expect_len": want_lens, "len_mode": args.len_mode,
                               "expect_run_id": [fmt_hex(x) for x in want_rids],
                               "allow_dup": args.allow_dup},
                   "stats": {"capture_frames": len(frames), "matched": len(matched),
                             "unique_seq": len(uniq), "dup": dup,
                             "nontwin": nontwin, "other": other,
                             "vlan_tagged": vlan_n, "fcs_trimmed": fcs_n,
                             "lens": lens},
                   "throughput": tp}
        try:
            with open(args.json_out, "w", encoding="utf-8") as fh:
                json.dump(summary, fh, indent=2, sort_keys=True)
            print("JSON_OUT: %s" % args.json_out)
        except OSError as exc:
            print("WARN: cannot write --json-out: %s" % exc, file=sys.stderr)

    print("NOTE: eth.dst is deliberately NOT judged (P1 echo frames may degrade to "
          "Ethernet broadcast when the board ARP table is empty).")
    return 0 if ok else 1


def _print_frame(m):
    t = m["twin"]
    if t:
        extra = " seq=%d/%d run=%s fill=%s" % (
            t["seq"], t["total"], fmt_hex(t["run_id"]),
            "ok" if t["fill_ok"] else "BAD@%d" % t["bad_at"])
    else:
        extra = " non-twin-payload"
    print("  t=%.6f %s:%d -> %s:%d len=%d flen=%d dst=%s%s%s"
          % (m["ts"], m["src_ip"], m["sport"], m["dst_ip"], m["dport"],
             m["plen"], m["flen"], m["dst_mac"],
             (" vlan" if m["vlan"] else ""), extra))


if __name__ == "__main__":
    sys.exit(main())
