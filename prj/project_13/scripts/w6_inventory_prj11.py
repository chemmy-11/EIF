# -*- coding: utf-8 -*-
"""w6_inventory_prj11.py -- prj11 路线 B 可观测性清单自动生成（W6 思路移植版，2026-10-19）

与 prj10 版区别：**以真实构建产物 LTX 为主源**（权威探针/位宽），RTL 声明做交叉比对，
避免从 Tcl 文本猜条件分支（round3c/round3d 的 env 裁剪会让纯文本解析算错）。

  1) probes_r2_<hash>.ltx : 每个 ILA 的 probe→net→位宽（按 LTX 实际连接）
  2) rtl/*.v              : 每个 dbg_* 声明的位宽/文件
  3) 交叉比对 -> 已挂 / 未挂（可观测性缺口）-> out/W6_prj11_可观测性清单.md

用法:
  py scripts/w6_inventory_prj11.py [--ltx <path>] [--check] [--out <path>]
  默认 LTX = out/archive/b31b_r2_2026-10-19_round3d/probes_r2_F6012BA0.ltx
"""
import io
import json
import os
import re
import sys
import time

PRJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # project_11
RTLDIR = os.path.join(PRJ, "rtl")
DEF_LTX = os.path.join(PRJ, "out", "archive", "b31b_r2_2026-10-19_round3d",
                       "probes_r2_F6012BA0.ltx")
DEF_OUT = os.path.join(PRJ, "out", "W6_prj11_可观测性清单.md")

CLOCK_HINT = {
    "u_ila_0": "user_clk（Aurora A，~151.5MHz）",
    "u_ila_3": "ui_clk（MIG ~300MHz）",
    "u_ila_4": "init_clk（100MHz；本轮 SKIP）",
    "u_ila_5": "ui_clk（MIG ~300MHz）",
}


def parse_ltx(path):
    d = json.load(io.open(path, encoding="utf-8"))
    entry = d["ltx_root"]["ltx_data"][0]
    cores = []
    for c in entry["debug_cores"]:
        if c.get("type") != "ILA_V3":
            continue
        probes = []
        for pin in c.get("pins", []):
            name = pin.get("name", "?")
            bits = pin.get("rightIndex", 0) - pin.get("leftIndex", 0) + 1
            nets = [n.get("name", "?") for n in pin.get("nets", [])]
            probes.append({"probe": name, "bits": bits, "nets": nets})
        cores.append({"core": c["name"], "probes": probes})
    return cores


def base_token(net):
    """LTX net -> 基础 dbg token（取最后一段，去掉 _rep/_1 之类后缀）"""
    t = net.replace("/", ".").split(".")[-1]
    t = re.sub(r"(_rep\d*|_\d+|_reg)$", "", t)
    return t


def parse_rtl(rtldir):
    decl = {}
    for fn in sorted(os.listdir(rtldir)):
        if not fn.endswith((".v", ".sv")):
            continue
        p = os.path.join(rtldir, fn)
        for ln in io.open(p, encoding="utf-8", errors="replace"):
            if "//" in ln:
                ln = ln.split("//", 1)[0]
            m = re.search(r"wire\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]\s+(dbg_\w+)", ln)
            if not m:
                m = re.search(r"output\s+wire\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]\s+(dbg_\w+)", ln)
            if m:
                w = abs(int(m.group(1)) - int(m.group(2))) + 1
                decl.setdefault(m.group(3), (w, fn))
                continue
            m = re.search(r"wire\s+(dbg_\w+)", ln)
            if m:
                decl.setdefault(m.group(1), (1, fn))
    return decl


# 判据 <-> 探针（人工维护；来源 out/r2_board.ps1 S4–S10）
CRIT_MAP = [
    ("S4/S5 单帧端到端（ping / NIC / WM 计数）",
     "ILA0 `dbg_mem_u_wr/u_rd`、`dbg_mem_rden`；ILA3 `dbg_mem_wm/wr_frm/rd_frm`、`dbg_s2mm_state/tvalid/tready`"),
    ("S6 桥级 ILA（mem 写/读 +4、ost=0；mem2 rd_frm +4、ost=0）",
     "ILA3 `dbg_mem_wm/wr_frm/rd_frm/ost`、`dbg_mem2_wm/wr_frm/rd_frm/ost`、`dbg_mem_stall/len_err`、`dbg_calib`"),
    ("S7 四档（PC 侧 UDP 逐字节）",
     "PC 侧判据；板上 `dbg_mem_wr_frm/rd_frm` + `dbg_mem2_*` 计数佐证"),
    ("S8 10MB 100%+SHA（PC 侧）",
     "PC 侧判据；`dbg_mem_wr_frm/rd_frm`、`dbg_wr_fault=0` 佐证"),
    ("S9 J3 四链（软核控制下导师四环节）",
     "PC 侧 j3_soft_verify 判据；串口 `U` 计数 + ILA3 `dbg_s2mm_state/tvalid` 佐证"),
    ("S10 双桥计数对账（mem/mem2 各自 wm==wr_frm==rd_frm、ost=0、stall/len_err=0、fault=0）",
     "ILA3 `dbg_mem_*` + `dbg_mem2_*`（152b 全量）；ILA0 `dbg_wr_fault`"),
    ("R2 写引擎 GO/ACK/introut 链（诊断用）",
     "ILA5 `dbg_wd_go_ui/ack_ui/intr_ui/go_ok`、`dbg_s2mm_tdata64/tkeep8/tvalid/tready/tlast_w`、`dbg_s2mm_state`"),
]


