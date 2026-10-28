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
    ap = argparse.ArgumentParser(description="prj12 P1 capture judge (PC2 side)")
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--from-pcap", help="离线解析现成 pcap/pcapng")
    src.add_argument("--live", action="store_true", help="调 dumpcap 现场抓包再解析")
    ap.add_argument("--iface", default=None, help="网卡名（--live 必填，dumpcap -i 的值）")
    ap.add_argument("--seconds", type=int, default=20, help="--live 抓包时长")
    ap.add_argument("--out", default=None, help="--live 的 pcap 输出路径")
    ap.add_argument("--board-mac", default="00:11:22:33:44:55", help="板卡 MAC（src 判据）")
    ap.add_argument("--port", type=int, default=1234, help="期望 UDP 端口")
    ap.add_argument("--expect-count", type=int, default=0, help="期望帧数（0=不判）")
    ap.add_argument("--expect-len", default="", help="期望 payload 长度白名单，逗号分隔（如 100 或 26,63,200）")
    ap.add_argument("--expect-run-id", default="", help="期望 run_id（可写 0x2；用于区分方向）")
    ap.add_argument("--allow-dup", action="store_true", help="允许重复 seq（默认重复即 FAIL）")
    ap.add_argument("--dry-run", action="store_true", help="只校验参数/文件")
    args = ap.parse_args()

    print("=== twin_recv ===")
    print(f"board-mac: {args.board_mac}  port={args.port}  expect-count={args.expect_count}")

    if args.live:
        dumpcap = shutil.which("dumpcap")
        if not dumpcap:
            print("FAIL: dumpcap 不在 PATH（装 Wireshark 或把 dumpcap 目录加入 PATH）", file=sys.stderr)
            return 1
        if not args.iface:
            print("FAIL: --live 需要 --iface（dumpcap -D 列网卡）", file=sys.stderr)
            return 1
        out = args.out or os.path.join(tempfile.gettempdir(), "twin_live.pcap")
        cmd = [dumpcap, "-i", args.iface, "-a", f"duration:{args.seconds}",
               "-f", f"ether src {args.board_mac}", "-w", out, "-q"]
        print("CMD:", " ".join(cmd))
        if args.dry_run:
            print("DRY_RUN: 未抓包")
            return 0
        rc = subprocess.call(cmd)
        if rc != 0 or not os.path.exists(out):
            print(f"FAIL: dumpcap rc={rc}", file=sys.stderr)
            return 1
        path = out
    else:
        path = args.from_pcap
        if not path:
            print("FAIL: 需要 --from-pcap 或 --live", file=sys.stderr)
            return 1
        if not os.path.exists(path):
            print(f"FAIL: file not found: {path}", file=sys.stderr)
            return 1
        if args.dry_run:
            print(f"DRY_RUN: 将解析 {path}（{os.path.getsize(path)} B）")
            return 0

    frames, kind = read_capture(path)
    print(f"capture: {path} ({kind}), frames={len(frames)}")

    target = args.board_mac.lower().replace("-", ":")
    hits, other, bad, vlan_n, fcs_n = [], 0, 0, 0, 0
    for ts, fr in frames:
        d = parse_eth_ip_udp(fr)
        if not d:
            other += 1
            continue
        vlan_n += d.get("vlan", 0)
        fcs_n += 1 if d.get("fcs") else 0
        if d["src_mac"].lower() != target:
            other += 1
            continue
        if d.get("l3") and d["l3"]["dport"] == args.port:
            info = looks_like_twin(d["l3"]["payload"])
            rec = {"ts": ts, "dst_mac": d["dst_mac"], "src_ip": d["src_ip"],
                   "dst_ip": d["dst_ip"], "sport": d["l3"]["sport"],
                   "dport": d["l3"]["dport"], "plen": len(d["l3"]["payload"]), "twin": info,
                   "vlan": d.get("vlan", 0)}
            hits.append(rec)
            if info and not info["fill_ok"]:
                bad += 1
        else:
            other += 1

    hits.sort(key=lambda r: (r["twin"]["seq"] if r["twin"] else 1 << 16))
    seqs = [r["twin"]["seq"] for r in hits if r["twin"]]
    lens = sorted({r["plen"] for r in hits})
    print(f"matched: {len(hits)} frame(s) src={target} dport={args.port}; other={other}")
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
    print(f"twin_recv: {'PASS' if ok else 'FAIL'}")
    print("NOTE: P1 判据只要求「PC2 网口能看到目的=PC1 的帧」；eth.dst 不是 PC2 = 预期，不是失败。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
