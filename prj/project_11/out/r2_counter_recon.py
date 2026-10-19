#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""r2_counter_recon.py -- prj11 R2(B3-2) 双桥计数对账 / ILA 前后差分 / 判据工具自检

背景
----
R2 把桥①(HAS_DMA=1, u_mem)的写路径从 axi4_master_bridge 硬件写 FSM 换成 AXI DMA S2MM;
桥②(HAS_DMA=0, u_mem2)写+读两条硬件路径一个字节都不许动。R2 的验收判据③是
"双桥计数对账闭合(口径同 J4: mem/mem2 各自 wm=wr_frm=rd_frm、错误计数全 0)",
并新增两项可观测量: 每帧 S2MM 写请求 WR_REQ/WR_DBG(经 'U' 探针) 与 S2MM 计数探针。

本工具读 Vivado ILA CSV(r2_ilacap.tcl 导出的 PRE/POST 快照), 给出:
  * --mode delta (S6): ping×N 窗口内的前后差分
       桥①(mem)  wm / wr_frm / rd_frm 各 +N
       桥②(mem2) rd_frm +N 且 ost 前后均 0   <- 桥② read 路径未被动过的直接证据
       另: 全局错误计数 dbg_wr_fault 前后均 0; timeout 在 ILA 不可观测(仅 INFO, 不硬判)
  * --mode recon (S10): J4 口径累计对账表
       每桥 wm == wr_frm == rd_frm; ost == 0; 错误计数按"可观测项"判 0
       错误口径(Lead 2026-10-17 v1.2 终版):
         mem  : stall/len_err 硬判 0; bresp 恒 0 **仅 INFO**(S2MM 写路径 IP 内部 BRESP 不可见)
         mem2 : 本轮 RTL 未动且无 stall/len_err/bresp ILA 探针 ⇒ **仅 INFO**(不可观测);
                只硬判 wm=wr_frm=rd_frm + ost=0
         全局: dbg_wr_fault(ILA0@user) 硬判 0; dbg_wr_timeout **未挂 ILA 且无 Lite 读回路径**
                (+0x40/+0x44 不含 stat_wr_timeout) ⇒ **仅 INFO**(不可观测)
       替代观测(不可硬判): ILA3 dbg_s2mm_state 编码 + dbg_wr_fault + 'U' 的 wreq/wdbg/s2sr +
                ro_wm 是否推进
  * --mode selftest: 正/负对照自检判据工具本身(AGENTS 坑 #56: 判据工具自身也是被测件;
       坑 #43: 每个负向 FAIL 必须指认到具体判据行)。
  * --check-tcl PATH: Tcl 结构完整性检查(引号/花括号/方括号闭合 + 行尾 # 提示 + 非 ASCII 字节)。
       本机无 tclsh 时的替代自检; 权威判据仍是 CI 的 tclsh info-complete(AGENTS §十二)。

R2 新探针布局(round2b 2026-10-18 ILA 探针集裁剪后; 已与 build_synth_only.tcl/build_debug.tcl 机械对齐)
--------------------------------------------------------------------------------------------
  本轮变动(round2b, 目的=省 300MHz 布线/资源余量, 不改 RTL):
    * ILA1@eth_rxc / ILA2@user_clk_b **整核移除** —— R2 S0–S11 判据不使用, 本工具对缺失不报错。
    * ILA0@user probe0 374→**92 bit**: dbg_mem_u_wr[16]/u_rd[16]/u_drop[16]/dbg_mem_rden(1)/
      dbg_mem_ost_s[9]/dbg_mem2_u_wr[16]/dbg_mem2_u_rd[16]/dbg_s2mm_reqpend(1)/dbg_wr_fault(1);
      probe1 发射字节流 9b 保留不变(S8c 判据用, 本工具不解析)。
    * ILA3@ui probe0 184→**152 bit**: dbg_calib + mem wm/wr_frm/rd_frm/stall/len_err/ost +
      mem2 wm/wr_frm/rd_frm/ost + dbg_s2mm_state[3]/tvalid/tready。
    * **裁掉**: dbg_mem_bresp / dbg_mem_wslot / dbg_mem_rslot ⇒ 本轮不可观测(INFO/NOT_OBTAINED, 不判 FAIL)。
  dbg_wr_timeout 未挂 ILA(有意省 300MHz ILA3 余量; R1/W6 教训: 300MHz 域加 96b 曾 WNS -1.142);
  stat_wr_timeout 是桥内 16b 计数器且**无 Lite 读回路径** ⇒ 上板不可观测, 仅 INFO。
  可观测替代物: ILA3 dbg_s2mm_state(0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT)
  + dbg_wr_fault(ILA0) + 'U' 的 wreq/wdbg/s2sr + ro_wm 是否推进。
  ⇒ 本工具对 ui/user 两份 CSV 做**列合并**后再找全局错误计数与 R2 观测探针;
    桥计数语义只取 ui CSV(避免 user 域旧探针同名混淆)。

Vivado ILA CSV 口径
-------------------
第 1 行 = 探针名(如 `dbg_mem_wm[15:0]`), 第 2 行 = 进制(HEX/UNSIGNED/BINARY),
第 3..N 行 = 采样(默认 2048)。计数器是累计量: 一次 trigger_now 快照的采样窗口覆盖
触发前历史, 因此"当前值"取**最后一行**; 同时打印 first/min/max 便于识别窗口内变化。
(与 out\\jb31b_ilacnt_parse.py 同源口径, 但增加 radix 感知与多探针语义映射)

判据行(供 r2_board.ps1 解析; 退出码 0=PASS / 1=FAIL / 2=NOT_OBTAINED / 3=用法错误)
  R2_COUNTER_RECON: PASS|FAIL|NOT_OBTAINED <reason>
  R2_ILA_DELTA:     PASS|FAIL|NOT_OBTAINED <reason>
  R2_TCL_CHECK:     PASS|FAIL|WARN <path> <detail>
  R2_SELFTEST:      PASS|FAIL <n>/<m>

用法示例
--------
  py r2_counter_recon.py --mode delta  --ui-pre  <pre.csv> --ui-post <post.csv> [--user-pre <p> --user-post <q>] [--expect-delta 4]
  py r2_counter_recon.py --mode recon  --ui-post <post.csv> [--user-post <q>] [--json-out out.json]
  py r2_counter_recon.py --mode selftest
  py r2_counter_recon.py --check-tcl out\\r2_ilacap.tcl
"""
import argparse
import csv
import json
import os
import re
import sys
import tempfile

# ---------------------------------------------------------------------------
# 语义映射: 字段 -> 候选列名(按顺序取第一个命中)
# 依据: prj11 scripts/build_debug.tcl ILA3@ui_clk 探针清单 + R2 DESIGN §8 新增探针
# ---------------------------------------------------------------------------
BRIDGE_SEM = {
    "mem": {
        "label": "u_mem (write=S2MM/DMA, read=MM2S/DMA)",
        "wm":     ["dbg_mem_wm"],
        "wr_frm": ["dbg_mem_wr_frm"],
        "rd_frm": ["dbg_mem_rd_frm"],
        "ost":    ["dbg_mem_ost"],
        "stall":  ["dbg_mem_stall"],
        "len_err": ["dbg_mem_len_err"],
        "bresp":  ["dbg_mem_bresp"],
    },
    "mem2": {
        "label": "u_mem2 (write/read=硬件路径, R2 禁改)",
        "wm":     ["dbg_mem2_wm"],
        "wr_frm": ["dbg_mem2_wr_frm"],
        "rd_frm": ["dbg_mem2_rd_frm"],
        "ost":    ["dbg_mem2_ost"],
        "stall":  ["dbg_mem2_stall"],
        "len_err": ["dbg_mem2_len_err"],
        "bresp":  ["dbg_mem2_bresp"],
    },
}

# round2b(2026-10-18) ILA 探针集裁剪(省 300MHz 布线/资源余量, 不改 RTL):
#   ILA1@eth_rxc / ILA2@user_clk_b 整核移除(R2 S0–S11 判据不使用); ILA0 probe0 374→92b,
#   ILA3 probe0 184→152b; 裁掉 dbg_mem_bresp / dbg_mem_wslot / dbg_mem_rslot。
#   判据边界: 被裁探针列缺失 ⇒ INFO/NOT_OBTAINED(判据未取得≠失败, AGENTS §6a), 不判 FAIL。
ROUND2B_TRIMMED = ["dbg_mem_bresp", "dbg_mem_wslot", "dbg_mem_rslot"]
ROUND2B_NOTE = ("round2b ILA 裁剪: ILA1/ILA2 整核移除(判据不用, 缺失不报错); "
                "dbg_mem_bresp/wslot/rslot 未挂 ⇒ INFO/NOT_OBTAINED, 不判 FAIL")

# 全局 R2 新错误计数(与桥实例无关; 有探针就硬判 0, 没有则 INFO)
#   Lead 2026-10-17 v1.2 终版: 错误硬判看 len_err/stall(桥①) 与 dbg_wr_fault(ILA0@user);
#   dbg_wr_timeout 未挂 ILA 且 stat_wr_timeout 无 Lite 读回路径(+0x40/+0x44 不含) ⇒ 不可观测仅 INFO。
GLOBAL_ERR_SEM = {
    "wr_timeout": ["dbg_wr_timeout", "ro_stat_wr_timeout", "stat_wr_timeout"],
    "wr_fault":   ["dbg_wr_fault", "ro_wr_fault", "stat_wr_fault"],
}

# R2 S2MM 观测探针(仅打印, 不参与硬判; 存在性用于 S6 证据充分性说明 / -RequireR2Probes)
#   位置(已与最终 build_synth_only.tcl / build_debug.tcl 机械对齐, Lead v1.2 冻结):
#     ILA3 @ui_clk = dbg_s2mm_state[2:0] / dbg_s2mm_tvalid / dbg_s2mm_tready
#     ILA0 @user   = dbg_s2mm_reqpend / dbg_wr_fault
#   注: dbg_wr_timeout 未挂 ILA 且无 Lite 读回路径 ⇒ ILA 侧 timeout 判据不可取得, 本工具记 INFO;
#       错误硬判实际靠 len_err/stall(桥①) + dbg_wr_fault(ILA0@user); 桥① bresp 恒 0 仅 INFO。
R2_INFO_SEM = {
    "s2mm_state":    ["dbg_s2mm_state"],
    "s2mm_tvalid":   ["dbg_s2mm_tvalid"],
    "s2mm_tready":   ["dbg_s2mm_tready"],
    "s2mm_reqpend":  ["dbg_s2mm_reqpend", "dbg_s2mm_req_pend"],
    "wr_fault_user": ["dbg_wr_fault"],
}

# dbg_s2mm_state 状态编码(Lead 2026-10-17 冻结口径; 仅用于 INFO 打印, 不参与硬判)
S2MM_STATE_DECODE = {
    0: "IDLE", 1: "WAITGO", 2: "STREAM", 3: "PUSH", 4: "WAITDONE", 5: "DRAIN", 6: "HALT",
}
S2MM_STATE_LEGEND = "dbg_s2mm_state 编码: 0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT"

# J4 口径(写进输出, 供证据引用)
J4_CALIBER = (
    "J4 口径: 每桥独立对账 wm==wr_frm==rd_frm(累计计数相等) + ost(在途)归零 + 错误计数全 0; "
    "两桥分别判, 不得用一桥的相等掩盖另一桥的失配 (W4/J4 原始判据)。"
)


# ---------------------------------------------------------------------------
# CSV 解析
# ---------------------------------------------------------------------------
def _parse_cell(cell, radix):
    """按 radix 行解析单个 cell; 解析失败返回 None。"""
    v = (cell or "").strip()
    if v == "" or v.upper() in ("X", "-", "N/A"):
        return None
    v = v.replace("_", "")
    low = v.lower()
    if low.startswith("0x"):
        return int(v, 16)
    if low.startswith("0b"):
        return int(v[2:], 2)
    r = (radix or "").upper()
    try:
        if r.startswith("HEX"):
            return int(v, 16)
        if r.startswith("BIN"):
            return int(v, 2)
        if r.startswith("UNS") or r.startswith("DEC"):
            return int(v, 10)
    except ValueError:
        return None
    # radix 行缺失/未知: 含 a-f 视为 hex, 否则十进制
    try:
        if re.search(r"[a-fA-F]", v):
            return int(v, 16)
        return int(v, 10)
    except ValueError:
        return None


def read_ila_csv(path):
    """返回 {列名: {"values":[...], "radix":..., "index":i}}; 失败抛 ValueError。"""
    if not os.path.isfile(path):
        raise ValueError("CSV 不存在: %s" % path)
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
        rows = list(csv.reader(f))
    if len(rows) < 2:
        raise ValueError("CSV 行数不足(需表头+radix+采样): %s rows=%d" % (path, len(rows)))
    header = rows[0]
    radix = rows[1]
    data = rows[2:]
    if not data:
        raise ValueError("CSV 无采样行: %s" % path)
    cols = {}
    for i, raw in enumerate(header):
        name = (raw or "").strip()
        if not name:
            continue
        rd = (radix[i] if i < len(radix) else "").strip()
        vals = []
        for row in data:
            if i >= len(row):
                continue
            n = _parse_cell(row[i], rd)
            if n is not None:
                vals.append(n)
        cols[name] = {"index": i, "radix": rd, "values": vals}
    return cols


def col_width(name):
    """从 `name[msb:lsb]` 提取位宽; 无线宽信息返回 32。"""
    m = re.search(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]", name)
    if m:
        return int(m.group(1)) - int(m.group(2)) + 1
    m = re.search(r"\[\s*(\d+)\s*\]\s*$", name)
    if m:
        return 1
    return 32


def find_col(cols, patterns):
    """按候选关键词找列名(不区分大小写, 子串匹配, 取第一个命中)。"""
    names = list(cols.keys())
    for pat in patterns:
        p = pat.lower()
        for n in names:
            if p in n.lower():
                return n
    return None


def stats(cols, name):
    c = cols[name]
    vals = c["values"]
    if not vals:
        return None
    return {
        "col": name,
        "first": vals[0],
        "last": vals[-1],
        "min": min(vals),
        "max": max(vals),
        "n": len(vals),
        "width": col_width(name),
    }


def resolve(cols, sem):
    """把语义表落到实际列上; 返回 {field: stats|None, '_label': ...}。"""
    out = {}
    for field, pats in sem.items():
        if field == "label":
            out["_label"] = pats
            continue
        name = find_col(cols, pats)
        out[field] = stats(cols, name) if name else None
    return out


def resolve_globals(cols):
    out = {}
    for field, pats in GLOBAL_ERR_SEM.items():
        name = find_col(cols, pats)
        out[field] = stats(cols, name) if name else None
    return out


def resolve_r2info(cols):
    out = {}
    for field, pats in R2_INFO_SEM.items():
        name = find_col(cols, pats)
        out[field] = stats(cols, name) if name else None
    return out


def decode_s2mm_state(value):
    """dbg_s2mm_state 编码解码(Lead 2026-10-17 冻结): 0=IDLE 1=WAITGO 2=STREAM 3=PUSH
    4=WAITDONE 5=DRAIN 6=HALT; 未知值原样返回 ?<v>。仅用于 INFO 打印。"""
    if value is None:
        return "n/a"
    if isinstance(value, int) and value in S2MM_STATE_DECODE:
        return S2MM_STATE_DECODE[value]
    return "?%s" % value


def merge_cols(primary, secondary):
    """合并两份 ILA CSV 的列(ui 域 + user 域): primary 优先, 只补 primary 缺的列名。
    R2 v1.1: dbg_wr_fault/dbg_s2mm_reqpend 挂在 ILA0@user, 而桥计数在 ILA3@ui,
    因此全局错误计数与 R2 观测探针必须在合并列上查找。"""
    if not primary:
        return dict(secondary or {})
    if not secondary:
        return dict(primary)
    merged = dict(primary)
    for k, v in secondary.items():
        if k not in merged:
            merged[k] = v
    return merged


def wrap_delta(pre, post, width):
    mod = 1 << width
    return (post - pre) % mod


# ---------------------------------------------------------------------------
# 输出辅助
# ---------------------------------------------------------------------------
def hr(ch="=", n=78):
    return ch * n


def fmt_val(st):
    if st is None:
        return "n/a"
    return str(st["last"])


def fmt_cell(st, width_hint=None):
    if st is None:
        return "-"
    return "%d(first %d/min %d/max %d)" % (st["last"], st["first"], st["min"], st["max"])


def print_table(rows, headers):
    widths = [len(h) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(str(c)))
    line = "  ".join(str(h).ljust(widths[i]) for i, h in enumerate(headers))
    print("  " + line)
    print("  " + "  ".join("-" * widths[i] for i in range(len(headers))))
    for r in rows:
        print("  " + "  ".join(str(c).ljust(widths[i]) for i, c in enumerate(r)))


# ---------------------------------------------------------------------------
# delta 模式(S6)
# ---------------------------------------------------------------------------
def judge_delta(ui_pre_cols, ui_post_cols, user_pre_cols=None, user_post_cols=None,
                expect_delta=4):
    """返回 (verdict, reason, detail_dict)。verdict ∈ PASS/FAIL/NOT_OBTAINED。"""
    detail = {"expect_delta": expect_delta}
    print(hr())
    print("S6 ILA 前后差分判据 (ping×%d 窗口; 桥②读路径未动的直接证据)" % expect_delta)
    print(hr())
    print("公式: delta = (post.last - pre.last) mod 2^width; 快照取最后一行=当前累计值")
    print()

    pre = resolve(ui_pre_cols, BRIDGE_SEM["mem"])
    post = resolve(ui_post_cols, BRIDGE_SEM["mem"])
    pre2 = resolve(ui_pre_cols, BRIDGE_SEM["mem2"])
    post2 = resolve(ui_post_cols, BRIDGE_SEM["mem2"])
    ui_pre_merged = merge_cols(ui_pre_cols, user_pre_cols)
    ui_post_merged = merge_cols(ui_post_cols, user_post_cols)
    gpre = resolve_globals(ui_pre_merged)
    gpost = resolve_globals(ui_post_merged)
    r2pre = resolve_r2info(ui_pre_merged)
    r2post = resolve_r2info(ui_post_merged)

    detail["mem"] = {}
    detail["mem2"] = {}
    rows = []
    missing = []
    fails = []

    # ---- 桥①(mem): wm/wr_frm/rd_frm 各 +expect_delta ----
    for field in ("wm", "wr_frm", "rd_frm"):
        a = pre.get(field)
        b = post.get(field)
        rec = {"pre": a["last"] if a else None, "post": b["last"] if b else None,
               "delta": None, "expect": expect_delta, "ok": False}
        if a is None or b is None:
            missing.append("mem.%s" % field)
        else:
            d = wrap_delta(a["last"], b["last"], a["width"])
            rec["delta"] = d
            rec["ok"] = (d == expect_delta)
            if not rec["ok"]:
                fails.append("mem.%s delta=%d (期望 +%d; pre=%d post=%d)"
                             % (field, d, expect_delta, a["last"], b["last"]))
        rows.append(["mem", field, fmt_val(a), fmt_val(b),
                     ("+" + str(rec["delta"])) if rec["delta"] is not None else "n/a",
                     "+%d" % expect_delta, "PASS" if rec["ok"] else "FAIL"])
        detail["mem"][field] = rec

    # ---- 桥① ost: 前后均 0(Lead 裁决: 仍硬判 0) ----
    a_ost = pre.get("ost")
    b_ost = post.get("ost")
    ost_ok = (a_ost is not None and b_ost is not None and a_ost["last"] == 0 and b_ost["last"] == 0)
    if a_ost is None or b_ost is None:
        missing.append("mem.ost")
    elif not ost_ok:
        fails.append("mem.ost 非 0 (pre=%s post=%s, 期望前后均 0)"
                     % (fmt_val(a_ost), fmt_val(b_ost)))
    rows.append(["mem", "ost", fmt_val(a_ost), fmt_val(b_ost), "-", "0/0",
                 "PASS" if ost_ok else "FAIL"])
    detail["mem"]["ost"] = {"pre": a_ost["last"] if a_ost else None,
                            "post": b_ost["last"] if b_ost else None, "ok": ost_ok}

    # ---- 桥②(mem2): rd_frm +expect_delta, ost 前后均 0 ----
    for field, expect in (("rd_frm", expect_delta), ("ost", 0)):
        a = pre2.get(field)
        b = post2.get(field)
        rec = {"pre": a["last"] if a else None, "post": b["last"] if b else None,
               "delta": None, "expect": expect, "ok": False, "kind": "delta"}
        if field == "ost":
            rec["kind"] = "zero_both"
            if a is None or b is None:
                missing.append("mem2.%s" % field)
            else:
                rec["delta"] = wrap_delta(a["last"], b["last"], a["width"])
                rec["ok"] = (a["last"] == 0 and b["last"] == 0)
                if not rec["ok"]:
                    fails.append("mem2.ost 非 0 (pre=%d post=%d, 期望前后均 0)"
                                 % (a["last"], b["last"]))
            rows.append(["mem2", field, fmt_val(a), fmt_val(b),
                         ("+" + str(rec["delta"])) if rec["delta"] is not None else "n/a",
                         "0/0", "PASS" if rec["ok"] else "FAIL"])
        else:
            if a is None or b is None:
                missing.append("mem2.%s" % field)
            else:
                d = wrap_delta(a["last"], b["last"], a["width"])
                rec["delta"] = d
                rec["ok"] = (d == expect)
                if not rec["ok"]:
                    fails.append("mem2.%s delta=%d (期望 +%d; pre=%d post=%d)"
                                 % (field, d, expect, a["last"], b["last"]))
            rows.append(["mem2", field, fmt_val(a), fmt_val(b),
                         ("+" + str(rec["delta"])) if rec["delta"] is not None else "n/a",
                         "+%d" % expect, "PASS" if rec["ok"] else "FAIL"])
        detail["mem2"][field] = rec

    print_table(rows, ["bridge", "field", "pre(last)", "post(last)", "delta", "expect", "verdict"])
    print()

    # ---- R2 新计数(时间窗内必须为 0) ----
    print("R2 新计数(故障/超时):")
    grows = []
    r2_fails = []
    r2_missing = []
    for field, expect_zero in (("wr_timeout", 0), ("wr_fault", 0)):
        a = gpre.get(field)
        b = gpost.get(field)
        ok = (a is not None and b is not None and a["last"] == 0 and b["last"] == 0)
        if a is None or b is None:
            note = ("缺失(不可观测: ILA 无该探针且 stat_wr_timeout 无 Lite 读回路径; 仅 INFO)"
                    if field == "wr_timeout" else "缺失(探针未挂/ltx 不配套)")
            grows.append([field, "n/a", "n/a", "-", note])
            r2_missing.append(field)
        else:
            grows.append([field, fmt_val(a), fmt_val(b), "0/0", "PASS" if ok else "FAIL"])
            if not ok:
                r2_fails.append("%s 非 0 (pre=%s post=%s)" % (field, fmt_val(a), fmt_val(b)))
    print_table(grows, ["R2 计数", "pre(last)", "post(last)", "expect", "verdict"])
    print()

    # ---- R2 S2MM 观测探针(仅打印, 供证据充分性判断) ----
    print("R2 S2MM 观测探针(INFO, 不参与硬判):")
    print("  " + ROUND2B_NOTE)
    print("  " + S2MM_STATE_LEGEND)
    r2info_rows = []
    for field in R2_INFO_SEM.keys():
        a = r2pre.get(field)
        b = r2post.get(field)
        if a is None and b is None:
            r2info_rows.append([field, "-", "-", "缺失"])
        else:
            note = "有变化" if (a and b and a["last"] != b["last"]) else "稳态"
            if field == "s2mm_state":
                note = "=" + decode_s2mm_state(a["last"] if a else None) + "->" + decode_s2mm_state(b["last"] if b else None)
            r2info_rows.append([field, fmt_val(a), fmt_val(b), note])
    print_table(r2info_rows, ["probe", "pre(last)", "post(last)", "note"])
    print()

    # ---- user 域(可选): 桥② user 侧 wr/rd ----
    if user_pre_cols and user_post_cols:
        urows = []
        for field, pats in (("u_wr", ["dbg_mem2_u_wr"]), ("u_rd", ["dbg_mem2_u_rd"])):
            na = find_col(user_pre_cols, pats)
            nb = find_col(user_post_cols, pats)
            if na and nb:
                a = stats(user_pre_cols, na)
                b = stats(user_post_cols, nb)
                d = wrap_delta(a["last"], b["last"], a["width"])
                urows.append([field, a["last"], b["last"], "+%d" % d])
            else:
                urows.append([field, "n/a", "n/a", "n/a"])
        print("user 域附加证据(桥② u_wr/u_rd; INFO):")
        print_table(urows, ["field", "pre(last)", "post(last)", "delta"])
        print()
    else:
        print("user 域附加证据: 未提供 --user-pre/--user-post (可选)")
        print()

    if r2_fails:
        fails.extend(r2_fails)
    if fails:
        reason = "; ".join(fails)
        print("判据明细(FAIL): " + reason)
        return "FAIL", reason, detail
    if missing:
        reason = "缺探针列: " + ", ".join(missing) + " (ltx/位流不配套或探针未挂; 判据未取得)"
        print("判据明细(NOT_OBTAINED): " + reason)
        return "NOT_OBTAINED", reason, detail
    reason = ("mem wm/wr_frm/rd_frm 各 +%d, mem ost=0; mem2 rd_frm +%d, mem2 ost 前后 0"
              % (expect_delta, expect_delta))
    reason += ("; R2 timeout/fault 0" if not r2_missing
               else "; R2 timeout/fault 探针缺失(%s)未硬判" % ",".join(r2_missing))
    print("判据明细(PASS): " + reason)
    return "PASS", reason, detail


# ---------------------------------------------------------------------------
# recon 模式(S10)
# ---------------------------------------------------------------------------
def judge_recon(ui_cols, user_cols=None, label="post", require_r2_probes=False):
    """J4 口径累计对账; 返回 (verdict, reason, detail)。"""
    detail = {"ui_csv_label": label}
    print(hr())
    print("S10 双桥计数对账 (J4 口径, 累计值)")
    print(hr())
    print(J4_CALIBER)
    print()

    rows = []
    missing = []
    fails = []
    info = []

    g = resolve_globals(merge_cols(ui_cols, user_cols))
    for key in ("mem", "mem2"):
        sem = dict(BRIDGE_SEM[key])
        seg = resolve(ui_cols, sem)
        label_txt = BRIDGE_SEM[key]["label"]
        rec = {"label": label_txt}
        vals = {}
        for field in ("wm", "wr_frm", "rd_frm", "ost", "stall", "len_err", "bresp"):
            st = seg.get(field)
            vals[field] = st["last"] if st else None
            rec[field] = vals[field]
        # 三计数
        trio = [vals["wm"], vals["wr_frm"], vals["rd_frm"]]
        if any(v is None for v in trio):
            missing.append("%s.wm/wr_frm/rd_frm" % key)
            trio_ok = False
            trio_txt = "n/a"
        else:
            trio_ok = (trio[0] == trio[1] == trio[2])
            trio_txt = "相等" if trio_ok else "失配"
            if not trio_ok:
                fails.append("%s 三计数失配 wm=%d wr_frm=%d rd_frm=%d" % (key, trio[0], trio[1], trio[2]))
        # ost 归零(Lead 裁决: 桥①/桥② 均硬判 0)
        if vals["ost"] is None:
            missing.append("%s.ost" % key)
            ost_ok = False
        else:
            ost_ok = (vals["ost"] == 0)
            if not ost_ok:
                fails.append("%s.ost=%d (期望 0)" % (key, vals["ost"]))
        # 错误计数口径(按 R2 Lead 裁决 + 实际 ILA 探针清单):
        #   桥①(mem):  stall/len_err 硬判 0; bresp 在 S2MM 写路径下不可见(S2MM 的 BRESP 不上报) -> 仅 INFO
        #   桥②(mem2): ILA3 只挂了 wm/wr_frm/rd_frm/ost 四个探针(prj10/prj11 build_debug.tcl 实证),
        #              没有 stall/len_err/bresp 探针 -> 不可观测, 记 INFO(不判 NOT_OBTAINED);
        #              若 R2 给 ILA3 新增了这些探针, 则自动升为硬判 0。
        err_ok = True
        for field in ("stall", "len_err"):
            if vals[field] is None:
                if key == "mem":
                    missing.append("%s.%s" % (key, field))
                    err_ok = False
                else:
                    info.append("mem2.%s 无 ILA 探针(不可观测) —— 桥② 错误计数硬判需新增 dbg_mem2_%s 探针"
                                % (field, field))
            elif vals[field] != 0:
                err_ok = False
                fails.append("%s.%s=%d (期望 0)" % (key, field, vals[field]))
        bresp_txt = "n/a"
        if vals["bresp"] is None:
            if key == "mem2":
                bresp_txt = "无探针(INFO)"
                info.append("mem2.bresp 无 ILA 探针(不可观测) —— 若需硬判需新增 dbg_mem2_bresp 探针")
            else:
                # round2b(2026-10-18) 裁掉 dbg_mem_bresp(S2MM 下恒 0, 只作 INFO) ⇒ 缺失记 INFO, 不判 NOT_OBTAINED
                bresp_txt = "无探针(INFO/round2b 裁)"
                info.append("mem.bresp 本轮 round2b ILA 裁剪未挂 dbg_mem_bresp(S2MM 下恒 0) ⇒ INFO, 不判 FAIL/NOT_OBTAINED")
        elif key == "mem2":
            bresp_txt = str(vals["bresp"])
            if vals["bresp"] != 0:
                fails.append("mem2.bresp=%d (期望 0)" % vals["bresp"])
        else:
            bresp_txt = "%d(INFO)" % vals["bresp"]
            if vals["bresp"] != 0:
                info.append("mem.bresp=%d 非 0 —— S2MM 写路径下 BRESP 不可见, 按裁决仅 INFO" % vals["bresp"])
        verdict = "PASS" if (trio_ok and ost_ok and err_ok) else "FAIL"

        def nv(x):
            return "n/a" if x is None else x

        rows.append([key, nv(vals["wm"]), nv(vals["wr_frm"]), nv(vals["rd_frm"]), trio_txt,
                     nv(vals["ost"]), nv(vals["stall"]), nv(vals["len_err"]), bresp_txt, verdict])
        rec.update({"trio_ok": trio_ok, "ost_ok": ost_ok, "err_ok": err_ok, "verdict": verdict})
        detail[key] = rec

    print_table(rows, ["bridge", "wm", "wr_frm", "rd_frm", "三计数", "ost",
                       "stall", "len_err", "bresp", "verdict"])
    print()

    # 全局 R2 错误计数
    grows = []
    glob_observed = {}
    for field in ("wr_timeout", "wr_fault"):
        st = g.get(field)
        if st is None:
            note = ("缺失(不可观测: ILA 无该探针且 stat_wr_timeout 无 Lite 读回路径; 仅 INFO)"
                    if field == "wr_timeout" else "缺失(探针未挂/ltx 不配套)")
            grows.append([field, "缺失", note])
        else:
            ok = (st["last"] == 0)
            grows.append([field, str(st["last"]), "PASS" if ok else "FAIL"])
            glob_observed[field] = ok
            if not ok:
                fails.append("%s=%d (期望 0)" % (field, st["last"]))
            detail.setdefault("globals", {})[field] = {"last": st["last"], "ok": ok}
    print("全局 R2 错误计数(故障/超时):")
    print_table(grows, ["counter", "last", "verdict"])
    print()

    r2i = resolve_r2info(merge_cols(ui_cols, user_cols))
    present = [k for k, v in r2i.items() if v is not None]
    print("R2 S2MM 观测探针存在性: %d/%d %s" %
          (len(present), len(R2_INFO_SEM), ("命中: " + ", ".join(present)) if present else "(无, 旧探针对账不受影响)"))
    detail["r2_probes_present"] = present
    if r2i.get("s2mm_state") is not None:
        st = r2i["s2mm_state"]
        print("  dbg_s2mm_state(last) = %s (raw %s)" % (decode_s2mm_state(st["last"]), st["last"]))
        print("  " + S2MM_STATE_LEGEND)
    for k in ("s2mm_tvalid", "s2mm_tready", "s2mm_reqpend", "wr_fault_user"):
        if r2i.get(k) is not None:
            print("  %s(last) = %s" % (k, r2i[k]["last"]))
    print()
    print("观测能力说明(INFO, 不作判据):")
    print("  - " + ROUND2B_NOTE)
    print("  - 桥① dbg_mem_bresp 在 S2MM 写路径恒 0(IP 内部 BRESP 不可见) ⇒ 仅 INFO; round2b 已裁该探针 ⇒ 缺失亦 INFO")
    print("  - 桥②(HAS_DMA=0, RTL 本轮未动) stall/len_err/bresp 无 ILA 探针 ⇒ 仅 INFO(不可观测)")
    print("  - wslot/rslot(调试槽号) round2b 未挂 ILA ⇒ INFO(判据不使用)")
    print("  - timeout: dbg_wr_timeout 未挂 ILA 且 stat_wr_timeout 无 Lite 读回路径(+0x40/+0x44 不含) ⇒ 仅 INFO")
    print("  - 可观测替代: dbg_s2mm_state/dbg_wr_fault + 'U' 的 wreq/wdbg/s2sr + ro_wm 是否推进")
    print()
    if require_r2_probes and len(present) < len(R2_INFO_SEM):
        missing.append("R2 新探针(db_s2mm_*) 不完整: %d/%d" % (len(present), len(R2_INFO_SEM)))
        print("WARN: --require-r2-probes 打开而 R2 新探针不完整 -> 按判据未取得处理")

    for s in info:
        print("INFO: " + s)
    if info:
        print()

    if fails:
        reason = "; ".join(fails)
        print("判据明细(FAIL): " + reason)
        return "FAIL", reason, detail
    if missing:
        reason = "缺探针列: " + ", ".join(missing) + " (判据未取得)"
        print("判据明细(NOT_OBTAINED): " + reason)
        return "NOT_OBTAINED", reason, detail
    mem2_rec = detail.get("mem2", {})
    mem2_err_observed = any(mem2_rec.get(f) is not None for f in ("stall", "len_err", "bresp"))
    parts = ["mem/mem2 各自 wm==wr_frm==rd_frm、ost=0"]
    parts.append("mem stall/len_err=0 (mem.bresp 恒 0 仅 INFO: S2MM 下 BRESP 不可见)")
    parts.append("mem2 错误计数=0" if mem2_err_observed
                 else "mem2 错误计数无 ILA 探针(仅 INFO, 不可观测)")
    if glob_observed:
        gtxt = []
        if "wr_fault" in glob_observed:
            gtxt.append("dbg_wr_fault=0")
        if "wr_timeout" in glob_observed:
            gtxt.append("wr_timeout=0")
        else:
            gtxt.append("timeout 无 ILA 探针且无 Lite 读回路径(仅 INFO)")
        parts.append("R2 " + "/".join(gtxt))
    else:
        parts.append("R2 timeout/fault 探针缺失(INFO, 未硬判)")
    reason = "; ".join(parts)
    print("判据明细(PASS): " + reason)
    return "PASS", reason, detail


# ---------------------------------------------------------------------------
# selftest: 正/负对照(坑 #43/#56)
# ---------------------------------------------------------------------------
FAKE_COUNTERS = [
    ("dbg_calib", "(1:0)", "HEX"),
    ("dbg_mem_wm", "(15:0)", "HEX"),
    ("dbg_mem_wr_frm", "(15:0)", "HEX"),
    ("dbg_mem_rd_frm", "(15:0)", "HEX"),
    ("dbg_mem_stall", "(15:0)", "HEX"),
    ("dbg_mem_len_err", "(15:0)", "HEX"),
    ("dbg_mem_bresp", "(15:0)", "HEX"),
    ("dbg_mem_ost", "(8:0)", "HEX"),
    ("dbg_mem2_wm", "(15:0)", "HEX"),
    ("dbg_mem2_wr_frm", "(15:0)", "HEX"),
    ("dbg_mem2_rd_frm", "(15:0)", "HEX"),
    ("dbg_mem2_ost", "(8:0)", "HEX"),
    ("dbg_mem2_stall", "(15:0)", "HEX"),
    ("dbg_mem2_len_err", "(15:0)", "HEX"),
    ("dbg_mem2_bresp", "(15:0)", "HEX"),
    ("dbg_wr_timeout", "(15:0)", "HEX"),
    ("dbg_wr_fault", "(0:0)", "HEX"),
    ("dbg_s2mm_reqpend", "(0:0)", "HEX"),
    ("dbg_s2mm_state", "(2:0)", "HEX"),
    ("dbg_s2mm_tvalid", "(0:0)", "HEX"),
    ("dbg_s2mm_tready", "(0:0)", "HEX"),
]


def write_fake_csv(path, values):
    """按 Vivado ILA CSV 格式写合成快照: 表头 / Radix / 8 行采样(全部相同)。"""
    names = [c[0] + c[1] for c in FAKE_COUNTERS]
    radix = ["HEX" for _ in FAKE_COUNTERS]
    lines = [",".join(names), ",".join(radix)]
    for _ in range(8):
        cells = []
        for name, _w, _r in FAKE_COUNTERS:
            base = re.sub(r"\[.*$", "", name)
            v = values.get(base, 0)
            cells.append(("%x" % int(v)).upper())
        lines.append(",".join(cells))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def _tmp(d, name):
    return os.path.join(d, name)


def run_selftest():
    print(hr())
    print("SELFTEST: 判据工具正/负对照 (坑 #43: 负向 FAIL 必须指认具体判据行; 坑 #56: 工具自身也是被测件)")
    print(hr())
    n_ok = 0
    n_all = 0
    tmpd = tempfile.mkdtemp(prefix="r2_recon_selftest_")
    try:
        # ---------- case 1: delta 正型 ----------
        n_all += 1
        pre = _tmp(tmpd, "pre_ok.csv")
        post = _tmp(tmpd, "post_ok.csv")
        base = {"dbg_mem_wm": 100, "dbg_mem_wr_frm": 100, "dbg_mem_rd_frm": 100,
                "dbg_mem2_wm": 50, "dbg_mem2_wr_frm": 50, "dbg_mem2_rd_frm": 50,
                "dbg_s2mm_reqpend": 0}
        write_fake_csv(pre, base)
        d = dict(base)
        d.update({"dbg_mem_wm": 104, "dbg_mem_wr_frm": 104, "dbg_mem_rd_frm": 104,
                  "dbg_mem2_wm": 54, "dbg_mem2_wr_frm": 54, "dbg_mem2_rd_frm": 54})
        write_fake_csv(post, d)
        v, r, _ = judge_delta(read_ila_csv(pre), read_ila_csv(post), expect_delta=4)
        ok = (v == "PASS")
        n_ok += 1 if ok else 0
        print("SELFTEST_CASE 1 delta-positive: expect PASS -> %s  %s" % (v, "OK" if ok else "BAD"))
        print()

        # ---------- case 2: delta 负型(桥② rd_frm 只 +3) ----------
        n_all += 1
        d = dict(base)
        d.update({"dbg_mem_wm": 104, "dbg_mem_wr_frm": 104, "dbg_mem_rd_frm": 104,
                  "dbg_mem2_wm": 54, "dbg_mem2_wr_frm": 54, "dbg_mem2_rd_frm": 53})
        post2 = _tmp(tmpd, "post_bad_rd.csv")
        write_fake_csv(post2, d)
        v, r, _ = judge_delta(read_ila_csv(pre), read_ila_csv(post2), expect_delta=4)
        ok = (v == "FAIL") and ("mem2.rd_frm" in r)
        n_ok += 1 if ok else 0
        print("SELFTEST_CASE 2 delta-negative(mem2.rd_frm+3): expect FAIL 指认 mem2.rd_frm -> %s  %s"
              % (v, "OK" if ok else "BAD"))
        print()

        # ---------- case 3: recon 负型(桥① wm!=rd_frm + 错误计数非 0) ----------
        n_all += 1
        reccsv = _tmp(tmpd, "recon_bad.csv")
        d = dict(base)
        d.update({"dbg_mem_wm": 200, "dbg_mem_wr_frm": 200, "dbg_mem_rd_frm": 199,
                  "dbg_mem_stall": 3, "dbg_mem2_wm": 200, "dbg_mem2_wr_frm": 200,
                  "dbg_mem2_rd_frm": 200})
        write_fake_csv(reccsv, d)
        v, r, _ = judge_recon(read_ila_csv(reccsv))
        ok = (v == "FAIL") and ("mem 三计数失配" in r) and ("mem.stall=3" in r)
        n_ok += 1 if ok else 0
        print("SELFTEST_CASE 3 recon-negative(trio+stall): expect FAIL 指认 mem 三计数失配 且 mem.stall -> %s  %s"
              % (v, "OK" if ok else "BAD"))
        print()

        # ---------- case 4: recon 缺列 -> NOT_OBTAINED ----------
        n_all += 1
        bare = _tmp(tmpd, "recon_bare.csv")
        with open(bare, "w", encoding="utf-8", newline="\n") as f:
            f.write("Sample in Buffer,Sample in Window,TRIGGER,dbg_calib\n")
            f.write("UNSIGNED,UNSIGNED,UNSIGNED,HEX\n")
            f.write("0,0,1,1\n")
        v, r, _ = judge_recon(read_ila_csv(bare))
        ok = (v == "NOT_OBTAINED")
        n_ok += 1 if ok else 0
        print("SELFTEST_CASE 4 recon-missing-columns: expect NOT_OBTAINED -> %s  %s"
              % (v, "OK" if ok else "BAD"))
        print()

        # ---------- case 5: tcl 检查正/负型 ----------
        n_all += 1
        goodtcl = _tmp(tmpd, "good.tcl")
        with open(goodtcl, "w", encoding="utf-8", newline="\n") as f:
            f.write("# comment line\nset x 1\nif {$x == 1} {\n    puts \"ok\"\n}\n")
        badtcl = _tmp(tmpd, "bad.tcl")
        with open(badtcl, "w", encoding="utf-8", newline="\n") as f:
            f.write("# comment line\nset x 1\nif {$x == 1} {\n    puts \"ok\"\n")
        ok1, _ = check_tcl_file(goodtcl)
        ok2, msg2 = check_tcl_file(badtcl)
        ok = ok1 and (not ok2) and ("花括号" in msg2 or "未闭合" in msg2)
        n_ok += 1 if ok else 0
        print("SELFTEST_CASE 5 tcl-check(good=PASS, bad=FAIL): good=%s bad=%s -> %s"
              % (ok1, ok2, "OK" if ok else "BAD"))
        print()
    finally:
        for f in os.listdir(tmpd):
            try:
                os.remove(os.path.join(tmpd, f))
            except OSError:
                pass
        try:
            os.rmdir(tmpd)
        except OSError:
            pass

    print(hr())
    if n_ok == n_all:
        print("R2_SELFTEST: PASS %d/%d" % (n_ok, n_all))
        return 0
    print("R2_SELFTEST: FAIL %d/%d (判据工具自身有问题, 先修工具再上板)" % (n_ok, n_all))
    return 1


# ---------------------------------------------------------------------------
# Tcl 结构检查(本机无 tclsh 的替代; 权威判据 = CI tclsh info-complete)
# ---------------------------------------------------------------------------
def check_tcl_file(path):
    """返回 (ok, message)。检查: 非 ASCII(GBK 解码风险, 坑 #1 同族); 引号/花括号/方括号闭合;
    行尾 # 提示(坑 #19)。"""
    try:
        with open(path, "rb") as fb:
            raw = fb.read()
    except OSError as e:
        return False, "读取失败: %s" % e
    # Vivado 按宿主 ANSI(GBK) 解码 Tcl 源: 非 ASCII 字节可能破坏脚本(R1 rdcap2 纪律 = ASCII only)
    non_ascii = [(i, b) for i, b in enumerate(raw) if b > 0x7F]
    if non_ascii:
        off, byte = non_ascii[0]
        line = raw[:off].count(b"\n") + 1
        return False, ("含非 ASCII 字节(第 %d 行, 0x%02X; 共 %d 处) —— Vivado 按 GBK 解码 Tcl 源, "
                       "非 ASCII 可能破坏脚本(坑 #1 同族); 须 ASCII-only" % (line, byte, len(non_ascii)))
    try:
        with open(path, "r", encoding="ascii", errors="replace") as f:
            text = f.read()
    except OSError as e:
        return False, "读取失败: %s" % e
    stack = []          # ("brace"|"bracket", line)
    in_quote = False
    quote_line = 0
    line_no = 1
    line_has_content = False   # 当前行是否已有非空白内容
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\n":
            line_no += 1
            line_has_content = False
            i += 1
            continue
        if ch == "\\" and not in_quote:
            # 转义: 跳过下一个字符(含行尾续行)
            if i + 1 < n and text[i + 1] == "\n":
                line_no += 1
                line_has_content = False
            i += 2
            continue
        if in_quote:
            if ch == '"':
                in_quote = False
            elif ch == "\\":
                i += 2
                continue
            i += 1
            continue
        if ch == "#" and not line_has_content:
            # 行首注释(本仓库约定): 整行跳过
            while i < n and text[i] != "\n":
                i += 1
            line_no += 1
            line_has_content = False
            continue
        if ch == "#" and stack == []:
            return False, "第 %d 行出现行尾 # 注释(Tcl 非法, 坑 #19), 注释必须独立成行" % line_no
        if ch == '"':
            in_quote = True
            quote_line = line_no
        elif ch == "{":
            stack.append(("brace", line_no))
        elif ch == "}":
            if not stack or stack[-1][0] != "brace":
                return False, "第 %d 行多余的 '}' (未匹配)" % line_no
            stack.pop()
        elif ch == "[":
            stack.append(("bracket", line_no))
        elif ch == "]":
            if not stack or stack[-1][0] != "bracket":
                return False, "第 %d 行多余的 ']' (未匹配)" % line_no
            stack.pop()
        if not ch.isspace():
            line_has_content = True
        i += 1
    if in_quote:
        return False, "引号未闭合(自第 %d 行)" % quote_line
    if stack:
        kind, ln = stack[-1]
        name = "花括号" if kind == "brace" else "方括号"
        return False, "%s未闭合(自第 %d 行, 余 %d 层)" % (name, ln, len(stack))
    return True, "OK"


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(
        description="prj11 R2 双桥计数对账 / ILA 前后差分 / 判据工具自检",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=["delta", "recon", "selftest"], default="",
                    help="delta=S6 前后差分; recon=S10 J4 累计对账; selftest=正负对照")
    ap.add_argument("--ui-pre", default="", help="UI 域 ILA PRE 快照 CSV")
    ap.add_argument("--ui-post", default="", help="UI 域 ILA POST 快照 CSV(recon 模式可只给这个)")
    ap.add_argument("--user-pre", default="", help="user 域 ILA PRE 快照 CSV(可选)")
    ap.add_argument("--user-post", default="", help="user 域 ILA POST 快照 CSV(可选)")
    ap.add_argument("--expect-delta", type=int, default=4, help="delta 模式期望前进步数(默认 4 = ping×4)")
    ap.add_argument("--json-out", default="", help="把判据明细写成 JSON")
    ap.add_argument("--require-r2-probes", action="store_true",
                    help="要求 R2 新探针(dbg_s2mm_* 6 项)全部存在, 否则 recon 判 NOT_OBTAINED(默认只 WARN)")
    ap.add_argument("--check-tcl", default="", help="Tcl 结构完整性检查(不进入 mode 流程)")
    ap.add_argument("--allow-missing", action="store_true", help="缺探针列时降级为 WARN(默认 NOT_OBTAINED)")
    args = ap.parse_args(argv)

    # ---- Tcl 检查模式 ----
    if args.check_tcl:
        ok, msg = check_tcl_file(args.check_tcl)
        if ok:
            print("R2_TCL_CHECK: PASS %s %s" % (args.check_tcl, msg))
            return 0
        print("R2_TCL_CHECK: FAIL %s %s" % (args.check_tcl, msg))
        return 1

    # ---- selftest ----
    if args.mode == "selftest":
        return run_selftest()

    if args.mode == "":
        print("用法错误: 需要 --mode {delta|recon|selftest} 或 --check-tcl <path>", file=sys.stderr)
        return 3

    # ---- 读 CSV ----
    try:
        ui_pre_cols = read_ila_csv(args.ui_pre) if args.ui_pre else None
        ui_post_cols = read_ila_csv(args.ui_post) if args.ui_post else None
        user_pre_cols = read_ila_csv(args.user_pre) if args.user_pre else None
        user_post_cols = read_ila_csv(args.user_post) if args.user_post else None
    except ValueError as e:
        print("R2_COUNTER_RECON: NOT_OBTAINED CSV 读取失败: %s" % e)
        if args.mode == "delta":
            print("R2_ILA_DELTA: NOT_OBTAINED CSV 读取失败: %s" % e)
        return 2

    detail = {}
    if args.mode == "delta":
        if not ui_pre_cols or not ui_post_cols:
            msg = "delta 模式需要 --ui-pre 与 --ui-post 两份 CSV (判据未取得; 先跑 r2_ilacap.tcl)"
            print("R2_ILA_DELTA: NOT_OBTAINED " + msg)
            print("R2_COUNTER_RECON: NOT_OBTAINED " + msg)
            return 2
        v, r, detail = judge_delta(ui_pre_cols, ui_post_cols, user_pre_cols, user_post_cols,
                                   expect_delta=args.expect_delta)
        print("R2_ILA_DELTA: %s %s" % (v, r))
        # delta 的正型也顺带给出累计对账(复用 post 快照)
        rv, rr, rdetail = judge_recon(ui_post_cols, user_post_cols, label="post",
                                      require_r2_probes=args.require_r2_probes)
        detail["recon_from_post"] = rdetail
        print("R2_COUNTER_RECON: %s %s" % (rv, rr))
        overall = "PASS" if (v == "PASS" and rv == "PASS") else (
            "NOT_OBTAINED" if "NOT_OBTAINED" in (v, rv) else "FAIL")
        print("R2_RECON_RESULT: %s" % overall)
        if args.json_out:
            _write_json(args.json_out, {"mode": "delta", "delta": {"verdict": v, "reason": r,
                                                                   "detail": detail}})
        return 0 if overall == "PASS" else (2 if overall == "NOT_OBTAINED" else 1)

    if args.mode == "recon":
        cols = ui_post_cols or ui_pre_cols
        if not cols:
            msg = "recon 模式需要 --ui-post 或 --ui-pre CSV (判据未取得)"
            print("R2_COUNTER_RECON: NOT_OBTAINED " + msg)
            print("R2_RECON_RESULT: NOT_OBTAINED")
            return 2
        label = "post" if ui_post_cols else "pre"
        v, r, detail = judge_recon(cols, user_post_cols or user_pre_cols, label=label,
                                   require_r2_probes=args.require_r2_probes)
        print("R2_COUNTER_RECON: %s %s" % (v, r))
        # ★2026-10-19 工具维护: delta 模式一直打印 R2_RECON_RESULT, recon 模式漏了;
        #   而 out/r2_board.ps1 的 Invoke-ReconJudge 只认 R2_RECON_RESULT => 真 PASS 被
        #   汇总成 NOT_OBTAINED。此处补齐标记 (判据逻辑不变)。
        print("R2_RECON_RESULT: %s" % v)
        if args.json_out:
            _write_json(args.json_out, {"mode": "recon", "verdict": v, "reason": r, "detail": detail})
        return 0 if v == "PASS" else (2 if v == "NOT_OBTAINED" else 1)

    print("用法错误: 未知 mode %s" % args.mode, file=sys.stderr)
    return 3


def _write_json(path, obj):
    try:
        parent = os.path.dirname(os.path.abspath(path))
        if parent and not os.path.isdir(parent):
            os.makedirs(parent, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
        print("JSON_OUT: " + os.path.abspath(path))
    except OSError as e:
        print("JSON_OUT_WARN: %s" % e)


if __name__ == "__main__":
    sys.exit(main())
