#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""m1a_sweep.py -- prj12 M1-A 双板对称采集脚本（PC1/PC2 各跑一份，互为收发）。

背景：M1-A-1（六尺寸×20帧）、A-2（每方向 10 MiB）、A-3（≥5 轮）、A-4（同时双向）
都需要"发送 + 对向单次连续抓包 + 按 run_id 判定"。本脚本把四件事合并进**一个
180 s 连续抓包窗口**：双方各开抓包 → 延时 20 s → 各自按计划发送 → 抓包结束后
各自判定**收到的对向帧**。

对称约定（两边必须一致）：
  PC1：--role pc1 --dir ab --send-base 0x100 --expect-base 0x200
  PC2：--role pc2 --dir ba --send-base 0x200 --expect-base 0x100
计划（两边相同，偏移量相同）：
  size26/64/100/512/1024/1472 : count=20, interval=0
  bidir1472                   : count=20, interval=0
  round1..round5              : count=20, len=100, interval=0
  big10MiB                    : len=1200, count=8739, interval=0.5ms
run_id = 基址 + 偏移（0x01..0x06 / 0xF1 / 0x11..0x15 / 0xA0）

用法：
  py pc\\m1a_sweep.py --iface 497F7354 --role pc1 --dir ab --send-base 0x100 --expect-base 0x200
  py pc\\m1a_sweep.py --iface <GUID>   --role pc2 --dir ba --send-base 0x200 --expect-base 0x100
  py pc\\m1a_sweep.py ... --dry-run          # 只打印计划
  py pc\\m1a_sweep.py ... --phase basic      # 只跑 sizes+rounds+bidir（不跑 10 MiB）
