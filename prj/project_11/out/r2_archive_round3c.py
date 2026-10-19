# -*- coding: utf-8 -*-
"""R2 round3c (2026-10-19) 归档: 成功位流对 -> out/archive/b31b_r2_2026-10-19_round3c/ + SHA256.txt.
用法: python r2_archive_round3c.py [success]
前提: bit/ltx/xsa 由 build_v5_sweep2.tcl 写出 (out/aurora_mem_bridge.bit, scripts/probes.ltx, out/mb_ctrl.xsa)
round3c 新点: lite_regs dbg_o[35:0] 观测总线 + BD 端口 dbg_l_bus + u_ila_4@clk_100m +
              u_ila_5 probe5 (GO/ACK/introut/go_ok/state) + 诊断固件含 g_step。
"""
import hashlib, io, os, shutil, sys, datetime

P = r"D:\FPGA\prj\project_11"
ARC = os.path.join(P, "out", "archive", "b31b_r2_2026-10-19_round3c")
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


elf = os.path.join(P, "sw", "j3_soft", "Debug", "j3_soft.elf")
elf8 = sha256(elf)[:8] if os.path.exists(elf) else "NOELF"

# 位流族 (仅成功)
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
        shutil.copy2(bit, os.path.join(ARC, "aurora_mem_bridge_r2.bit"))

# RTL/固件/脚本快照
for f in ["axi4_master_bridge.v", "frame_mem_if.v", "aurora_mem_bridge.v", "axi_lite_regs.v"]:
    add("rtl_" + f, os.path.join(P, "rtl", f), True)
add("main.c", os.path.join(P, "sw", "src_j3", "main.c"), True)
add("main_vitis_copy.c", os.path.join(P, "sw", "j3_soft", "src", "main.c"))
add("j3_soft_r2_%s.elf" % elf8, elf, True)
add("create_bd_b.tcl", os.path.join(P, "scripts", "create_bd_b.tcl"), True)
add("build_synth_only.tcl", os.path.join(P, "scripts", "build_synth_only.tcl"), True)
add("build_debug.tcl", os.path.join(P, "scripts", "build_debug.tcl"), True)
add("build_v5_sweep2.tcl", os.path.join(P, "scripts", "build_v5_sweep2.tcl"), True)
add("r3c_synth_retry.ps1", os.path.join(OUT, "r3c_synth_retry.ps1"))
# BD 快照 (新端口 dbg_l_bus 的载体; 位于 vivado 工程目录, 不入 git)
bd = os.path.join(P, "vivado", "prj11.srcs", "sources_1", "bd", "mb_ctrl", "mb_ctrl.bd")
add("mb_ctrl.bd", bd)

# 构建日志
for fn, dst in [("r3c_synth.log", "build_r3c_synth_attempt1.log"),
                ("r3c_synth_console.log", "build_r3c_synth_attempt1_console.log"),
                ("r3c_sweep2.log", "build_r3c_sweep2_attempt1.log"),
                ("r3c_sweep2_console.log", "build_r3c_sweep2_attempt1_console.log"),
                ("r3c2_synth.log", "build_r3c_synth.log"),
                ("r3c2_synth_console.log", "build_r3c_synth_console.log"),
                ("r3c2_sweep2.log", "build_r3c_sweep2.log"),
                ("r3c2_sweep2_console.log", "build_r3c_sweep2_console.log"),
                ("r3c_synth_retry.ps1", "r3c_synth_retry.ps1"),
                ("r3c_sweep2_retry.ps1", "r3c_sweep2_retry.ps1"),
                ("r3c2_synth_retry.ps1", "r3c2_synth_retry.ps1"),
                ("r3c2_sweep2_retry.ps1", "r3c2_sweep2_retry.ps1"),
                ("r3c3_synth.log", "build_r3c3_synth.log"),
                ("r3c3_synth_console.log", "build_r3c3_synth_console.log"),
                ("r3c3_one.log", "build_r3c3_one.log"),
                ("r3c3_one_console.log", "build_r3c3_one_console.log"),
                ("r3c2_one.log", "build_r3c2_one_attempt2.log"),
                ("r3c2_one_console.log", "build_r3c2_one_attempt2_console.log"),
                ("r3c3_synth_retry.ps1", "r3c3_synth_retry.ps1"),
                ("r3c3_sweep_one_retry.ps1", "r3c3_sweep_one_retry.ps1"),
                ("r3c2_sweep_one.tcl", "r3c2_sweep_one.tcl"),
                ("r3c_regen_bd.log", "regen_bd_r3c.log"),
                ("r3c_regen_bd_console.log", "regen_bd_r3c_console.log")]:
    add(dst, os.path.join(OUT, fn))
# attempt1 证据目录（4 核构建被时序门限拒的日志）
att = os.path.join(OUT, "evidence_2026-10-19", "round3c_build_attempt1")
if os.path.isdir(att):
    for fn in sorted(os.listdir(att)):
        add(os.path.join("attempt1", fn), os.path.join(att, fn))

# 失败/成功轮报告 (若存在)
for fn in sorted(os.listdir(OUT)):
    if (fn.startswith("rpt2_") or fn.startswith("rpt3_")) and fn.endswith(".rpt"):
        add(fn, os.path.join(OUT, fn))

copied = []
for dst, src in items:
    d = os.path.join(ARC, dst)
    ddir = os.path.dirname(d)
    if ddir and not os.path.isdir(ddir):
        os.makedirs(ddir, exist_ok=True)
    shutil.copy2(src, d)
    copied.append((dst, sha256(d), os.path.getsize(d)))

lines = ["b31b_r2_2026-10-19_round3c 归档清单（lite_regs AXI 楔死探针 + S2MM GO 链探针轮）",
         "生成时间: " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
         "round3c 改动: ① axi_lite_regs.v 新增纯观测 output [35:0] dbg_o（AXI 握手/地址解码/lwst/lrst/"
         "aclk 侧邮箱/aresetn/rst_user_n 2FF+sticky/卡死 sticky 检测）② create_bd_b.tcl 引出 BD 端口 "
         "dbg_l_bus ③ 顶层 alias dbg_l_bus[35:0]/dbg_l_stuck_or ④ frame_mem_if/axi4_master_bridge "
         "增 mark_debug 别名（GO/ACK/introut 2FF 镜像、wd_go_ok）⑤ u_ila_5@ui 增 probe5=7b"
         "(go_ui/ack_ui/intr_ui/go_ok/state)。**本归档位流为 round3c-lite：u_ila_4 被 "
         "R3C_SKIP_ILA4 跳过（attempt1 四核版 ExtraTimingOpt 后路 WNS=-0.029 被门限拒，ltx=3 核）**。",
         "功能逻辑: 零改动（探针/观测计数器不反馈任何 FSM）",
         "诊断 ELF: " + elf8,
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
        print("  KEY %-44s %10d  %s" % (dst, n, h[:24]))
