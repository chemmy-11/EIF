#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
twin_recv.py — prj12 P1: PC2 侧抓包判据（pcap 离线解析 / dumpcap 现场抓包）

为什么不用 raw socket: Windows 上 raw socket 收不到"目的 MAC 不是本机"的帧，
而 P1 的验收现象正是「PC2 网口看到目的 = PC1 的帧」。所以走 pcap 文件：
  现场: dumpcap 抓 -> 本脚本解析； 离线: 直接喂现成 pcap。
支持 pcap(经典) 与 pcapng 两种容器（纯标准库解析）。

用法:
  py pc\\twin_recv.py --from-pcap out\\pc2.pcap --board-mac 00:11:22:33:44:55
  py pc\\twin_recv.py --live --iface "Ethernet" --seconds 20 --out out\\pc2.pcap
  py pc\\twin_recv.py --from-pcap out\\pc2.pcap --dry-run     # 只校验参数/文件

P2 多值判据（2026-11-08 增补，P0-2）:
  py pc\\twin_recv.py --from-pcap p2.pcap --scheme protocol --pair B ^
     --expect-dst-ip 192.168.50.2 --expect-dst-ip 192.168.50.1 --no-bcast
  * --board-mac 可重复（板卡 MAC 多值：P1 00:11:22:33:44:55 / P2 02:00:00:00:0A:01、0B:01）；
    不给时默认匹配「全部已知板卡 MAC」（P1+P2 protocol/handbook），并在 banner 里列出来；
  * --expect-dst-ip 可重复（本端 PC IP + 对端 PC IP 都算命中）；--expect-dst-mac 可重复；
  * --no-bcast：命中帧的 eth.dst 若是广播即 FAIL —— P2 新口径要求单播（P1 广播回声已废止）；
  * --port-direction 默认 any 保持不变。
  * 注意：MAC 一律按 **src** 判（P1 实测回声帧 dst=广播，src 才是板卡 MAC）。