"""
import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
CAP = os.path.join(HERE, "npcap_capture.py")
SEND = os.path.join(HERE, "twin_send.py")
RECV = os.path.join(HERE, "twin_recv.py")
BIG_BYTES = 10 * 1024 * 1024
BIG_LEN = 1200
BIG_COUNT = (BIG_BYTES + BIG_LEN - 1) // BIG_LEN


def build_plan(send_base, phase, small_interval=0.0, big_interval=0.7):
    """small_interval/big_interval 是 2026-11-12 加的节奏参数。

    为什么必须能调（实测）：20 帧 `interval=0` 是背靠背突发，PC 会在同一毫秒内把 20 帧
    全塞给网卡，板卡 RX 侧扛不住 —— 两个方向都只到 5–9/20；而 8739 帧 @0.7 ms 的连续流
    在 B→A 上是 8739/8739=100%。所以"丢包"主要由发送节奏决定，与帧长/方向无关。
    默认值保持 0.0 / 0.7 不变，保证旧命令的行为与哈希语义不变。
    """
    items = []
    for i, L in enumerate((26, 64, 100, 512, 1024, 1472), start=1):
        items.append(dict(label="size%d" % L, length=L, count=20, run=send_base + i, interval=small_interval))
    items.append(dict(label="bidir1472", length=1472, count=20, run=send_base + 0xF1, interval=small_interval))
    for i in range(1, 6):
        items.append(dict(label="round%d" % i, length=100, count=20, run=send_base + 0x10 + i, interval=small_interval))
    if phase == "all":
        items.append(dict(label="big10MiB", length=BIG_LEN, count=BIG_COUNT, run=send_base + 0xA0, interval=big_interval))
    return items


def run(cmd, timeout=300):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main():
    ap = argparse.ArgumentParser(description="M1-A symmetric sweep (send + capture + judge)")
    ap.add_argument("--iface", default="", help="Npcap 设备名/描述子串")
    ap.add_argument("--role", choices=["pc1", "pc2"], required=True)
    ap.add_argument("--dir", choices=["ab", "ba"], required=True)
    ap.add_argument("--send-base", type=lambda s: int(s, 0), required=True)
    ap.add_argument("--expect-base", type=lambda s: int(s, 0), required=True)
    ap.add_argument("--seconds", type=float, default=180.0)
    ap.add_argument("--start-delay", type=float, default=20.0)
    ap.add_argument("--phase", choices=["all", "basic"], default="all")
    ap.add_argument("--small-interval", type=float, default=0.0,
                    help="小项(20帧)的帧间隔 ms；默认 0.0=背靠背(旧行为)。"
                         "实测 0.0 时板卡 RX 只收到 5-9/20，建议 1.0")
    ap.add_argument("--big-interval", type=float, default=0.7,
                    help="big10MiB 的帧间隔 ms；默认 0.7（实测 B→A 8739/8739 零丢）")
    ap.add_argument("--out-dir", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    out_dir = args.out_dir or os.path.join(os.path.dirname(HERE), "out", "evidence_20261112_m1a_dualboard", "judge")
    os.makedirs(out_dir, exist_ok=True)
    plan = build_plan(args.send_base, args.phase, args.small_interval, args.big_interval)
    ts = time.strftime("%Y%m%d_%H%M%S")
    pcap = os.path.join(os.path.dirname(HERE), "out", "evidence_20261112_m1a_dualboard", "pcap", "m1a_%s_%s.pcap" % (args.role, ts))
    os.makedirs(os.path.dirname(pcap), exist_ok=True)
    log_path = os.path.join(out_dir, "sweep_%s_%s.log" % (args.role, ts))

    print("=== m1a_sweep role=%s dir=%s iface=%s ===" % (args.role, args.dir, args.iface))
    print("send_base=0x%X expect_base=0x%X seconds=%.0f delay=%.0f phase=%s" %
          (args.send_base, args.expect_base, args.seconds, args.start_delay, args.phase))
    for it in plan:
        print("  SEND %-10s len=%-5d count=%-5d run=0x%X interval=%.1f ms" %
              (it["label"], it["length"], it["count"], it["run"], it["interval"]))
    total_send = sum(it["count"] for it in plan)
    print("  total frames=%d (both directions combined at receiver)" % total_send)

    if args.dry_run:
        print("DRY_RUN: nothing executed")
        return 0

    log = []

    def logfile(tag, text):
        log.append("--- %s ---\n%s" % (tag, text))

    # 1) 启动抓包（后台）
    cap_cmd = [PY, CAP, "--iface", args.iface, "--seconds", str(int(args.seconds)), "--out", pcap]
    print("CAPTURE: %s" % " ".join(cap_cmd))
    cap = subprocess.Popen(cap_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    # 2) 延时后发送本方向计划
    time.sleep(args.start_delay)
    send_all_ok = True
    for it in plan:
        cmd = [PY, SEND, "--count", str(it["count"]), "--len", str(it["length"]),
               "--run-id", hex(it["run"]), "--interval-ms", str(it["interval"])]
        rc, out = run(cmd, timeout=120)
        ok = rc == 0 and "SEND_OK" in out
        send_all_ok &= ok
        print("SEND %-10s rc=%d %s" % (it["label"], rc, "OK" if ok else "FAIL"))
        logfile("send " + it["label"], out)

    # 3) 等抓包结束
    cap_out, _ = cap.communicate(timeout=args.seconds + 120)
    logfile("capture", cap_out or "")

    # 4) 判定对向帧
    judge_ok = 0
    for it in plan:
        expect_run = args.expect_base + (it["run"] - args.send_base)
        cmd = [PY, RECV, "--from-pcap", pcap, "--expect-count", str(it["count"]),
               "--expect-len", str(it["length"]), "--expect-run-id", hex(expect_run)]
        rc, out = run(cmd, timeout=300)
        ok = rc == 0
        judge_ok += 1 if ok else 0
        print("JUDGE %-10s run=0x%X rc=%d %s" % (it["label"], expect_run, rc, "PASS" if ok else "FAIL"))
        logfile("judge " + it["label"], out)

    with open(log_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("m1a_sweep role=%s dir=%s iface=%s pcap=%s\nts=%s\n" %
                (args.role, args.dir, args.iface, pcap, ts))
        f.write("\n".join(log) + "\n")

    print("PCAP: %s" % pcap)
    print("LOG : %s" % log_path)
    print("M1A_SWEEP_RESULT: role=%s sent=%s judge=%d/%d %s" %
          (args.role, "OK" if send_all_ok else "FAIL", judge_ok, len(plan),
           "PASS" if judge_ok == len(plan) and send_all_ok else "FAIL"))
    return 0 if judge_ok == len(plan) and send_all_ok else 1


if __name__ == "__main__":
    sys.exit(main())