def main():
    argv = sys.argv[1:]
    check = "--check" in argv
    ltx = DEF_LTX
    out_path = DEF_OUT
    if "--ltx" in argv:
        ltx = argv[argv.index("--ltx") + 1]
    if "--out" in argv:
        out_path = argv[argv.index("--out") + 1]

    cores = parse_ltx(ltx)
    decl = parse_rtl(RTLDIR)

    # 已挂 token 集合（从 net 名提取基础 token）
    attached = {}
    for c in cores:
        for p in c["probes"]:
            for n in p["nets"]:
                attached.setdefault(base_token(n), set()).add(c["core"])

    unattached = sorted(n for n in decl if n not in attached)

    out = []
    out.append("# prj11 路线 B 可观测性清单（自动生成，勿手改）")
    out.append("")
    out.append("> 生成器 `scripts/w6_inventory_prj11.py`（W6 思路移植版，**以 LTX 构建产物为主源**）  ")
    out.append("> LTX 源：`%s`  " % os.path.relpath(ltx, PRJ).replace("\\", "/"))
    out.append("> RTL 源：`rtl/*.v` · 生成时间：%s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    out.append("")
    out.append("## 一、ILA 按域分挂")
    out.append("")
    out.append("| ILA | 时钟域 | 探针数 | 位宽合计 |")
    out.append("|---|---|---|---|")
    tot = 0
    for c in sorted(cores, key=lambda x: int(x["core"].split("_")[-1])):
        bits = sum(p["bits"] for p in c["probes"])
        tot += bits
        out.append("| `%s` | %s | %d | %d |" % (c["core"], CLOCK_HINT.get(c["core"], "?"), len(c["probes"]), bits))
    out.append("")
    out.append("合计挂载 **%d bit**（%d 个 ILA；本轮 ILA4 整核跳过）。" % (tot, len(cores)))
    out.append("")
    out.append("## 二、探针明细（LTX 实际连接）")
    out.append("")
    out.append("| ILA | probe | 位宽 | nets（基础名，多 net 时列出） |")
    out.append("|---|---|---|---|")
    for c in sorted(cores, key=lambda x: int(x["core"].split("_")[-1])):
        for p in c["probes"]:
            nets = ", ".join("`%s`" % base_token(n) for n in p["nets"])
            out.append("| `%s` | `%s` | %d | %s |" % (c["core"], p["probe"], p["bits"], nets))
    out.append("")
    out.append("## 三、RTL 声明与挂载状态")
    out.append("")
    out.append("| 信号 | 位宽 | 声明文件 | 挂载 ILA |")
    out.append("|---|---|---|---|")
    for name in sorted(decl):
        w, fn = decl[name]
        on = "、".join(sorted(attached.get(name, []))) if name in attached else "**未挂**"
        out.append("| `%s` | %d | `%s` | %s |" % (name, w, fn, on))
    out.append("")
    out.append("## 四、可观测性缺口（RTL 已声明但未上 ILA）")
    out.append("")
    if unattached:
        out.append("| 信号 | 位宽 | 声明文件 | 说明 |")
        out.append("|---|---|---|---|")
        for name in unattached:
            w, fn = decl[name]
            if name.startswith(("dbg_mem", "dbg_s2mm", "dbg_wd")):
                note = "300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见"
            else:
                note = "顶层聚合/别名或按需诊断信号"
            out.append("| `%s` | %d | `%s` | %s |" % (name, w, fn, note))
    else:
        out.append("（无）")
    out.append("")
    out.append("## 五、判据 ↔ 探针索引（人工维护）")
    out.append("")
    out.append("| 判据 | 依赖探针/计数 |")
    out.append("|---|---|")
    for a, b in CRIT_MAP:
        out.append("| %s | %s |" % (a, b))
    out.append("")
    out.append("## 六、配置变体与已知裁剪（口径，非缺陷）")
    out.append("")
    out.append("| 位流轮次 | ILA 配置 | 说明 |")
    out.append("|---|---|---|")
    out.append("| round3b `02F7153A` | ILA0 110b / ILA3 152b / ILA5 82b（tdata64+probe5=7b），3 核 | 写流首拍全面取证版 |")
    out.append("| round3c-diag `9852016C` | ILA0 110b / ILA3 **63b**（裁 stall/len_err/mem2）/ ILA5 **47b**（tdata32+probe5=4b） | 为 300MHz 时序余量裁剪的诊断版（S6/S10 计数不可用） |")
    out.append("| round3d `F6012BA0`（验收） | ILA0 110b / ILA3 **152b 全量** / ILA5 47b；ILA4 整核跳过 | 本清单主源；S6/S10 判据仪器齐 |")
    out.append("| 全部轮次 | `u_ila_4`（lite_regs `dbg_o[35:0]` @100MHz） | round3c/round3d 均 `R3C_SKIP_ILA4=1` 跳过（省时序余量；lite 总线直证暂缺） |")
    out.append("")
    txt = "\n".join(out) + "\n"

    if check:
        print("W6_PRJ11_CHECK: ILA=%d 挂载=%d bit 声明=%d 未挂=%d"
              % (len(cores), tot, len(decl), len(unattached)))
        return 2 if unattached else 0

    d = os.path.dirname(out_path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    io.open(out_path, "w", encoding="utf-8", newline="\n").write(txt)
    print("W6_PRJ11_INVENTORY_OK:", out_path)
    print("  ILA=%d  挂载=%d bit  声明=%d  未挂=%d"
          % (len(cores), tot, len(decl), len(unattached)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
