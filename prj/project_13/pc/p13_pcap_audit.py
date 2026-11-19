#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""p13_pcap_audit.py — prj13 V4 字节级审计（classic pcap，无第三方依赖）

判据来源：issue #10 §6.8 + docs/M1_prj13_V4执行单_2026-11-19.md
  判据1 IP 包逐字节不变：每帧 cap == ip.len + 14（以太头 14 B）
  判据3 ARP 不跨板    ：窗口内 ARP 帧数必须为 0
  判据4 无乒乓        ：目的 IP 只能落在允许集合（本端 PC / 对端 PC），
                        出现 8.8.8.8 之类外部目的且被转出去 = 乒乓/泛洪

用法:
  py p13_pcap_audit.py --pcap x.pcap [--allow-dst 10.10.0.1 --allow-dst 10.10.0.2]
                       [--board-mac 02:00:00:00:0a:01] [--port 47001] [--json out.json]

输出人读摘要 + 可选 JSON；退出码 0=全通过 1=有违例 2=参数/读文件问题
"""
import argparse
import json
import struct
import sys

ETH_HDR = 14


def read_pcap(path):
    """返回 [(ts_sec, ts_usec, raw_frame_bytes)]；兼容 magic 0xa1b2c3d4/0xd4c3b2a1 与纳秒版。"""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 24:
        raise SystemExit("pcap too short: %d" % len(data))
    magic = data[:4]
    # 文件里的魔数字节序：a1b2c3d4 = 大端文件；d4c3b2a1 = 小端文件（npcap/Wireshark 在 x86 上写后者）
    if magic == b"\xa1\xb2\xc3\xd4":
        endian = ">"; nano = False
    elif magic == b"\xd4\xc3\xb2\xa1":
        endian = "<"; nano = False
    elif magic == b"\xa1\xb2\x3c\x4d":
        endian = ">"; nano = True
    elif magic == b"\x4d\x3c\xb2\xa1":
        endian = "<"; nano = True
    else:
        raise SystemExit("unsupported pcap magic: %s" % magic.hex())
    # global header already consumed by the 24-byte skip below
    off = 24
    out = []
    while off + 16 <= len(data):
        ts_sec, ts_frac, incl, orig = struct.unpack_from(endian + "IIII", data, off)
        off += 16
        if incl > len(data) - off:
            break
        out.append((ts_sec, ts_frac, data[off:off + incl]))
        off += incl
    return out, nano


def mac_s(b):
    return ":".join("%02x" % x for x in b)


def ip_s(b):
    return "%d.%d.%d.%d" % tuple(b)


def audit(frames, allowed_dst, board_mac, port, only_src=None):
    st = {
        "frames": len(frames),
        "skipped_other_src": 0,
        "ip": 0,
        "arp": 0,
        "other_l3": 0,
        "len_ok": 0,
        "len_bad": 0,
        "len_bad_samples": [],
        "udp_target_port": 0,
        "dst_ip_histogram": {},
        "dst_not_allowed": 0,
        "dst_not_allowed_samples": [],
        "src_mac_histogram": {},
    }
    for ts, fr, raw in frames:
        if len(raw) < ETH_HDR:
            st["other_l3"] += 1
            continue
        etype = struct.unpack_from(">H", raw, 12)[0]
        smac = mac_s(raw[6:12])
        st["src_mac_histogram"][smac] = st["src_mac_histogram"].get(smac, 0) + 1

        # 只审计指定源 MAC（收窄到"板卡发出的帧"）；环境中 mDNS/SSDP/广播不是被测对象
        if only_src and smac.lower() not in only_src:
            st["skipped_other_src"] += 1
            continue

        if etype == 0x0806:  # ARP
            st["arp"] += 1
            continue
        if etype != 0x0800:
            st["other_l3"] += 1
            continue

        st["ip"] += 1
        if len(raw) < ETH_HDR + 20:
            st["len_bad"] += 1
            if len(st["len_bad_samples"]) < 5:
                st["len_bad_samples"].append({"why": "truncated_ip", "cap": len(raw)})
            continue
        ip = raw[ETH_HDR:]
        ihl = (ip[0] & 0x0F) * 4
        total_len = struct.unpack_from(">H", ip, 2)[0]
        proto = ip[9]
        dst = ip_s(ip[16:20])
        st["dst_ip_histogram"][dst] = st["dst_ip_histogram"].get(dst, 0) + 1

        # 判据1：cap == ip.len + 14
        if len(raw) == total_len + ETH_HDR:
            st["len_ok"] += 1
        else:
            st["len_bad"] += 1
            if len(st["len_bad_samples"]) < 8:
                st["len_bad_samples"].append({
                    "why": "cap_ne_ip_len_plus_14",
                    "cap": len(raw), "ip_len": total_len,
                    "expect_cap": total_len + ETH_HDR, "delta": len(raw) - (total_len + ETH_HDR),
                    "dst": dst,
                })

        # UDP 目标端口
        if proto == 17 and len(ip) >= ihl + 8:
            dport = struct.unpack_from(">H", ip, ihl + 2)[0]
            if port and dport == port:
                st["udp_target_port"] += 1

        # 判据4：目的 IP 白名单
        if allowed_dst and dst not in allowed_dst:
            st["dst_not_allowed"] += 1
            if len(st["dst_not_allowed_samples"]) < 8:
                st["dst_not_allowed_samples"].append(dst)

    return st


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pcap", required=True)
    ap.add_argument("--allow-dst", action="append", default=[])
    ap.add_argument("--board-mac", default="")
    ap.add_argument("--src-mac", action="append", default=[],
                    help="只审计这些源 MAC（收窄到板卡发出的帧；环境流量不计入）")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--json", default="")
    a = ap.parse_args()

    frames, nano = read_pcap(a.pcap)
    only_src_check = bool(a.src_mac)
    st = audit(frames, set(a.allow_dst), a.board_mac.lower(), a.port, set(m.lower() for m in a.src_mac))
    st["pcap"] = a.pcap
    st["ts_unit"] = "ns" if nano else "us"
    if frames:
        st["first_ts"] = frames[0][0] + frames[0][1] / (1e9 if nano else 1e6)
        st["last_ts"] = frames[-1][0] + frames[-1][1] / (1e9 if nano else 1e6)
        st["duration_s"] = round(st["last_ts"] - st["first_ts"], 3)

    verdict = "PASS"
    reasons = []
    if st["frames"] == 0:
        verdict = "FAIL"; reasons.append("窗口内零帧")
    if only_src_check and (st["ip"] + st["arp"] + st["other_l3"]) == 0:
        verdict = "FAIL"; reasons.append("src-mac 收窄后零帧（MAC 选错，或该方向确实无流量）——不得据此判 PASS")
    if st["len_bad"] > 0:
        verdict = "FAIL"; reasons.append("判据1 违例 %d 帧（cap != ip.len+14）" % st["len_bad"])
    if st["arp"] > 0:
        verdict = "FAIL"; reasons.append("判据3 违例：窗口内出现 %d 个 ARP 帧（ARP 不得跨板）" % st["arp"])
    if a.allow_dst and st["dst_not_allowed"] > 0:
        verdict = "FAIL"; reasons.append("判据4 违例：%d 帧目的 IP 不在白名单" % st["dst_not_allowed"])
    st["verdict"] = verdict
    st["reasons"] = reasons

    print("=== p13_pcap_audit ===")
    print("pcap      :", a.pcap)
    print("frames    :", st["frames"], " duration_s:", st.get("duration_s"))
    print("ip/arp/l3 :", st["ip"], "/", st["arp"], "/", st["other_l3"])
    print("len_ok    :", st["len_ok"], "  len_bad:", st["len_bad"])
    if st["len_bad_samples"]:
        print("len_bad   :", json.dumps(st["len_bad_samples"], ensure_ascii=False))
    print("udp_port  :", a.port or "-", "hits:", st["udp_target_port"])
    print("dst_ip    :", json.dumps(st["dst_ip_histogram"], ensure_ascii=False, sort_keys=True))
    if a.allow_dst:
        print("dst_allow :", sorted(a.allow_dst), " violations:", st["dst_not_allowed"])
    print("src_mac   :", json.dumps(st["src_mac_histogram"], ensure_ascii=False, sort_keys=True))
    print("VERDICT   :", verdict, ("| " + "; ".join(reasons)) if reasons else "")
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False, indent=2)
        print("JSON      :", a.json)
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

