#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""m1a_rejudge.py -- prj12 M1-A: 按 run_id 分组重判**已有 pcap**（不需要重开窗口）

为什么需要它（2026-11-12 实测，两个窗口的 0/13 全是假 FAIL）：
    `twin_recv.py` 的假设是"一个 pcap 只装一次发送"，它把所有 src=板卡 MAC 的帧算进同一个
    `hits`，再拿这一坨去比 `--expect-count/--expect-len/--expect-run-id`。
    而 `m1a_sweep.py` 的协议是"一个 600 s 连续抓包装 13 次发送（13 个 run_id）"，
    于是每一类都被其他 12 类污染 → 13 项必然全 FAIL。判据日志原文：
        matched: 8835 frame(s) ... payload lens: [26, 64, 100, 512, 1024, 1200, 1472]
        FAIL: run_id(s) [...] != expected 0x203
        FAIL: payload len(s) [...] not in expected [100]
    本脚本先按 run_id **分组**，再逐项判，语义与 sweep 协议一致。

用法:
    py pc\\m1a_rejudge.py --from-pcap out\\...\\m1a_pc1_*.pcap --expect-base 0x200
    py pc\\m1a_rejudge.py --from-pcap ... --expect-base 0x100 --verbose
    py pc\\m1a_rejudge.py --from-pcap ... --expect-base 0x200 --json out\\judge\\m1a_pc1_rejudge.json

判定（每项，四个条件全满足才 PASS）:
    count   >= 期望帧数（默认要求 == ，用 --allow-missing 才放宽为 >=1）
    unique  == 收到的帧数里的唯一 seq 数，且 dup == 0
    fill    全部 ok
    len     该 run_id 下所有帧的 payload 长度 == 期望长度
退出码: 0 = 全部 PASS；1 = 有 FAIL
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twin_recv as T  # 复用 pcap 解析 / TWIN 解包，避免两份实现

# 与 m1a_sweep.build_plan 一致的计划（偏移 -> (label, len, count)）
PLAN = [
    (0x01, "size26",    26,   20),
    (0x02, "size64",    64,   20),
    (0x03, "size100",   100,  20),
    (0x04, "size512",   512,  20),
    (0x05, "size1024",  1024, 20),
    (0x06, "size1472",  1472, 20),
    (0xF1, "bidir1472", 1472, 20),
    (0x11, "round1",    100,  20),
    (0x12, "round2",    100,  20),
    (0x13, "round3",    100,  20),
    (0x14, "round4",    100,  20),
    (0x15, "round5",    100,  20),
    (0xA0, "big10MiB",  1200, 8739),
]


def main():
    ap = argparse.ArgumentParser(description="prj12 M1-A per-run_id re-judge (offline)")
    ap.add_argument("--from-pcap", required=True)
    ap.add_argument("--board-mac", default="00:11:22:33:44:55")
    ap.add_argument("--port", type=int, default=1234)
    ap.add_argument("--expect-base", type=lambda s: int(s, 0), required=True)
    ap.add_argument("--allow-missing", action="store_true", help="只要求至少 1 帧（默认要求足数）")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--json", default=None)
    args = ap.parse_args()

    if not os.path.exists(args.from_pcap):
        print("FAIL: file not found: %s" % args.from_pcap, file=sys.stderr)
        return 1

    frames, kind = T.read_capture(args.from_pcap)
    target = args.board_mac.lower().replace("-", ":")

    groups = {}          # run_id -> list of (seq, plen, frame_len, ip_total, fill_ok)
    other_src = 0
    for _ts, fr in frames:
        d = T.parse_eth_ip_udp(fr)
        if not d or d["src_mac"].lower() != target:
            other_src += 1
            continue
        if not d.get("l3"):
            continue
        sport, dport = d["l3"]["sport"], d["l3"]["dport"]
        if not (sport == args.port or dport == args.port):
            continue
        info = T.looks_like_twin(d["l3"]["payload"])
        if not info:
            continue
        groups.setdefault(info["run_id"], []).append(
            (info["seq"], len(d["l3"]["payload"]), len(fr), d["l3"]["ip_total_len"], info["fill_ok"]))

    total = sum(len(v) for v in groups.values())
    print("=== m1a_rejudge ===")
    print("pcap      : %s (%s) frames=%d" % (args.from_pcap, kind, len(frames)))
    print("board-mac : %s  port=%d (any)  expect-base=0x%X" % (target, args.port, args.expect_base))
    print("matched   : %d TWIN frames over %d run_id(s); non-board/other=%d" %
          (total, len(groups), other_src))
    print("")

    hdr = "%-10s %-7s %5s %5s %5s %5s  %-22s %s" % (
        "item", "run_id", "want", "got", "uniq", "dup", "payload_len(want=got)", "verdict")
    print(hdr)
    print("-" * len(hdr))

    results = []
    passed = 0
    for off, label, want_len, want_cnt in PLAN:
        rid = args.expect_base + off
        v = groups.get(rid, [])
        seqs = [x[0] for x in v]
        uniq = len(set(seqs))
        dup = len(seqs) - uniq
        lens = sorted({x[1] for x in v})
        fill_bad = sum(1 for x in v if not x[4])
        # 传输链完整性：帧长应 == 14 + ip_total（少字节 = 线上截断）
        trunc = sum(1 for x in v if x[2] < 14 + x[3])

        ok = True
        why = []
        if args.allow_missing:
            if len(v) < 1:
                ok = False; why.append("no-frame")
        elif len(v) < want_cnt:
            ok = False; why.append("short %d/%d" % (len(v), want_cnt))
        if dup:
            ok = False; why.append("dup=%d" % dup)
        if fill_bad:
            ok = False; why.append("fill_bad=%d" % fill_bad)
        if lens != [want_len]:
            ok = False; why.append("len=%s" % (lens if lens else "none"))
        if trunc:
            ok = False; why.append("truncated=%d" % trunc)

        verdict = "PASS" if ok else ("FAIL:" + ",".join(why))
        print("%-10s 0x%03X %5d %5d %5d %5d  %-22s %s" % (
            label, rid, want_cnt, len(v), uniq, dup,
            ("%d -> %s" % (want_len, lens if lens else "none")), verdict))
        if args.verbose and v:
            print("             frame_len=%s ip_total=%s" % (
                sorted({x[2] for x in v}), sorted({x[3] for x in v})))
        results.append(dict(item=label, run_id=rid, want=want_cnt, got=len(v), unique=uniq,
                            dup=dup, want_len=want_len, got_len=lens, fill_bad=fill_bad,
                            truncated=trunc, verdict=verdict))
        if ok:
            passed += 1

    extra = sorted(set(groups) - {args.expect_base + o for o, _l, _n, _c in PLAN})
    if extra:
        print("\nNOTE: 计划外的 run_id（可能是另一轮/另一方向）：%s" % [hex(x) for x in extra])

    print("")
    print("M1A_REJUDGE_RESULT: %d/%d PASS  (pcap=%s)" % (passed, len(PLAN), os.path.basename(args.from_pcap)))
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(dict(pcap=args.from_pcap, expect_base=args.expect_base,
                           passed=passed, total=len(PLAN), items=results),
                      f, ensure_ascii=False, indent=2)
        print("JSON: %s" % args.json)
    return 0 if passed == len(PLAN) else 1


if __name__ == "__main__":
    sys.exit(main())
