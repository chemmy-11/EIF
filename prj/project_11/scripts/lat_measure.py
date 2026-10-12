#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lat_measure.py — prj11 B3-0 板上 Lw/Lr 实测（UDP GET_LATENCY 0x05 路）

配套: 操作文档/阶段三_prj11_B3数据面换层执行单_2026-10-12 §一（B3-0）
     结论_cross_prj10_MIG读写延迟LwLr口径核查_2026-10-10 §六 方案甲（判据）

原理: 桥内 lat_w (AW->B 出队拍数) / lat_r (AR->首个 R 拍) 经 cmd_channel
      OP_GET_LAT(0x05) 回读（v16=Lw, v16b=Lr, v16c=采样序号）。

采样策略（关键）: lat_w 只在**提交队列空**时武装 —— 故写侧必须**间隔投放**
（每帧之间留空档），每帧后立即回读一次，取到的是该隔离帧的真实延迟。
SEQ 模式下写进槽的帧会被桥①自动读回（回显），其读延迟即 lat_r 的样本。

判据: 连续 N>=100 帧，Lw/Lr 拍数分布稳定（min/中位/max），换算
      us = 拍 x 3.332 ns；与粗上界 <11,300 拍 与条件上界 <=2100 拍核对。

用法:
  set PYTHONUTF8=1
  python lat_measure.py                 # N=128, pace 4ms
  python lat_measure.py --n 256 --pace-ms 3
  python lat_measure.py --json-out lat_board.json
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time

J3 = r"D:\FPGA\prj\project_10\prj_loop\scripts\j3_random_read.py"
sys.path.insert(0, os.path.dirname(J3))
from j3_random_read import (CmdClient, DataPlane,  # noqa: E402
                            MODE_SEQ, MODE_RND, build_payload, warmup_link)

OP_GET_LAT = 0x05
CYC_NS = 3.332           # ui_clk 300 MHz -> 3.332 ns/cycle (MIG report)
COARSE_BOUND = 11300     # 拍, 无条件粗上界 (Lw < 37.7 us)
COND_BOUND = 2100        # 拍, 条件性上界 (前提未证实)


def log(m):
    print(m, flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--n", type=int, default=128, help="隔离帧数（>=100）")
    p.add_argument("--pace-ms", type=float, default=4.0, help="帧间隔 ms（保提交队列空）")
    p.add_argument("--size", type=int, default=64)
    p.add_argument("--json-out", default=None)
    a = p.parse_args()

    cli = CmdClient("192.168.1.102")
    dm = DataPlane("192.168.1.102")

    log("=== B3-0 板上 Lw/Lr 实测 (UDP GET_LATENCY 0x05) ===")
    # 起手: 回 SEQ（RND 下板发不出 ARP 应答, 单播数据帧会被 PC 丢弃）
    try:
        cli.set_mode(MODE_SEQ)
    except Exception as e:
        log("SET_MODE(SEQ) 失败: %s" % e)
    warmup_link(dm.dst[0], dm.dst[1], enabled=True, settle_s=0.8, bind_ip="192.168.1.102")
    time.sleep(0.5)

    # 基线: 先看一次计数是否可读
    try:
        r0 = cli.send(OP_GET_LAT, label="GET_LAT baseline")
        log("基线 LAT_W=%d LAT_R=%d (seq=%d)" %
            (r0["value16"], r0["value16b"], r0["value16c"]))
    except Exception as e:
        log("GET_LATENCY 不可用: %s" % e)
        return 2

    samples = []
    t0 = time.time()
    for k in range(a.n):
        payload = build_payload(2000 + k, 1, a.size)
        dm.send(payload)                      # 写一帧（桥① -> DDR）
        time.sleep(a.pace_ms / 1000.0)          # 间隔: 保提交队列空 -> lat_w 武装
        try:
            r = cli.send(OP_GET_LAT, label="L%d" % k)
        except Exception as e:
            log("第 %d 帧回读失败: %s" % (k, e))
            continue
        samples.append((r["value16"], r["value16b"], r["value16c"]))
        if (k + 1) % 32 == 0:
            log("  进度 %d/%d  最近 LAT_W=%d LAT_R=%d" %
                (k + 1, a.n, r["value16"], r["value16b"]))
    dur = time.time() - t0
    dm.drain(0.5)

    if not samples:
        log("LAT_BOARD: FAIL (无有效样本)")
        return 1

    lw = [s[0] for s in samples if s[0] != 0]
    lr = [s[1] for s in samples if s[1] != 0]
    log("-" * 66)
    log("样本 %d 帧 (用时 %.1fs)  非零样本: Lw=%d Lr=%d" %
        (len(samples), dur, len(lw), len(lr)))

    def stat(name, v):
        if not v:
            log("  %s: 无有效样本" % name)
            return None
        mn, md, mx = min(v), int(statistics.median(v)), max(v)
        log("  %s: min=%d  中位=%d  max=%d 拍   (%d 个不同值)"
            % (name, mn, md, mx, len(set(v))))
        log("      换算: min=%.2f us  中位=%.2f us  max=%.2f us"
            % (mn * CYC_NS / 1000.0, md * CYC_NS / 1000.0, mx * CYC_NS / 1000.0))
        return {"min": mn, "median": md, "max": mx, "n": len(v)}

    sw = stat("Lw (AW->B)", lw)
    sr = stat("Lr (AR->首R)", lr)

    errs = []
    if not lw:
        errs.append("Lw 无有效样本")
    elif sw["max"] >= COARSE_BOUND:
        errs.append("Lw max=%d >= 粗上界 %d" % (sw["max"], COARSE_BOUND))
    if not lr:
        errs.append("Lr 无有效样本（SEQ 自动读应产生样本）")

    verdict = "PASS" if not errs else "FAIL"
    log("-" * 66)
    if sw:
        log("  Lw 与粗上界(%d 拍)对照: max=%d → %s" %
            (COARSE_BOUND, sw["max"], "满足" if sw["max"] < COARSE_BOUND else "超出"))
        log("  Lw 与条件上界(%d 拍)对照: max=%d → %s" %
            (COND_BOUND, sw["max"], "满足(前提成立)" if sw["max"] <= COND_BOUND else "不满足(前提不成立)"))
    log("LAT_BOARD: %s%s" % (verdict, ("  " + "; ".join(errs)) if errs else ""))

    if a.json_out:
        with open(a.json_out, "w", encoding="utf-8") as f:
            json.dump({"verdict": verdict, "n": len(samples),
                       "Lw": sw, "Lr": sr, "cycle_ns": CYC_NS,
                       "coarse_bound": COARSE_BOUND, "cond_bound": COND_BOUND,
                       "samples_tail": samples[-16:]}, f, ensure_ascii=False, indent=1)
        log("JSON: %s" % a.json_out)
    return 0 if not errs else 1


if __name__ == "__main__":
    sys.exit(main())