"""
import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile

MAGIC = b"TWIN"


# ---------------------------------------------------------------- pcap readers
def read_pcap(path):
    """经典 pcap -> [(ts, frame_bytes)]"""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 24:
        raise ValueError("file too short for pcap header")
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
        raise ValueError(f"not a classic pcap (magic=0x{magic:08X})")
    linktype = struct.unpack(endian + "I", data[20:24])[0]
    if linktype != 1:
        raise ValueError(f"unsupported linktype {linktype} (expect 1=EN10MB)")
    off, out = 24, []
    while off + 16 <= len(data):
        ts_s, ts_u, caplen, _origlen = struct.unpack(endian + "IIII", data[off:off + 16])
        off += 16
        if off + caplen > len(data):
            break
        frame = data[off:off + caplen]
        off += caplen
        scale = 1e9 if nano else 1e6
        out.append((ts_s + ts_u / scale, frame))
    return out


def read_pcapng(path):
    """pcapng -> [(ts, frame_bytes)]（只解析 EPB/SPB 两类包块）"""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 12 or struct.unpack("<I", data[:4])[0] != 0x0A0D0D0A:
        raise ValueError("not a pcapng")
    endian = "<" if struct.unpack("<I", data[8:12])[0] == 0x1A2B3C4D else ">"
    out, off = [], 0
    while off + 8 <= len(data):
        btype, blen = struct.unpack(endian + "II", data[off:off + 8])
        if blen < 12 or off + blen > len(data):
            break
        body = data[off + 8: off + blen - 4]
        if btype == 6 and len(body) >= 20:      # Enhanced Packet Block
            _iid, ts_h, ts_l, caplen, _orig = struct.unpack(endian + "IIIII", body[:20])
            frame = body[20:20 + caplen]
            out.append(((ts_h << 32) | ts_l, frame))   # 单位由 IDB 决定，这里只用于排序
        elif btype == 3 and len(body) >= 4:     # Simple Packet Block
            _orig = struct.unpack(endian + "I", body[:4])[0]
            out.append((0.0, body[4:]))
        off += blen
    return out


def read_capture(path):
    with open(path, "rb") as f:
        first = f.read(4)
    if first == b"\x0a\x0d\x0d\x0a":
        return read_pcapng(path), "pcapng"
    return read_pcap(path), "pcap"


# ---------------------------------------------------------------- dissection
def parse_eth_ip_udp(frame):
    """返回 dict 或 None（非 IPv4/UDP 直接跳过）

    2026-10-29 加固（上板前）：
      * 支持 802.1Q VLAN 单标签（个位数 TCI），返回 vlan=1 —— 板卡不发光 VLAN，
        若抓到 VLAN 帧说明上游/网卡加了标签，要能识别而不是当噪声丢掉；
      * FCS 自动剥离：若帧长 == 14(+4) + IP total_len + 4，多出来的 4 字节按 FCS 处理
        （dumpcap 一般不给 FCS，但个别网卡/驱动会给）；
    """
    if len(frame) < 14:
        return None
    dst_mac = ":".join(f"{b:02x}" for b in frame[0:6])
    src_mac = ":".join(f"{b:02x}" for b in frame[6:12])
    etype = struct.unpack(">H", frame[12:14])[0]
    l3_off = 14
    vlan = 0
    if etype == 0x8100 and len(frame) >= 18:      # 802.1Q
        etype = struct.unpack(">H", frame[16:18])[0]
        l3_off = 18
        vlan = 1
    if etype != 0x0800:
        return {"etype": etype, "dst_mac": dst_mac, "src_mac": src_mac,
                "l3": None, "vlan": vlan}
    ip = frame[l3_off:]
    if len(ip) < 20:
        return None
    ihl = (ip[0] & 0x0F) * 4
    proto = ip[9]
    tot = struct.unpack(">H", ip[2:4])[0]
    # FCS 自动剥离（只在长度严格吻合 14+l3_off-14+tot+4 时）
    exp_no_fcs = l3_off + tot
    fcs_trimmed = 0
    if len(frame) == exp_no_fcs + 4:
        frame = frame[:-4]
        ip = frame[l3_off:]
        fcs_trimmed = 4
    src_ip = ".".join(str(b) for b in ip[12:16])
    dst_ip = ".".join(str(b) for b in ip[16:20])
    d = {"etype": etype, "dst_mac": dst_mac, "src_mac": src_mac,
         "src_ip": src_ip, "dst_ip": dst_ip, "proto": proto, "l3": None,
         "vlan": vlan, "fcs": fcs_trimmed}
    if proto != 17 or len(ip) < ihl + 8:
        return d
    udp = ip[ihl:]
    sport, dport, ulen = struct.unpack(">HHH", udp[:6])
    payload = udp[8:]
    if ulen >= 8:
        payload = payload[:max(0, min(len(payload), ulen - 8))]
    d["l3"] = {"sport": sport, "dport": dport, "ulen": ulen,
               "payload": payload, "ip_total_len": tot}
    return d


def looks_like_twin(payload):
    if len(payload) < 12 or payload[:4] != MAGIC:
        return None
    seq, total = struct.unpack(">HH", payload[4:8])
    run_id = struct.unpack(">I", payload[8:12])[0]
    fill = payload[12:]
    expect = bytes(((seq + i) & 0xFF) for i in range(12, 12 + len(fill)))
    return {"seq": seq, "total": total, "run_id": run_id,
            "fill_ok": fill == expect, "fill_bad_at": _first_diff(fill, expect)}


def _first_diff(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return -1 if len(a) == len(b) else min(len(a), len(b))


def main():
    ap = argparse.ArgumentParser(description="prj13 P2 capture judge (either PC side)")
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--from-pcap", help="离线解析现成 pcap/pcapng")
    src.add_argument("--live", action="store_true", help="调 dumpcap 现场抓包再解析")
    ap.add_argument("--iface", default=None, help="网卡名（--live 必填，dumpcap -i 的值）")
    ap.add_argument("--seconds", type=int, default=20, help="--live 抓包时长")
    ap.add_argument("--out", default=None, help="--live 的 pcap 输出路径")
    ap.add_argument("--scheme", choices=["handbook", "protocol", "p1"], default="handbook",
                    help="地址方案（默认 handbook = 2026-11-08 20:40 已裁决 10.10.0.x；"
                         "protocol = 历史 192.168.50.x；p1 = P1 基线位流，判 P1 抓包必须显式给）")
    ap.add_argument("--pair", choices=["A", "B"], default=None,
                    help="配合 --scheme：只认该板的 MAC；不给则 scheme 里两块板的 MAC 都认")
    ap.add_argument("--board-mac", action="append", default=None, metavar="MAC",
                    help="板卡 MAC（src 判据），可重复给多个，覆盖 --scheme 的默认集合")
    ap.add_argument("--expect-dst-ip", action="append", default=None, metavar="IP",
                    help="期望 IP 目的地址，可重复（本端 PC IP / 对端 PC IP 都可给）；不给=不判")
    ap.add_argument("--expect-dst-mac", action="append", default=None, metavar="MAC",
                    help="期望以太网目的 MAC，可重复；不给=不判（P1 实测回声帧 dst=广播）")
    ap.add_argument("--no-bcast", action="store_true",
                    help="命中帧 eth.dst 若是广播/组播即 FAIL —— P2 新口径要求单播目的 MAC")
    ap.add_argument("--port", type=int, default=1234, help="期望 UDP 端口（板卡回声的 1234；P2 业务 47001）")
    ap.add_argument("--port-direction", choices=["any", "sport", "dport"], default="any",
                    help="port 匹配方向：any=sport 或 dport 命中都算（默认；2026-11-06 实测板卡回声是 "
                         "sport=1234 / dport=PC 临时端口，只认 dport 会假阴性）")
    ap.add_argument("--expect-count", type=int, default=0, help="期望帧数（0=不判）")
    ap.add_argument("--expect-len", default="", help="期望 payload 长度白名单，逗号分隔（如 100 或 26,63,200）")
    ap.add_argument("--expect-run-id", default="", help="期望 run_id（可写 0x2；用于区分方向）")
    ap.add_argument("--allow-dup", action="store_true", help="允许重复 seq（默认重复即 FAIL）")
    ap.add_argument("--dry-run", action="store_true", help="只校验参数/文件")
    args = ap.parse_args()

    # ---- 板卡 MAC 判据集合（多值）
    KNOWN_BOARD_MACS = {
        "p1": {"A": ["00:11:22:33:44:55"], "B": ["00:11:22:33:44:55"]},
        "protocol": {"A": ["02:00:00:00:0a:01"], "B": ["02:00:00:00:0b:01"]},
        "handbook": {"A": ["02:00:00:00:0a:01"], "B": ["02:00:00:00:0b:01"]},
    }
    mac_source = "explicit --board-mac"
    if args.board_mac:
        mac_list = [m.lower().replace("-", ":") for m in args.board_mac]
    else:
        pairs = [args.pair] if args.pair else ["A", "B"]
        mac_list = []
        for p in pairs:
            mac_list += KNOWN_BOARD_MACS[args.scheme][p]
        mac_source = f"--scheme {args.scheme}" + (f" --pair {args.pair}" if args.pair else " (both pairs)")
    mac_set = set(mac_list)
    dst_ip_set = {ip for ip in (args.expect_dst_ip or [])}
    dst_mac_set = {m.lower().replace("-", ":") for m in (args.expect_dst_mac or [])}

    BITSTREAM_GUARD = {
        "handbook": "requires a P2 bitstream (RTL BOARD_IP 10.10.0.11/.12); a P1 bitstream only\n"
                    "           ever emits 00:11:22:33:44:55 -> use --scheme p1 for P1 captures",
        "protocol": "requires a P2 bitstream built with 192.168.50.x -- NOT the adjudicated plan\n"
                    "           any more; a P1 bitstream only ever emits 00:11:22:33:44:55",
        "p1": "P1 baseline bitstream (board mac 00:11:22:33:44:55, 192.168.1.0/24)",
    }

    print("=== twin_recv (prj13 P2) ===")
    print(f"scheme   : {args.scheme}" + (f" / pair {args.pair}" if args.pair else ""))
    print("note     : handbook is the ADJUDICATED plan (project owner 2026-11-08 20:40); "
          "protocol = historical; p1 = P1 baseline bitstream only")
    print(f"BITSTREAM: {BITSTREAM_GUARD[args.scheme]}")
    print(f"board-mac: {', '.join(sorted(mac_set))}   [{mac_source}]")
    print(f"dst-ip   : {', '.join(sorted(dst_ip_set)) if dst_ip_set else '(not judged)'}")
    print(f"dst-mac  : {', '.join(sorted(dst_mac_set)) if dst_mac_set else '(not judged)'}"
          f"  no-bcast={args.no_bcast}")
    print(f"port     : {args.port} ({args.port_direction})  expect-count={args.expect_count}")

    # ---------------- 参数自检（dry-run 在任何机器上都必须能过：无板、无网卡、无 pcap）
    if args.port < 0 or args.port > 65535:
        print(f"FAIL: --port {args.port} 超出 0..65535", file=sys.stderr)
        return 1
    if args.expect_count < 0:
        print(f"FAIL: --expect-count {args.expect_count} < 0", file=sys.stderr)
        return 1
    for m in list(mac_set) + list(dst_mac_set):
        try:
            if len(m.split(":")) != 6:
                raise ValueError
            bytes.fromhex(m.replace(":", ""))
        except ValueError:
            print(f"FAIL: bad MAC {m!r}（want AA:BB:CC:DD:EE:FF）", file=sys.stderr)
            return 1
    if args.expect_len:
        try:
            [int(x) for x in args.expect_len.split(",") if x.strip()]
        except ValueError:
            print(f"FAIL: --expect-len {args.expect_len!r} 不是逗号分隔的整数", file=sys.stderr)
            return 1
    if args.expect_run_id:
        try:
            int(args.expect_run_id, 0)
        except ValueError:
            print(f"FAIL: --expect-run-id {args.expect_run_id!r} 不是整数（可写 0x2）", file=sys.stderr)
            return 1

    if args.live:
        dumpcap = shutil.which("dumpcap")
        if not args.iface:
            print("FAIL: --live 需要 --iface（dumpcap -D 列网卡）", file=sys.stderr)
            return 1
        out = args.out or os.path.join(tempfile.gettempdir(), "twin_live.pcap")
        flt = " or ".join(f"(ether src {m})" for m in sorted(mac_set))
        if len(mac_set) > 1:
            flt = "(" + flt + ")"
        cmd = [dumpcap or "<dumpcap>", "-i", args.iface, "-a", f"duration:{args.seconds}",
               "-f", flt, "-w", out, "-q"]
        print("CMD:", " ".join(cmd))
        if args.dry_run:
            if not dumpcap:
                print("WARN: dumpcap 不在 PATH（真抓包前需装 Wireshark / 加 PATH）")
            print("DRY_RUN: 未抓包（参数校验通过）")
            return 0
        if not dumpcap:
            print("FAIL: dumpcap 不在 PATH（装 Wireshark 或把 dumpcap 目录加入 PATH）", file=sys.stderr)
            return 1
        rc = subprocess.call(cmd)
        if rc != 0 or not os.path.exists(out):
            print(f"FAIL: dumpcap rc={rc}", file=sys.stderr)
            return 1
        path = out
    else:
        path = args.from_pcap
        if not path:
            if args.dry_run:
                print("DRY_RUN: 无抓包源（没给 --from-pcap / --live）-> 仅参数校验通过")
                return 0
            print("FAIL: 需要 --from-pcap 或 --live", file=sys.stderr)
            return 1
        if not os.path.exists(path):
            if args.dry_run:
                print(f"WARN: file not found: {path}")
                print("DRY_RUN: 仅参数校验通过（文件缺失不影响参数自检）")
                return 0
            print(f"FAIL: file not found: {path}", file=sys.stderr)
            return 1
        if args.dry_run:
            print(f"DRY_RUN: 将解析 {path}（{os.path.getsize(path)} B），参数校验通过")
            return 0

    frames, kind = read_capture(path)
    print(f"capture: {path} ({kind}), frames={len(frames)}")

    target = ", ".join(sorted(mac_set))
    hits, other, bad, vlan_n, fcs_n = [], 0, 0, 0, 0
    other_mac, other_dst_ip, other_dst_mac, bcast_hits = 0, 0, 0, 0
    other_nonsense, port_miss = 0, 0
    for ts, fr in frames:
        d = parse_eth_ip_udp(fr)
        if not d:
            other += 1
            other_nonsense += 1
            continue
        vlan_n += d.get("vlan", 0)
        fcs_n += 1 if d.get("fcs") else 0
        if d["src_mac"].lower() not in mac_set:
            other += 1
            other_mac += 1
            continue
        if dst_ip_set and (d.get("dst_ip") or "").lower() not in dst_ip_set:
            other += 1
            other_dst_ip += 1
            continue
        if dst_mac_set and d["dst_mac"].lower() not in dst_mac_set:
            other += 1
            other_dst_mac += 1
            continue
        port_hit = False
        if d.get("l3"):
            sport, dport = d["l3"]["sport"], d["l3"]["dport"]
            if args.port_direction == "sport":
                port_hit = sport == args.port
            elif args.port_direction == "dport":
                port_hit = dport == args.port
            else:  # any
                port_hit = (sport == args.port) or (dport == args.port)
        if port_hit:
            info = looks_like_twin(d["l3"]["payload"])
            rec = {"ts": ts, "dst_mac": d["dst_mac"], "src_ip": d["src_ip"],
                   "dst_ip": d["dst_ip"], "sport": d["l3"]["sport"],
                   "dport": d["l3"]["dport"], "plen": len(d["l3"]["payload"]), "twin": info,
                   "vlan": d.get("vlan", 0)}
            hits.append(rec)
            if d["dst_mac"].lower() == "ff:ff:ff:ff:ff:ff" or (
                    int(d["dst_mac"][:2], 16) & 1):
                bcast_hits += 1
            if info and not info["fill_ok"]:
                bad += 1
        else:
            other += 1
            port_miss += 1

    hits.sort(key=lambda r: (r["twin"]["seq"] if r["twin"] else 1 << 16))
    seqs = [r["twin"]["seq"] for r in hits if r["twin"]]
    lens = sorted({r["plen"] for r in hits})
    print(f"matched: {len(hits)} frame(s) src in [{target}] port={args.port}({args.port_direction}); other={other}")
    if other:
        print(f"  other breakdown: not-a-frame/non-ipv4={other_nonsense} other-src-mac={other_mac}"
              f" dst-ip-miss={other_dst_ip} dst-mac-miss={other_dst_mac} port-miss={port_miss}")
    if lens:
        print(f"payload lens: {lens}")
    if seqs:
        dup = len(seqs) - len(set(seqs))
        print(f"seq: min={min(seqs)} max={max(seqs)} unique={len(set(seqs))} dup={dup}")
    for r in hits[:20]:
        t = r["twin"]
        tag = "TWIN" if t else "non-twin-payload"
        extra = ""
        if t:
            extra = f" seq={t['seq']}/{t['total']} run=0x{t['run_id']:08X} fill={'ok' if t['fill_ok'] else 'BAD@%d' % t['fill_bad_at']}"
        print(f"  t={r['ts']:.6f} dst={r['dst_mac']} {r['src_ip']}:{r['sport']}->{r['dst_ip']}:{r['dport']} len={r['plen']} [{tag}]{extra}")
    if len(hits) > 20:
        print(f"  ... ({len(hits) - 20} more)")

    ok = len(hits) > 0 and bad == 0
    if args.expect_count > 0:
        if len(hits) >= args.expect_count and len(set(seqs)) >= min(args.expect_count, len(seqs)):
            pass
        else:
            print(f"FAIL: expect >= {args.expect_count} frames, got {len(hits)} (unique seq={len(set(seqs))})")
            ok = False
    if bad:
        print(f"FAIL: {bad} frame(s) with corrupted fill pattern")
    # 重复帧：0 丢包的判据里，重复也是缺陷（除非显式允许）
    dup = len(seqs) - len(set(seqs)) if seqs else 0
    if dup and not args.allow_dup:
        print(f"FAIL: {dup} duplicate seq(s)（0 丢包场景不允许；确属预期请加 --allow-dup）")
        ok = False
    # 载荷长度白名单（抓到的帧长度必须与发送侧一致）
    if args.expect_len:
        want = {int(x) for x in args.expect_len.split(",") if x.strip()}
        got = {r["plen"] for r in hits}
        if not got.issubset(want):
            print(f"FAIL: payload len(s) {sorted(got - want)} not in expected {sorted(want)}")
            ok = False
        else:
            print(f"payload len(s) {sorted(got)} ⊆ expected {sorted(want)}: OK")
    if vlan_n:
        print(f"WARN: {vlan_n} frame(s) carry 802.1Q VLAN tag（板卡不发光 VLAN；已按 VLAN 解析）")
    if fcs_n:
        print(f"INFO: {fcs_n} frame(s) had trailing FCS, auto-trimmed")
    # 方向判别：run_id 必须与发送侧一致（PC1 发用 0x1、PC2 发用 0x2 的约定见执行单）
    if args.expect_run_id:
        want_rid = int(args.expect_run_id, 0)
        got_rids = sorted({r["twin"]["run_id"] for r in hits if r["twin"]})
        if got_rids != [want_rid]:
            print(f"FAIL: run_id(s) {[hex(x) for x in got_rids]} != expected {hex(want_rid)}")
            ok = False
        else:
            print(f"run_id: {hex(want_rid)} OK（方向判别通过）")
    # 目的 MAC 口径：P2 新口径要求单播（旧「回声 dst=广播」口径已废止）
    if args.no_bcast:
        if not hits:
            print("dst-mac: SKIP (--no-bcast but no matched frame; see the FAIL above)")
        elif bcast_hits:
            print(f"FAIL: {bcast_hits}/{len(hits)} matched frame(s) have broadcast/multicast eth.dst -- "
                  f"P2 requires unicast dst (the P1 broadcast echo shape is RETIRED)")
            ok = False
        else:
            print(f"dst-mac: {len(hits)}/{len(hits)} matched frame(s) unicast: OK (--no-bcast)")
    if dst_ip_set:
        if not hits:
            print(f"dst-ip coverage: SKIP (no matched frame); expected one of {sorted(dst_ip_set)}")
        else:
            got_ips = {r["dst_ip"] for r in hits}
            print(f"dst-ip coverage: {sorted(got_ips)} subset-of {sorted(dst_ip_set)}: "
                  f"{'OK' if got_ips <= dst_ip_set else 'MISMATCH'}")
    print("twin_recv: PASS" if ok else "twin_recv: FAIL")
    print("NOTE: 判据以 **src=板卡 MAC + payload TWIN 结构** 为准（P1 实测回声帧 dst=广播，src 才是板卡 MAC）。")
    print("      P1 口径：回声帧 dst 是 ff:ff:ff:ff:ff:ff 属预期，所以默认不判 dst_mac；")
    print("      P2 口径：必须是单播 dst=本端 PC MAC，请加 --no-bcast（或 --expect-dst-mac <本端 MAC>）作硬判据。")
    print("      端口方向：板卡回声是 sport=1234 / dport=PC 临时端口（默认 --port-direction any）。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
