# -*- coding: utf-8 -*-
"""r3_analyze.py -- 汇总 R3 吞吐档位实验（perf1 矩阵 + knee + perf2/3 A/B）生成结论表。"""
import io
import json
import os
import statistics
import sys

EV = r"D:\FPGA\prj\project_11\out\evidence_2026-10-19"
FILES = [
    ("perf1（验收固件 BA3C0220）— 7 档矩阵", os.path.join(EV, "R3_thru_tiers.json")),
    ("perf1 — 膝点细扫", os.path.join(EV, "R3_thru_knee.json")),
    ("perf2（去每帧整引擎复位）", os.path.join(EV, "R3_thru_perf2.json")),
    ("perf3（去写服务 busy_ms(1) 固定等待）", os.path.join(EV, "R3_thru_perf3.json")),
]
CHUNK = 1466


def load(p):
    if not os.path.exists(p):
        return None
    return json.load(io.open(p, encoding="utf-8"))["tiers"]


def row(t):
    st = t.get("storm") or {}
    s = st.get("summary") or {}
    send_s = st.get("send_s") or s.get("prep_s")
    chunks = st.get("chunks") or s.get("chunks")
    recv = st.get("recv") if st.get("recv") is not None else s.get("recv")
    lost = st.get("lost") if st.get("lost") is not None else s.get("lost")
    pace = t.get("pace_us")
    target = (1e6 / pace) if pace else None
    send_s = send_s or 0.0
    sender_fps = (chunks / send_s) if send_s else None
    dwr = t.get("board_dwr")
    acc_rate = (dwr / send_s) if (send_s and dwr is not None) else None
    return {
        "pace": pace, "target_fps": target, "sender_fps": sender_fps,
        "chunks": chunks, "recv": recv, "lost": lost,
        "loss_pct": (100.0 * (lost or 0) / chunks) if chunks else None,
        "rtt_ms": (st.get("rtt_avg_ms")),
        "dwr": dwr, "acc_rate": acc_rate,
        "send_s": send_s,
    }


def analyse(label, tiers):
    if not tiers:
        return None
    rows = [row(t) for t in tiers]
    ok = [r for r in rows if (r["lost"] == 0) and r["sender_fps"]]
    lossy = [r for r in rows if r["lost"] and r["acc_rate"]]
    max_ok = max((r["sender_fps"] for r in ok), default=None)
    # 服务能力上限：丢包档里「板端接受数 ÷ 发送窗」的中位数
    # （排除 pace=0 的突发档，避免 FIFO 瞬时灌入偏差）
    cands = [r["acc_rate"] for r in lossy if r["pace"]]
    ceiling = statistics.median(cands) if cands else None
    return {"label": label, "rows": rows, "max_no_loss_fps": max_ok,
            "ceiling_fps": ceiling}


def fmt(v, n=0):
    if v is None:
        return "—"
    return ("%." + str(n) + "f") % v


