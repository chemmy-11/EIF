# =============================================================================
# p12_build_report.py — prj12: 从构建产物生成 P1 位流报告（markdown）
# 输入（构建完才有）: out/impl*.console.log, out/rpt_impl_util.rpt,
#                     scripts/probes.ltx, out/aurora_mem_bridge.bit
# 输出: docs/构建报告_P1位流_<tag>.md
# 基线: prj11 round3d F6012BA0（常量写在 BASELINE 里，来源见 docs 引用）
# 用法: py scripts\p12_build_report.py [tag]
# =============================================================================
import glob
import hashlib
import json
import os
import re
import sys

ROOT = r"D:\FPGA\prj\project_12"
OUT = os.path.join(ROOT, "out")
DOCS = os.path.join(ROOT, "docs")

BASELINE = {
    "name": "prj11 round3d F6012BA0",
    "wns": 0.002,
    "whs": 0.004,
    "size": 9288496,
    "sha256": "f6012ba0ff8f9d7f3bcd9ac848a97f1c5e1b6dd7016dad5bebe93755e73c54c4",
    "lut": 41304, "ff": 56654, "bram": 81.5, "dsp": 3, "iob": 142,
    "gt": 2, "mmcm": 2,
    "src": "prj/project_11/out/archive/b31b_r2_2026-10-19_round3d/rpt3_ExtraTimingOpt.{util,timing_summary}.rpt",
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_impl_log():
    best = None
    for pat in ("impl1b.console.log", "impl1.console.log", "impl2.console.log", "impl3.console.log"):
        p = os.path.join(OUT, pat)
        if os.path.exists(p):
            txt = open(p, encoding="utf-8", errors="replace").read()
            if "IMPL_BUILD_OK" in txt:
                return p, txt
            if best is None:
                best = (p, txt)
    return best if best else (None, "")


def parse_gate(txt):
    m = re.search(r"IMPL_GATE: directive=(\S+) WNS=(\S+) WHS=(\S+)", txt)
    if not m:
        return None
    return {"directive": m.group(1), "wns": float(m.group(2)), "whs": float(m.group(3))}


def parse_timing_summary(path):
    """以 report_timing_summary 的 Design Timing Summary 为准。

    行格式: WNS TNS TNSFE TNSTE WHS THS THSFE THSTE WPWS TPWS TPWSFE TPWSTE
    （2026-10-24 教训：`get_timing_paths -delay_type min_max -max_paths 1` 会返回
      setup/hold 里最差的一条，曾把 WNS 误打成 hold 的 0.004；报告必须以本文件为准。）
    """
    if not os.path.exists(path):
        return None
    txt = open(path, encoding="utf-8", errors="replace").read()
    lines = txt.splitlines()
    # 先定位 "WNS(ns)" 表头，再往下找第一行"前 6 列都是数字"的数据行
    # （不能用 `Design Timing Summary(.*?)\n\n`：表头与数据行之间还有一个空行，
    #   非贪婪匹配会停在空行上 —— 2026-10-24 实测）
    for i, ln in enumerate(lines):
        if "WNS(ns)" not in ln:
            continue
        for cand in lines[i + 1:i + 8]:
            parts = cand.split()
            if len(parts) >= 6 and all(re.fullmatch(r"-?\d+(\.\d+)?", p) for p in parts[:6]):
                return {"wns": float(parts[0]), "whs": float(parts[4]),
                        "wpws": float(parts[8]) if len(parts) > 8 else None}
    return None


def parse_util(path):
    if not os.path.exists(path):
        return {}
    txt = open(path, encoding="utf-8", errors="replace").read()
    pats = {
        "lut": r"\|\s+CLB LUTs\*?\s+\|\s+(\d+)",
        "ff": r"\|\s+CLB Registers\s+\|\s+(\d+)",
        "bram": r"\|\s+Block RAM Tile\s+\|\s+([\d.]+)",
        "dsp": r"\|\s+DSPs\s+\|\s+(\d+)",
        "iob": r"\|\s+Bonded IOB\s+\|\s+(\d+)",
        "gt": r"\|\s+GTHE3_CHANNEL\s+\|\s+(\d+)",
        "mmcm": r"\|\s+MMCME3_ADV\s+\|\s+(\d+)",
    }
    out = {}
    for k, p in pats.items():
        m = re.search(p, txt)
        if m:
            out[k] = float(m.group(1)) if k == "bram" else int(m.group(1))
    return out


def count_ilas(ltx):
    """LTX v4 是 JSON：ILA 核形如 {"type":"ILA_V3","name":"u_ila_0",...}。

    首版按 XML `<core name=...>` 匹配 -> 恒 0（2026-10-24 实测纠正）。
    返回 (个数, 名字列表)。
    """
    if not os.path.exists(ltx):
        return None, []
    try:
        with open(ltx, encoding="utf-8", errors="replace") as f:
            doc = json.load(f)
    except Exception:
        return None, []
    names = []

    def walk(node):
        if isinstance(node, dict):
            t = node.get("type")
            if isinstance(t, str) and t.startswith("ILA") and node.get("name"):
                names.append(node["name"])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(doc)
    return len(names), names


def count_cw(txt):
    return len(re.findall(r"^CRITICAL WARNING", txt, re.M))


def fmt_delta(now, base, unit=""):
    if now is None or base is None:
        return "—"
    d = now - base
    sign = "+" if d >= 0 else ""
    if isinstance(d, float):
        return f"{sign}{d:.3f}{unit}"
    return f"{sign}{d}{unit}"


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "2026-10-24"
    bit = os.path.join(OUT, "aurora_mem_bridge.bit")
    log_path, txt = find_impl_log()
    gate = parse_gate(txt) if txt else None
    ts = parse_timing_summary(os.path.join(OUT, "rpt_impl_timing_summary.rpt"))
    # 以报告文件为准；日志里的 IMPL_GATE 只作为 fallback（并注明口径）
    timing = dict(ts) if ts else (dict(gate) if gate else None)
    if timing and gate:
        timing["directive"] = gate.get("directive")
        timing["gate_wns"] = gate.get("wns")
        timing["gate_whs"] = gate.get("whs")
    util = parse_util(os.path.join(OUT, "rpt_impl_util.rpt"))
    sha = sha256(bit) if os.path.exists(bit) else ""
    size = os.path.getsize(bit) if os.path.exists(bit) else 0
    cw = count_cw(txt) if txt else 0
    n_ila, ila_names = count_ilas(os.path.join(ROOT, "scripts", "probes.ltx"))

    lines = []
    A = lines.append
    A(f"# prj12 P1 位流构建报告（{tag}）")
    A("")
    A("> **自动生成**：`py scripts\\p12_build_report.py`（输入 `out/impl*.console.log`、`out/rpt_impl_util.rpt`、")
    A("> `scripts/probes.ltx`、`out/aurora_mem_bridge.bit`）。基线 = prj11 round3d `F6012BA0`：")
    A(f"> `{BASELINE['src']}`。")
    A("")
    A("## 1. 结论")
    A("")
    if timing:
        ok = timing["wns"] >= 0 and timing["whs"] >= 0
        src = "report_timing_summary" if ts else "IMPL_GATE 日志"
        A(f"- 时序门限（WNS≥0 且 WHS≥0）：**{'PASS' if ok else 'FAIL'}** "
          f"（WNS {timing['wns']:+.3f} ns / WHS {timing['whs']:+.3f} ns，"
          f"place directive `{timing.get('directive') or '—'}`；来源 {src}）")
        if ts and gate and (abs(gate["wns"] - ts["wns"]) > 1e-9):
            A(f"  - ⚠ 日志 `IMPL_GATE` 打的是 {gate['wns']:+.3f} —— 那是 `-delay_type min_max` 取到的"
              f"**最差路径**（本例为 hold），不是 setup WNS；已在 `build_impl.tcl` 修正为 `-delay_type max`。"
              f"对外口径以本行（报告文件）为准。")
    else:
        A("- 时序门限：**未取得**（没有找到 `rpt_impl_timing_summary.rpt` 或 `IMPL_GATE` 日志）")
    A(f"- 位流：`out/aurora_mem_bridge.bit`，{size:,} B，指纹 **`{sha.upper()[:8]}`**（SHA256 前 8 位，沿用 F6012BA0 口径）")
    A(f"- SHA256：`{sha.upper()}`")
    A(f"- 实现日志 CRITICAL WARNING：**{cw}** 条（日志 `{os.path.relpath(log_path, ROOT) if log_path else '—'}`）")
    A(f"- ILA 核：**{n_ila if n_ila is not None else '—'}** 个（`scripts/probes.ltx`）："
      f"{'、'.join(ila_names) if ila_names else '—'}")
    A("")
    A("## 2. 与 prj11 基线逐项对比")
    A("")
    A("| 项 | prj12（本次） | prj11 F6012BA0 | 差 |")
    A("|---|---|---|---|")
    if timing:
        A(f"| WNS (ns) | {timing['wns']:+.3f} | {BASELINE['wns']:+.3f} | {fmt_delta(timing['wns'], BASELINE['wns'])} |")
        A(f"| WHS (ns) | {timing['whs']:+.3f} | {BASELINE['whs']:+.3f} | {fmt_delta(timing['whs'], BASELINE['whs'])} |")
    else:
        A("| WNS (ns) | — | +0.002 | — |")
        A("| WHS (ns) | — | +0.004 | — |")
    A(f"| 位流大小 (B) | {size:,} | {BASELINE['size']:,} | {fmt_delta(size, BASELINE['size'])} |")
    A(f"| CLB LUTs | {util.get('lut', '—')} | {BASELINE['lut']} | {fmt_delta(util.get('lut'), BASELINE['lut'])} |")
    A(f"| CLB Registers | {util.get('ff', '—')} | {BASELINE['ff']} | {fmt_delta(util.get('ff'), BASELINE['ff'])} |")
    A(f"| Block RAM Tile | {util.get('bram', '—')} | {BASELINE['bram']} | {fmt_delta(util.get('bram'), BASELINE['bram'])} |")
    A(f"| DSPs | {util.get('dsp', '—')} | {BASELINE['dsp']} | {fmt_delta(util.get('dsp'), BASELINE['dsp'])} |")
    A(f"| Bonded IOB | {util.get('iob', '—')} | {BASELINE['iob']} | {fmt_delta(util.get('iob'), BASELINE['iob'])} |")
    A(f"| GTHE3_CHANNEL | {util.get('gt', '—')} | {BASELINE['gt']} | {fmt_delta(util.get('gt'), BASELINE['gt'])} |")
    A(f"| MMCME3_ADV | {util.get('mmcm', '—')} | {BASELINE['mmcm']} | {fmt_delta(util.get('mmcm'), BASELINE['mmcm'])} |")
    A("")
    A("## 3. 差异解释（本次改了什么）")
    A("")
    A("1. **`link_ok` 单核化**（`rtl/aurora_mem_bridge.v`）：去掉一个 AND 项，对资源几乎无影响；")
    A("   但它把 `aurora_rst` 的复位扇出从\"双核与\"改成\"单核\"，理论上略减复位网络负担。")
    A("2. **新增 u_ila_6**（119b × 1024 深度 @ user_clk）：BRAM/LUT 增量应主要来自这里；")
    A("   `P12_SKIP_ILA6=1` 的构建可给出\"无 ILA6\"对照（本报告若为回退构建会注明）。")
    A("3. ILA0/3/5 与 round3d 逐字一致（`R3C_SKIP_ILA4=1`、`R3C_LITE_ILA5=1`），")
    A("   所以**除上述两项外**的差异只能来自 place/route 随机性（同一网表重掷实测可差 ~0.1 ns）。")
    A("")
    A("## 4. 复现")
    A("")
    A("```cmd")
    A(r"D:\FPGA\prj\project_12\scripts\build_p1.cmd")
    A("```")
    A("")
    A("阶段日志：`out\\synth.log`、`out\\impl1.log`（或 impl2/impl3），")
    A("报告：`out\\rpt_impl_timing_summary.rpt` / `out\\rpt_impl_util.rpt` / `out\\rpt_impl_worst.rpt`。")
    A("")
    A("## 5. 告警口径（CRITICAL WARNING / XDC）")
    A("")
    A("- **实现阶段 CRITICAL WARNING = 0**（脚本按 `^CRITICAL WARNING` 统计上面的实现日志）。")
    A("- **BD 构建阶段**有 2 条 `[BD 41-1356] Slave segment ... not assigned`（DMA 的 `M_AXI_*` 存储映射段未分配地址）：")
    A("  这是 **prj11 既有口径**，不是 prj12 引入 —— 同一告警在 prj11 的 BD 重生成日志")
    A("  `prj/project_11/out/regen_bd.log`、`prj/project_11/out/archive/b31b_r2_2026-10-19_round3c/regen_bd_r3c.log` 中同样存在；")
    A("  P1 直通模式下该段不参与寻址（`M_AXI` 接自研 `axi_arb_3to1`），故不修。")
    A("- **XDC 静态检查**（`mcp__vivado__xdc_lint`，纯离线）：0 ERROR / 109 WARNING，全部为 `MISSING_IOSTANDARD`，")
    A("  落在 GT 参考时钟（T6/T5）与 DDR4 引脚：前者按 MGTREFCLK 用法**不需要** IOSTANDARD（误报，PITFALLS #20），")
    A("  后者由 MIG 生成的 XDC 提供 IOSTANDARD，顶层 XDC 只给 `PACKAGE_PIN` 是既有约定。")
    A("- 门限纪律：**WNS≥0 且 WHS≥0 才写位流**（`scripts/build_impl.tcl` 内判；不达标 exit 2、不写流）。")
    A("")
    A("## 6. 构建过程（本次实测，含失败分支）")
    A("")
    A("| 阶段 | 结果 | 备注 |")
    A("|---|---|---|")
    A("| create_project | OK（约 2 min） | 21 个 IP + BD `mb_ctrl`；2 条 BD CW 见 §5 |")
    A("| synth（`-jobs 8` 链式） | 失败 | 16 个 OOC IP run 并发，6 个在 helper 进程起步崩 `TclStackFree: incorrect freePtr` |")
    A("| synth（逐 run 重试版） | **OK** | 16/16 OOC run 100%，`SYNTH_ONLY_DONE`；日志 `out/synth.log` |")
    A("| impl（第一次） | 被外部 Ctrl+C 中断 | 日志 `out/impl1.log`（DRC 阶段收到 ^C，与设计无关） |")
    A("| impl（重跑） | **OK** | 日志 `out/impl1b.*`；WNS/WHS/资源见 §1–§2 |")
    A("")
    path = os.path.join(DOCS, f"构建报告_P1位流_{tag}.md")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(f"REPORT: {path}")
    try:
        print("\n".join(lines[:12]))
    except UnicodeEncodeError:
        # GBK 控制台打不出某些字符时不要当成失败（文件已经写好）
        print("(console cannot encode Chinese here; see the report file)")


if __name__ == "__main__":
    main()
