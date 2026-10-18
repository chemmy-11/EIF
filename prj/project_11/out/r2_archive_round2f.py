# -*- coding: utf-8 -*-
"""R2 round2 (2026-10-18) 归档: 成功位流对 -> out/archive/b31b_r2_2026-10-18_round2f/ + SHA256.txt.
用法: python r2_archive_round2.py success
前提: bit/ltx/xsa 由 build_v5_sweep2.tcl 写出 (out/aurora_mem_bridge.bit, scripts/probes.ltx, out/mb_ctrl.xsa)
"""
import hashlib, io, os, shutil, sys, datetime

P = r"D:\FPGA\prj\project_11"
ARC = os.path.join(P, "out", "archive", "b31b_r2_2026-10-18_round2f")
OUT = os.path.join(P, "out")
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


# 位流族 (仅成功)
if mode == "success":
    add("aurora_mem_bridge_r2.bit", os.path.join(OUT, "aurora_mem_bridge.bit"), True)
    add("probes_r2.ltx", os.path.join(P, "scripts", "probes.ltx"), True)
    add("mb_ctrl_r2.xsa", os.path.join(OUT, "mb_ctrl.xsa"), True)
    # 位流/探针/xsa 的 hash 前缀命名副本 (便于归档名自解释)
    bit = os.path.join(OUT, "aurora_mem_bridge.bit")
    if os.path.exists(bit):
        h8 = sha256(bit)[:8]
        shutil.copy2(bit, os.path.join(ARC, "aurora_mem_bridge_r2_%s.bit" % h8))
        ltx = os.path.join(P, "scripts", "probes.ltx")
        if os.path.exists(ltx):
            shutil.copy2(ltx, os.path.join(ARC, "probes_r2_%s.ltx" % h8))

# RTL/固件/脚本快照
for f in ["axi4_master_bridge.v", "frame_mem_if.v", "aurora_mem_bridge.v", "axi_lite_regs.v"]:
    add("rtl_" + f, os.path.join(P, "rtl", f), True)
add("main.c", os.path.join(P, "sw", "src_j3", "main.c"), True)
add("create_bd_b.tcl", os.path.join(P, "scripts", "create_bd_b.tcl"), True)
add("build_synth_only.tcl", os.path.join(P, "scripts", "build_synth_only.tcl"), True)
add("build_v5_sweep2.tcl", os.path.join(P, "scripts", "build_v5_sweep2.tcl"), True)
add("j3_soft_r2_1bc8088d.elf", os.path.join(P, "sw", "j3_soft", "Debug", "j3_soft.elf"), True)

# 构建日志
for fn, dst in [("r2h_synth.log", "build_r2_synth.log"),
                ("r2h_synth_console.log", "build_r2_synth_console.log"),
                ("r2h_sweep2.log", "build_r2_sweep2.log"),
                ("r2h_sweep2_console.log", "build_r2_sweep2_console.log")]:
    add(dst, os.path.join(OUT, fn))

# 失败/成功轮报告 (若存在)
for fn in sorted(os.listdir(OUT)):
    if fn.startswith("rpt2_") and fn.endswith(".rpt"):
        add(fn, os.path.join(OUT, fn))

copied = []
for dst, src in items:
    d = os.path.join(ARC, dst)
    shutil.copy2(src, d)
    copied.append((dst, sha256(d), os.path.getsize(d)))

lines = ["b31b_r2_2026-10-18_round2f 归档清单（round2: 字节捕获流水时序修复后重建）",
         "生成时间: " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
         "RTL 冻结: axi4_master_bridge.v blob d133b508 (round2f: fix2 bridge c92c20c7 + lite d133b508; ELF f8cf4022)；其余三文件同 round1",
         "ELF 冻结: 1bc8088d (50,896 B)",
         "",
         "| 文件 | 字节 | SHA256 |",
         "|---|---|---|"]
for dst, h, n in copied:
    lines.append("| %s | %d | %s |" % (dst, n, h))
lines.append("")
lines.append("注: 位流烧写前一律先 Get-FileHash 核对本表 SHA256; 本目录只收成功对。")
txt = "\n".join(lines) + "\n"
io.open(os.path.join(ARC, "SHA256.txt"), "w", encoding="utf-8", newline="\n").write(txt)
print("ARCHIVE_DONE:", ARC, "files=", len(copied))
for dst, h, n in copied:
    if dst.endswith((".bit", ".ltx", ".xsa", ".elf")):
        print("  KEY %-40s %10d  %s" % (dst, n, h[:24]))
