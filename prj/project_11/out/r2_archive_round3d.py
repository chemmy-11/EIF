# -*- coding: utf-8 -*-
"""R2 round3d (2026-10-19) 归档: 成功位流对 -> out/archive/b31b_r2_2026-10-19_round3d/ + SHA256.txt.
round3d = round3c-diag 的验收版: ILA3 恢复 152b 全量（S6/S10 判据计数），ILA5 47b，ILA4 跳过。
用法: python r2_archive_round3d.py [success]
"""
import hashlib
import io
import os
import shutil
import time
import sys
import datetime

P = r"D:\FPGA\prj\project_11"
ARC = os.path.join(P, "out", "archive", "b31b_r2_2026-10-19_round3d")
OUT = os.path.join(P, "out")
EVID = os.path.join(OUT, "evidence_2026-10-19")
mode = sys.argv[1] if len(sys.argv) > 1 else "success"
os.makedirs(ARC, exist_ok=True)


def sha256(p):
    h = hashlib.sha256()
    with io.open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest().upper()


items = []


def add(dst, src, required=False):
    if os.path.exists(src):
        items.append((dst, src))
    elif required:
        raise SystemExit("MISSING required artifact: " + src)


elf = os.path.join(P, "sw", "j3_soft", "Debug", "j3_soft.elf")
elf8 = sha256(elf)[:8] if os.path.exists(elf) else "NOELF"

if mode == "success":
    add("aurora_mem_bridge_r2.bit", os.path.join(OUT, "aurora_mem_bridge.bit"), True)
    add("probes_r2.ltx", os.path.join(P, "scripts", "probes.ltx"), True)
    add("mb_ctrl_r2.xsa", os.path.join(OUT, "mb_ctrl.xsa"), True)
    bit = os.path.join(OUT, "aurora_mem_bridge.bit")
    if os.path.exists(bit):
        h8 = sha256(bit)[:8]
        shutil.copy2(bit, os.path.join(ARC, "aurora_mem_bridge_r2_%s.bit" % h8))
        ltx = os.path.join(P, "scripts", "probes.ltx")
        if os.path.exists(ltx):
            shutil.copy2(ltx, os.path.join(ARC, "probes_r2_%s.ltx" % h8))

# RTL / 固件 / 脚本快照
for f in ["axi4_master_bridge.v", "frame_mem_if.v", "aurora_mem_bridge.v", "axi_lite_regs.v"]:
    add("rtl_" + f, os.path.join(P, "rtl", f), True)
add("main.c", os.path.join(P, "sw", "src_j3", "main.c"), True)
add("j3_soft_r2_%s.elf" % elf8, elf, True)
add("create_bd_b.tcl", os.path.join(P, "scripts", "create_bd_b.tcl"), True)
add("build_synth_only.tcl", os.path.join(P, "scripts", "build_synth_only.tcl"), True)
add("build_debug.tcl", os.path.join(P, "scripts", "build_debug.tcl"), True)
add("build_v5_sweep2.tcl", os.path.join(P, "scripts", "build_v5_sweep2.tcl"), True)
add("r3c2_sweep_one.tcl", os.path.join(OUT, "r3c2_sweep_one.tcl"))
add("r3d_synth_retry.ps1", os.path.join(OUT, "r3d_synth_retry.ps1"))
add("r3d_sweep_one_retry.ps1", os.path.join(OUT, "r3d_sweep_one_retry.ps1"))
add("r2_ilacap.tcl", os.path.join(OUT, "r2_ilacap.tcl"))
add("j3_fourchains.ps1", os.path.join(OUT, "j3_fourchains.ps1"))
add("j3_fourchains_original.ps1", os.path.join(OUT, "j3_fourchains.ps1.bak_20261019_r2"))
add("r2_archive_round3d.py", os.path.join(OUT, "r2_archive_round3d.py"))
# BD 快照
bd = os.path.join(P, "vivado", "prj11.srcs", "sources_1", "bd", "mb_ctrl", "mb_ctrl.bd")
add("mb_ctrl.bd", bd)

# 构建日志 + S0 adapter 日志
for fn, dst in [
    ("r3d_synth.log", "build_r3d_synth.log"),
    ("r3d_synth_console.log", "build_r3d_synth_console.log"),
    ("r3d_one.log", "build_r3d_one.log"),
    ("r3d_one_console.log", "build_r3d_one_console.log"),
]:
    add(dst, os.path.join(OUT, fn))

# 模板报告
for fn in sorted(os.listdir(OUT)):
    if (fn.startswith("rpt3_") or fn.startswith("rpt2_")) and fn.endswith(".rpt"):
        add(fn, os.path.join(OUT, fn))

# 板验关键证据副本（终验那轮）
for fn in [
    "R3C_fourtier_perf1.log", "R3C_board_session_20261019.md", "R3C_evt2_dump.txt",
    "R3D_S0-S11_run1.log", "R3D_S0-S11_run2.log", "R3D_S0-S11_run3.log",
    "EVIDENCE_INDEX_r3c.md", "R3D_S10_recon_manual.log", "R3D_S10_recon_manual.json",
    "R2_4tier_20261019_164245.log", "R2_mb10_20261019_164518.log",
]:
    add(os.path.join("evidence", fn), os.path.join(EVID, fn))

copied = []
_ad = os.path.join(ARC, "R3D_s0_buildlog_adapter.log")
if os.path.exists(_ad):
    copied.append(("R3D_s0_buildlog_adapter.log", sha256(_ad), os.path.getsize(_ad)))
for dst, src in items:
    d = os.path.join(ARC, dst)
    ddir = os.path.dirname(d)
    if ddir and not os.path.isdir(ddir):
        os.makedirs(ddir, exist_ok=True)
    for attempt in range(5):
        try:
            shutil.copy2(src, d)
            break
        except PermissionError as e:
            print('COPY_RETRY', dst, 'from', src, 'attempt', attempt, e)
            time.sleep(1.0)
    else:
        raise SystemExit('COPY_FAILED ' + src + ' -> ' + d)
    copied.append((dst, sha256(d), os.path.getsize(d)))

lines = [
    "b31b_r2_2026-10-19_round3d 归档清单（round3c-diag 的验收版：ILA3=152b 全量，S6/S10 判据仪器齐）",
    "生成时间: " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    "round3d 改动: 相对 round3c-diag 仅 ILA 探针恢复（ILA3 63b->152b 全量：mem/mem2 计数 + stall/len_err；"
    "ILA5 保持 47b；ILA4 跳过）。功能 RTL/BD 不变。",
    "构建: build_synth_only.tcl（R3C_SKIP_ILA4=1 + R3C_LITE_ILA5=1） + 单掷 ExtraTimingOpt（r3c2_sweep_one.tcl）",
    "固件: 验收版 perf1（s2mm_rearm 修复 + 全速服务），ELF " + elf8,
    "",
    "| 文件 | 字节 | SHA256 |",
    "|---|---|---|",
]
for dst, h, n in copied:
    lines.append("| %s | %d | %s |" % (dst, n, h))
lines.append("")
lines.append("注: 位流烧写前一律先 Get-FileHash 核对本表 SHA256; 本目录只收成功对。")
txt = "\n".join(lines) + "\n"
io.open(os.path.join(ARC, "SHA256.txt"), "w", encoding="utf-8", newline="\n").write(txt)
print("ARCHIVE_DONE:", ARC, "files=", len(copied))
for dst, h, n in copied:
    if dst.endswith((".bit", ".ltx", ".xsa", ".elf")):
        print("  KEY %-44s %10d  %s" % (dst, n, h[:24]))
