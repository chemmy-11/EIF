# -*- coding: utf-8 -*-
"""R2 收尾归档: 把本轮构建/离线产物归档到 out/archive/b31b_r2_2026-10-17/ 并生成 SHA256.txt.
用法: python r2_archive.py <mode>   mode = success | fail
- success: 位流/ltx/xsa 必须存在, 一并归档
- fail: 无位流; 归档综合/扫描日志/失败轮报告/RTL 快照/ELF, 并在 SHA256.txt 标注 NO_BITSTREAM
所有路径均为绝对路径 (项目内), 只读源文件, 写入归档目录.
"""
import hashlib, io, os, shutil, sys, datetime

P = r"D:\FPGA\prj\project_11"
ARC = os.path.join(P, "out", "archive", "b31b_r2_2026-10-17")
OUT = os.path.join(P, "out")
mode = sys.argv[1] if len(sys.argv) > 1 else "fail"

os.makedirs(ARC, exist_ok=True)


def sha256(p):
    h = hashlib.sha256()
    with io.open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


items = []  # (dst_name, src_path)


def add(dst, src, required=False):
    if os.path.exists(src):
        items.append((dst, src))
    elif required:
        raise SystemExit("MISSING required artifact: " + src)


# ---- 位流族 (仅 success) ----
if mode == "success":
    add("aurora_mem_bridge_r2.bit", os.path.join(OUT, "aurora_mem_bridge.bit"), True)
    add("probes_r2.ltx", os.path.join(P, "scripts", "probes.ltx"), True)
    add("mb_ctrl_r2.xsa", os.path.join(OUT, "mb_ctrl.xsa"), True)
else:
    add("aurora_mem_bridge_r2.last_attempt.bit.absent", os.path.join(OUT, "aurora_mem_bridge.bit"))  # 老文件仅作参照

# ---- RTL 快照 (可追溯本轮改动) ----
for f in ["axi4_master_bridge.v", "frame_mem_if.v", "aurora_mem_bridge.v", "axi_lite_regs.v"]:
    add("rtl_" + f, os.path.join(P, "rtl", f), True)
add("main.c", os.path.join(P, "sw", "src_j3", "main.c"), True)
add("create_bd_b.tcl", os.path.join(P, "scripts", "create_bd_b.tcl"), True)
add("build_synth_only.tcl", os.path.join(P, "scripts", "build_synth_only.tcl"), True)
add("build_v5_sweep.tcl", os.path.join(P, "scripts", "build_v5_sweep.tcl"), True)
add("build_v5_sweep2.tcl", os.path.join(P, "scripts", "build_v5_sweep2.tcl"), True)

# ---- ELF ----
add("j3_soft_r2_1bc8088d.elf", os.path.join(P, "sw", "j3_soft", "Debug", "j3_soft.elf"), True)

# ---- 构建日志/失败轮报告 ----
add("build_r2_synth.log", os.path.join(OUT, "r2_synth.log"))
add("build_r2_sweep.log", os.path.join(OUT, "r2_sweep.log"))
add("build_r2_sweep_console.log", os.path.join(OUT, "r2_sweep_console.log"))
add("build_r2_sweep2.log", os.path.join(OUT, "r2_sweep2.log"))
add("build_r2_sweep2_console.log", os.path.join(OUT, "r2_sweep2_console.log"))
for fn in sorted(os.listdir(OUT)):
    if fn.startswith("rpt2_") and fn.endswith((".rpt",)):
        add(fn, os.path.join(OUT, fn))

# ---- 复制 ----
copied = []
for dst, src in items:
    d = os.path.join(ARC, dst)
    shutil.copy2(src, d)
    copied.append((dst, src, sha256(d), os.path.getsize(d)))

# ---- SHA256.txt ----
lines = []
lines.append("b31b_r2_2026-10-17 归档清单")
lines.append("生成时间: " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
lines.append("构建模式: " + ("SUCCESS（含位流对）" if mode == "success" else "FAIL（时序门限拒收，NO_BITSTREAM）"))
lines.append("ELF 冻结: 1bc8088d (50,896 B)  bit 配置口径见 调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md")
lines.append("")
lines.append("| 文件 | 字节 | SHA256 |")
lines.append("|---|---|---|")
for dst, src, h, n in copied:
    lines.append("| %s | %d | %s |" % (dst, n, h))
lines.append("")
lines.append("注: 位流若存在, 烧写前一律先 Get-FileHash 核对本表 SHA256; 失败轮不覆盖在库产物。")
txt = "\n".join(lines) + "\n"
io.open(os.path.join(ARC, "SHA256.txt"), "w", encoding="utf-8", newline="\n").write(txt)
print("ARCHIVE_DONE:", ARC, "files=", len(copied), "mode=", mode)
for dst, src, h, n in copied:
    print("  %-45s %10d  %s..." % (dst, n, h[:16]))
