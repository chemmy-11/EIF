#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""r2_neg_patch.py -- R2 WR TB 负向对照缺陷副本生成器（坑 #43 纪律）

从冻结的 rtl/axi4_master_bridge.v 复制出两个缺陷副本（不改原文件）:
  r2_neg_cursor/axi4_master_bridge.v : 被拒帧不推进槽游标
  r2_neg_tkeep/axi4_master_bridge.v  : 尾拍 TKEEP 用满 64 lane
若冻结文件 git hash 与 Lead 冻结值不符 -> 硬失败（防止拿错版本）。

注：本脚本只做文本注入；每个 patch 必须恰好命中 1 处，否则硬失败。
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, '..'))
RTL = os.path.join(PROJ, 'rtl', 'axi4_master_bridge.v')

# Lead 冻结值（2026-10-18 18:2x round2f：采纳 fix2 —— WD_WAITGO arm/wait 互斥, 修 4d1c50c7 的首拍并行执行缺陷）
EXPECT_HASH = 'c92c20c7fb1884cb6238daf6e03dd69daa93f172'

# 附加守卫（2026-10-18 round2d）：TB 的 DUT 例化 frame_mem_if（内部例化 bridge），
# fmi 变化同样会改变仿真语义 -> 一并冻结。lite_regs/顶层不在本 TB 依赖内（TB 不编译），
# 故它们的 hash 变化（如 round2d 的 d133b508 AXI 修复）不需要更新本守卫。
RTL_FMI = os.path.join(PROJ, 'rtl', 'frame_mem_if.v')
EXPECT_FMI_HASH = '96d5b136305e81ee9d4cc716e60c5034581d027d'


def git_hash_object(path):
    out = subprocess.run(['git', '-C', 'D:/FPGA', 'hash-object', path],
                         capture_output=True)
    return out.stdout.decode('ascii', 'replace').strip()


def main():
    if not os.path.exists(RTL):
        print('FATAL: rtl not found: %s' % RTL)
        return 1
    h = git_hash_object(RTL)
    print('frozen rtl hash : %s' % h)
    print('expected  hash  : %s' % EXPECT_HASH)
    if h != EXPECT_HASH:
        print('FATAL: rtl/axi4_master_bridge.v 与 Lead 冻结 hash 不符 -> 拒绝生成缺陷副本')
        return 1
    if not os.path.exists(RTL_FMI):
        print('FATAL: rtl/frame_mem_if.v not found: %s' % RTL_FMI)
        return 1
    h_fmi = git_hash_object(RTL_FMI)
    print('frozen fmi hash : %s' % h_fmi)
    print('expected fmi    : %s' % EXPECT_FMI_HASH)
    if h_fmi != EXPECT_FMI_HASH:
        print('FATAL: rtl/frame_mem_if.v 与 Lead 冻结 hash 不符 -> 拒绝生成缺陷副本（TB DUT 语义已变）')
        return 1

    src = open(RTL, encoding='utf-8', errors='replace').read()

    # ---- defect 1: 被拒帧不推进槽游标 ----
    anchor = 'wr_last_slot_r  <= wd_slot_next;'
    i = src.find(anchor)
    if i < 0:
        print('FATAL: cursor patch anchor not found')
        return 1
    j = src.find("wr_slot_ptr <= wr_slot_ptr + 16'd1;", i)
    if j < 0:
        print('FATAL: cursor patch target not found')
        return 1
    old = "wr_slot_ptr <= wr_slot_ptr + 16'd1;"
    new = "wr_slot_ptr <= (wd_noroom_n | wd_badlen_n) ? wr_slot_ptr : (wr_slot_ptr + 16'd1);"
    cur = src[:j] + new + src[j + len(old):]
    if cur.count(new) != 1 or src.count(old) < 1:
        print('FATAL: cursor patch did not apply cleanly')
        return 1
    print('cursor defect   : refused frame does NOT advance wr_slot_ptr  (1 substitution)')

    # ---- defect 2: 尾拍 TKEEP 用满 64 lane ----
    pat = re.compile(r"wd_keep_r\[wd_bi\]\s*<=\s*1'b1;")
    hits = pat.findall(src)
    if len(hits) != 1:
        print('FATAL: tkeep patch expected exactly 1 hit, got %d' % len(hits))
        return 1
    tk = pat.sub("wd_keep_r <= {64{1'b1}};", src)
    if tk.count("{64{1'b1}}") != 1:
        print('FATAL: tkeep patch did not apply cleanly')
        return 1
    print('tkeep defect    : tail beat TKEEP forced to 64 lanes          (1 substitution)')

    d1 = os.path.join(HERE, 'r2_neg_cursor')
    d2 = os.path.join(HERE, 'r2_neg_tkeep')
    os.makedirs(d1, exist_ok=True)
    os.makedirs(d2, exist_ok=True)
    open(os.path.join(d1, 'axi4_master_bridge.v'), 'w', encoding='utf-8', newline='\n').write(cur)
    open(os.path.join(d2, 'axi4_master_bridge.v'), 'w', encoding='utf-8', newline='\n').write(tk)
    print('defect copies written:')
    print('  %s' % os.path.join(d1, 'axi4_master_bridge.v'))
    print('  %s' % os.path.join(d2, 'axi4_master_bridge.v'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