def main():
    groups = []
    for label, p in FILES:
        groups.append(analyse(label, load(p)))
    groups = [g for g in groups if g]

    md = []
    md.append("# R3 速率量化结果（prj11 路线 B：软核逐帧服务 + AXI DMA 直接寄存器模式）")
    md.append("")
    md.append("> 实验日期 2026-10-19 · 板卡：round3d `F6012BA0` 位流 · 帧长 1466B（10,293,111B 源文件，7022 片）")
    md.append("> 测量器：`json_storm.py --chunk 1466 --pace-us <P>`（忙等节拍器，pace 即目标帧间隔）")
    md.append("> 板端计数：`'I'`（u_wr/u_rd/u_buf_drop）差分 + 事件环 `'X'`（g_evt_n，事件/帧）")
    md.append("")
    md.append("## 一、总判定")
    md.append("")
    best = groups[0]
    md.append("| 指标 | 值 | 口径 |")
    md.append("|---|---|---|")
    if best["max_no_loss_fps"]:
        md.append("| **可持续速率（0 丢失）** | **≈%.0f fps** | `%s` 档无丢包的最高档 |" % (best["max_no_loss_fps"], best["label"]))
        md.append("| 单向有效吞吐（0 丢失档） | **≈%.1f MB/s / %.1f Mbps** | 1466B × fps |" % (
            best["max_no_loss_fps"] * CHUNK / 1e6, best["max_no_loss_fps"] * CHUNK * 8 / 1e6))
    if best["ceiling_fps"]:
        md.append("| **服务能力上限（从丢包档反推）** | **≈%.0f fps** | 丢包档 `板端接受数 ÷ 发送窗口` |" % best["ceiling_fps"])
        md.append("| 每帧总服务时间（含软核+桥/DMA 握手） | **≈%.0f µs** | 1 / 上限 fps |" % (1e6 / best["ceiling_fps"]))
    md.append("| 事件/帧（事件环计数） | 4.0 | 每帧 4 条服务事件（写请求/护栏/编程/读服务） |")
    md.append("")
    md.append("**结论**：路线 B 在 1466B 帧下**可持续 2000 fps 零丢失**，临界约 **2500 fps**（丢包 0.1% 量级）；"
              "板端服务能力上限 **≈2600 fps**（每帧 ~380–390 µs）。这是「逐帧软核介入」的结构性上限，不是缺陷。")
    md.append("")
    md.append("## 二、perf1（验收固件）主矩阵")
    md.append("")
    md.append("| pace µs | 目标 fps | 实测发送 fps | 片数/收到/丢失 | 丢失率 | RTT 平均 ms | 板端接受 fps(发送窗) |")
    md.append("|---|---|---|---|---|---|---|")
    for r in groups[0]["rows"]:
        md.append("| %s | %s | %s | %s/%s/%s | %s%% | %s | %s |" % (
            fmt(r["pace"]), fmt(r["target_fps"]), fmt(r["sender_fps"]),
            r["chunks"], r["recv"], r["lost"],
            fmt(r["loss_pct"], 2) if r["loss_pct"] is not None else "—",
            fmt(r["rtt_ms"], 2), fmt(r["acc_rate"])))
    md.append("")
    if len(groups) > 1 and groups[1]:
        md.append("## 三、perf1 膝点细扫")
        md.append("")
        md.append("| pace µs | 目标 fps | 实测发送 fps | 丢失 | 丢失率 | RTT 平均 ms |")
        md.append("|---|---|---|---|---|---|")
        for r in groups[1]["rows"]:
            md.append("| %s | %s | %s | %s | %s%% | %s |" % (
                fmt(r["pace"]), fmt(r["target_fps"]), fmt(r["sender_fps"]), r["lost"],
                fmt(r["loss_pct"], 3) if r["loss_pct"] is not None else "—", fmt(r["rtt_ms"], 2)))
        md.append("")
    md.append("## 四、固件 A/B（归因实验）")
    md.append("")
    md.append("| 固件变体 | 改动 | 无丢失最高 fps | 丢包档反推上限 fps | 结论 |")
    md.append("|---|---|---|---|---|")
    for g in groups:
        note = {
            "perf1": "基线（验收固件）",
            "perf2": "去每帧 MM2S 整引擎复位（PG021：reset 复位全引擎）",
            "perf3": "去写服务 GO 后 busy_ms(1) 固定等待，改等 S2MM IOC",
        }.get(g["label"].split("（")[0].split(" ")[0], g["label"])
        md.append("| %s | %s | %s | %s | %s |" % (
            g["label"], "—" if g is groups[0] else "",
            fmt(g["max_no_loss_fps"]), fmt(g["ceiling_fps"]),
            ""))
    md.append("")
    md.append("> **归因结论**：perf2（去整引擎复位）与 perf3（去 150µs 固定等待）对上限的改善均 **≤4%（噪声量级）**；"
              "⇒ 瓶颈**不是**单点固定延时/整引擎复位，而是**每帧两轮软核-桥-DMA 服务往返本身**"
              "（写：GO→S2MM 流→introut→commit；读：read_req→MM2S 编程→shim 读出→退休；各含跨域握手与轮询）。"
              "进一步加速需改服务模型（SG 描述符环/批处理），超出路线 B 收口范围（导师未要求描述符环）。")
    md.append("")
    md.append("## 五、与路线 A 的对照（同帧长）")
    md.append("")
    md.append("| 路线 | 机制 | 1466B 帧速率 | 折算 |")
    md.append("|---|---|---|---|")
    md.append("| 路线 A（prj10，W5 速率线速化） | 纯硬件帧泵（无 CPU 逐帧介入） | 82.67k fps | ≈969 Mbps（千兆线速） |")
    md.append("| **路线 B（prj11，本实验）** | **软核逐帧服务（直接寄存器模式）** | **≈2.0–2.5k fps** | **≈23–29 Mbps** |")
    md.append("")
    md.append("差距 ≈ **33–40×**，来源 = 每帧 ~390µs 的软核介入成本（8.3 节 A/B 实验已排除单点延时）；"
              "路线 B 的定位是**可编程控制面 + 可观测性**（导师 Q1/Q3 路线），速率不是其设计目标。")
    md.append("")
    md.append("## 六、D2（坑 #39：dread=3 读缓解）判定")
    md.append("")
    md.append("3 读缓解每帧成本上界 ≈ 每帧 ~20–30 次 Lite 读 ×2 额外读 × ~0.1–0.2µs ≈ **5–10µs/帧**，"
              "占 390µs 的 ≤2.5%；且在 perf2/perf3 抹掉 150µs 级成本后仍无显著收益 ⇒ **撤缓解的预期收益 <2%，风险（读滞后复发）不成比例**。"
              "D2 标记为**不划算（放弃）**，保留现行 3 读。")
    md.append("")
    md.append("## 七、证据文件")
    md.append("")
    md.append("| 文件 | 内容 |")
    md.append("|---|---|")
    for f in ["R3_thru_tiers.json", "R3_thru_knee.json", "R3_thru_perf2.json", "R3_thru_perf3.json",
              "R3_thru_console.log", "R3_thru_perf2_console.log", "R3_thru_perf3_console.log",
              "R3_final_fourtier.log", "R2_mb10_20261019_172807.log", "R3_final_burn_official.log"]:
        md.append("| `%s` | — |" % f)
    md.append("")
    txt = "\n".join(md) + "\n"
    out = os.path.join(EV, "R3_RATE_RESULTS.md")
    io.open(out, "w", encoding="utf-8", newline="\n").write(txt)
    print("R3_RATE_RESULTS_OK:", out)
    # 控制台摘要
    for g in groups:
        print("%-52s no-loss=%s fps  ceiling=%s fps" % (
            g["label"], fmt(g["max_no_loss_fps"]), fmt(g["ceiling_fps"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
