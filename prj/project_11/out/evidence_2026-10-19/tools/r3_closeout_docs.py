# -*- coding: utf-8 -*-
"""2026-10-19 路线 B 收尾（R3/R4）文档落地：
- 记录 §二十二（R3 速率结果 + R4 交付 + 路线 B 收口结论）
- 剩余清单 §八（收尾执行记录：R3/R4 完成、D1/K2 已结、D2 放弃）
- 复现/README.md（加 prj11 章节与坑）
- AGENTS §十（路线 B 收口完成；project_11 行状态）
- 短期待办（收尾更新）
- docs 镜像（记录/清单/复现 README/新指南）+ docs/README 索引
"""
import io
import os
import shutil

VAULT = r"C:\Users\15266\Desktop\毕设"
REPO = r"D:\FPGA"
DOCS = os.path.join(REPO, "docs")

REC = os.path.join(VAULT, "调试记录", "阶段三_prj11_R2写侧S2MM换层_2026-10-17.md")
WL = os.path.join(VAULT, "操作文档", "阶段三_prj11_路线B剩余工作清单_2026-10-16.md")
TODO = os.path.join(VAULT, "追踪_cross_短期待办_2026-10-10.md")
REPRO = os.path.join(VAULT, "复现", "README.md")
GUIDE = os.path.join(VAULT, "复现", "复现_prj11_指南_2026-10-19.md")
AGENTS = os.path.join(REPO, "AGENTS.md")
DREADME = os.path.join(DOCS, "README.md")


def read(p):
    return io.open(p, "r", encoding="utf-8", newline="").read()


def write(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


# ---------------------------------------------------------------- 记录 §二十二
REC_SEC = r'''
## 二十二、路线 B 收尾（R3 速率量化 + R4 文档收口，2026-10-19）

> 结论：**路线 B（B0–B5 / R1 / R2 / R3 / R4）全部收口。** 本节记录 R3/R4 的执行结果与最终证据。

### 22.1 R3 速率量化（板场次：round3d `F6012BA0` + perf1 `BA3C0220`）

**方法**：`json_storm.py --chunk 1466 --pace-us <P>`（忙等节拍器，pace=目标帧间隔；1466B 帧、7022 片/轮），
板端 `'I'`（u_wr/u_rd/u_buf_drop）差分 + 事件环 `'X'`（g_evt_n）；测量器 `out/evidence_2026-10-19/tools/r3_thru.py`。

| pace µs | 目标 fps | 实测发送 fps | 片数/收到/丢失 | 丢失率 | 板端接受 fps（发送窗） |
|---|---|---|---|---|---|
| 1000 | 1000 | 1000 | 7022/7022/0 | 0 | 1000 |
| **500** | **2000** | **2001** | **7022/7022/0** | **0** | **2001** |
| 400 | 2500 | 2499 | 7022/7016/6 | 0.085% | 2497 |
| 350 | 2857 | 2843 | 7022/6309/713 | 10.2% | 2566 |
| 300 | 3333 | 3328 | 7022/5400/1622 | 23.1% | 2563 |
| 200 | 5000 | 4980 | 7022/3600/3422 | 48.7% | 2553 |
| 100 | 10000 | 10031 | 7022/1804/5218 | 74.3% | 2577 |
| 50 | 20000 | 20063 | 7022/907/6115 | 87.1% | 2591 |
| 13（prj9 吞吐档） | 76923 | 70220 | 7022/250/6772 | 96.4% | 2500 |
| 0（无节拍） | — | 117033 | 7022/223/6799 | 96.8% | — |

**判定**：1466B 帧下 **可持续 2000 fps 零丢失**（≈23.5 Mbps 单向）；**临界 ≈2500 fps**（400µs 档丢 0.085%）；
**服务能力上限 ≈2560 fps**（多个丢包档反推中位数，每帧 ≈390 µs）。

**归因 A/B（三版固件，同一 round3d 位流）**：

| 变体 | 改动 | 上限 fps（丢包档反推中位数） | 与基线差 |
|---|---|---|---|
| perf1（验收固件） | 基线（`s2mm_rearm` 修复 + 全速服务） | **2565** | — |
| perf2 | 读服务去掉每帧 MM2S 整引擎复位（PG021：reset 复位全引擎） | 2556 | −0.4%（噪声） |
| perf3 | 写服务去掉 GO 后 `busy_ms(1)` 固定等待，改等 S2MM IOC | 2571 | +0.2%（噪声） |

⇒ **瓶颈不是"整引擎复位"或"固定等待"这类单点延时**，而是**每帧两轮软核-桥-DMA 服务往返本身**
（写：GO→S2MM 流→introut→commit；读：read_req→MM2S 编程→shim 读出→退休；各含跨域握手+轮询）。
进一步提速需改服务模型（SG 描述符环/批处理），属新设计（导师未要求描述符环，不在路线 B 范围）。
事件环计数 **4.0 事件/帧**（写请求/护栏/编程/读服务各一类）。

**与路线 A 对照**：路线 A（纯硬件帧泵）1466B **82.67k fps ≈969 Mbps**（线速）；路线 B **≈2.0–2.5k fps ≈23–29 Mbps**，
差 33–40× = 每帧约 390µs 的软核介入成本（路线 B 定位=可编程控制面+可观测性，速率非目标）。

**D2（坑 #39 三读缓解）判定 = 放弃**：三读成本上界 ≈5–10µs/帧（占 390µs ≤2.5%）；perf2/perf3 抹掉 150µs 级成本后
上限仍无变化 ⇒ 撤缓解收益 <2%、风险（读滞后复发）不成比例。保留现行 `dread()` 三读。

### 22.2 R4 文档/可观测性收口交付

1. **复现指南 B 章**：`复现/复现_prj11_指南_2026-10-19.md`（12 节：产物 hash、烧录、体检、S0–S11 一键、四档、10MB+SHA、J3、
   速率量化、ILA、归档核对、8 条坑、与路线 A 对照）+ `复现/README.md` 索引更新。
2. **prj11 探针/计数清单自动生成**：`scripts/w6_inventory_prj11.py`（W6 思路移植版，**以 LTX 构建产物为主源** + RTL 交叉比对）
   → `out/W6_prj11_可观测性清单.md`：ILA0 110b/ILA3 152b/ILA5 47b（合计 309b）、118 个 RTL `dbg_*` 声明、86 个未挂/缺口、
   判据↔探针索引、配置变体（round3b/round3c-diag/round3d）说明。
3. **跨轮归档索引**：`scripts/archive_index_prj11.py` → `out/archive/ARCHIVE_INDEX_prj11.md`；
   对 13 个历史轮次**补生成 SHA256.txt**（`scripts/backfill_archive_sha.py`，只补清单不改产物）⇒
   **32 轮 / 584 文件 / 有 SHA256.txt 32/32 / 表内缺失 0**，`archive_index_prj11.py --check` exit 0。
4. **文档同步**：AGENTS §十（路线 B 标收口）、记录 §二十二、剩余清单 §八、短期待办、docs 镜像+README。

### 22.3 最终产物与板卡状态

- 验收对（不变，R3 实验后**已恢复并复验**）：bit **`F6012BA0`** / ltx `2F8AF498` / xsa `216839F4` / ELF **`BA3C0220`**（归档 `b31b_r2_2026-10-19_round3d/`）。
- 复验（2026-10-19 17:2x）：重烧官方对后 `udp_verify_ddr.py` **DDR_VERIFY: PASS**（20/20·12/12·12/12·300/300）；
  `r2_mb10_sha.ps1 -Run` **R2_MB10_RESULT: PASS**（7022/7022、SHA256 一致）；板卡留在官方对 + `'d'`（mode=1）。
- R3 实验固件（perf2 `ED908502` / perf3 `47B9EB18`）为**实验变体、未采纳**；源码由 `main_perf1.c` + patch 脚本可复现
  （`out/evidence_2026-10-19/tools/r3_patch_perf{2,3}.py`）；实验后已 `git checkout` 回到 perf1 并在板上复验功能。

### 22.4 路线 B 收口结论

| 阶段 | 判据 | 状态 |
|---|---|---|
| B0 脚手架 / B1 软核控制面 / B2 J3 软核验证 / B3-0 延迟可观测 / B3-1 DMA 集成与读路径 | 各自判据 | ✅（10-10～10-17） |
| R1 读侧收尾（退役桥①读引擎） | S0–S8 + 四判据 | ✅（10-17，[L4]） |
| **R2 写侧换 S2MM** | round3d 过门限 + S0–S11 13/13 | ✅（10-19） |
| **R3 速率量化** | 上限/膝点/归因（本节） | ✅（10-19） |
| **R4 文档/可观测性收口** | 复现指南/清单/索引 0 缺失/文档同步 | ✅（10-19） |
| D1 / D2 / K1 / K2 | 见 §21 | D1/K2 结项；D2 放弃（量化后）；K1 保留风险条 |

**路线 B 完结（2026-10-19）。** 后续（若继续）属新范围：双板双链路（2026-09-30 Q4 已定案暂缓）/ SG 描述符环提速 /
调度与 FL 负载验证 —— 均不在本轮路线 B 收口内。
'''

# ---------------------------------------------------------------- 剩余清单 §八
WL_SEC = r'''
## 八、2026-10-19 收尾执行记录（R3/R4 完成；路线 B 收口）

> 本节替代 §一/§三 的 R3/R4 状态；执行口径见记录 §二十一（重审）与 §二十二（结果）。

| 项 | 修订判据 | 结果 | 状态 |
|---|---|---|---|
| **R3 速率量化** | pace 档矩阵 + 膝点 + 三版固件 A/B + D2 判定 | 1466B：**可持续 2000fps 零丢**、**临界≈2500fps**、**上限≈2560fps（≈390µs/帧）**；A/B（去整引擎复位/去 busy 固定等待）均 ≤±0.4% ⇒ 瓶颈=每帧软核服务往返（结构性）；D2 三读收益 <2% ⇒ **放弃** | ✅ 完成 |
| **R4 文档收口** | 复现指南/探针清单/归档索引/文档同步 | ①`复现/复现_prj11_指南_2026-10-19.md` + README；②`scripts/w6_inventory_prj11.py`→`out/W6_prj11_可观测性清单.md`（309b/118 声明/86 缺口）；③`scripts/archive_index_prj11.py`→32 轮/584 文件/**0 缺失**（13 旧轮补 SHA256）；④记录 §二十二 + AGENTS §十 + 短期待办 + docs 镜像 | ✅ 完成 |
| ~~D1~~ | W2/W4 TB 改造 | 已由 10-17 `.HAS_DMA(0)` tie + 回归完成 | ✅ 已结项 |
| **D2** | 坑 #39 三读撤除 | 量化收益 <2%、风险不成比例 ⇒ **放弃**（保留三读） | ✅ 已判定 |
| ~~K2~~ | wedge 根因 | module-ref IP cache 陈旧（坑 #68） | ✅ 已结项 |
| K1 | 时序抖动风险 | recipe 保留（单掷 ExtraTimingOpt + ILA 裁剪 + retry） | 保留风险条 |

**⇒ 路线 B 全部工作包（B0–B5 / R1–R4）收口完成（2026-10-19）。**
证据：记录 §二十二、`out/evidence_2026-10-19/R3_RATE_RESULTS.md`、`out/archive/ARCHIVE_INDEX_prj11.md`、`out/W6_prj11_可观测性清单.md`、
`复现/复现_prj11_指南_2026-10-19.md`、S0–S11 run3（13/13 PASS）与四档/10MB 复验日志。
'''

# ---------------------------------------------------------------- 短期待办更新
TODO_SEC = r'''
## 2026-10-19 收尾完成（R3/R4；路线 B CLOSED）

- ✅ **R3 速率量化完成**：1466B 帧 可持续 **2000fps 零丢失**（≈23.5Mbps）、临界 **≈2500fps**、服务上限 **≈2560fps**（≈390µs/帧）；
  三版固件 A/B（去整引擎复位 / 去 busy 固定等待）均 ≤±0.4% ⇒ 瓶颈=每帧软核服务往返（结构性）；**D2 三读撤除=放弃**（收益<2%）。
- ✅ **R4 文档收口完成**：复现指南 B 章（`复现/复现_prj11_指南_2026-10-19.md`）、prj11 探针清单自动生成
  （`out/W6_prj11_可观测性清单.md`）、跨轮归档索引 **32 轮/584 文件/0 缺失**（13 旧轮补 SHA256）、
  AGENTS §十 + 记录 §二十二 + 剩余清单 §八 + docs 镜像。
- ✅ **路线 B 全部工作包（B0–B5 / R1–R4）收口**；最终验收对 round3d `F6012BA0` + perf1 `BA3C0220` 已恢复并复验（四档 + 10MB+SHA PASS）。
- 后续属新范围（不在路线 B）：双板双链路（2026-09-30 Q4 暂缓）/ SG 描述符环提速 / 调度与 FL 负载验证。
'''

# ---------------------------------------------------------------- AGENTS 更新
AG_NEW_BULLET = (
    "- ✅ **路线 B 收口完成（2026-10-19）**：B0–B5 / R1（读侧）/ **R2（写侧 S2MM，round3d `F6012BA0` + S0–S11 13/13 PASS）** / "
    "**R3 速率量化**（1466B：可持续 **2000fps 零丢失**≈23.5Mbps，临界 **≈2500fps**，上限 **≈2560fps≈390µs/帧**；"
    "三版固件 A/B 证明瓶颈=每帧软核服务往返而非单点延时；D2 三读撤除收益<2% ⇒ 放弃） / "
    "**R4 文档收口**（复现指南 B 章 `复现/复现_prj11_指南_2026-10-19.md`、`out/W6_prj11_可观测性清单.md`、"
    "`out/archive/ARCHIVE_INDEX_prj11.md` **32 轮/584 文件/0 缺失**、AGENTS+记录 §二十二+docs 镜像）全部完成。"
    "D1/K2 已结项，K1 保留风险条。证据：`out/evidence_2026-10-19/R3_RATE_RESULTS.md`、`R3D_S0-S11_run3.log`、四档/10MB 复验日志。"
    "后续属新范围：双板双链路（2026-09-30 Q4 暂缓）/ SG 描述符环提速 / 调度与 FL 负载验证。"
)
AG_OLD_ROW_TAIL = ("**2026-10-19：R1/R2 已收口（round3d `F6012BA0` WNS+0.002/WHS+0.004 + S0–S11 13/13 PASS）；"
                   "剩 R3 速率量化 + R4 文档收口（≈1 天，重审版见剩余清单 §七/记录 §二十一）；D1/K2 结项、D2 可选、坑#39 降级**")
AG_NEW_ROW_TAIL = ("**2026-10-19：路线 B 全量收口（B0–B5/R1–R4）**——round3d `F6012BA0` + S0–S11 13/13 PASS；"
                   "R3 速率：可持续 2000fps/临界≈2500fps/上限≈2560fps（瓶颈=每帧软核服务）；"
                   "R4：复现指南 B 章 + 探针清单 + 归档索引 0 缺失；D1/K2 结项、D2 放弃**")

# ================================================================ 执行
if "## 二十二、路线 B 收尾" in read(REC):
    print("record already patched")
else:
    s = read(REC).rstrip("\n") + "\n" + REC_SEC
    write(REC + ".tmp22", s)
    os.replace(REC + ".tmp22", REC)
    print("record §二十二 appended ->", os.path.getsize(REC))

if "## 八、2026-10-19 收尾执行记录" in read(WL):
    print("worklist already patched")
else:
    s = read(WL).rstrip("\n") + "\n" + WL_SEC
    write(WL + ".tmp8", s)
    os.replace(WL + ".tmp8", WL)
    print("worklist §八 appended ->", os.path.getsize(WL))

if "2026-10-19 收尾完成（R3/R4；路线 B CLOSED）" in read(TODO):
    print("todo already patched")
else:
    s = read(TODO).rstrip("\n") + "\n" + TODO_SEC
    write(TODO + ".tmp3", s)
    os.replace(TODO + ".tmp3", TODO)
    print("todo appended ->", os.path.getsize(TODO))

# README 复现索引（vault）
r = read(REPRO)
r = r.replace("# prj9 / prj10 复现指南", "# prj9 / prj10 / prj11 复现指南", 1)
r = r.replace("> **prj9 = 以太网 → Aurora 光回环**（无内存）；**prj10 = 在光口两侧各插一级 DDR4**（内存进环路）。",
              "> **prj9 = 以太网 → Aurora 光回环**（无内存）；**prj10 = 在光口两侧各插一级 DDR4**（内存进环路，路线 A）；"
              "**prj11 = 路线 B：MicroBlaze 控制面 + AXI DMA 数据面**（软核逐帧服务，DDR4+Aurora 双程；可编程/可观测）。", 1)
old_row = ("| **prj10 · 速率** | [复现_prj10_指南_2026-10-09.md](复现_prj10_指南_2026-10-09.md#第-9-步速率验证l1-乒乓泵修复后) | "
           "验证**帧泵乒乓修复后的速率上限**：1466B 帧 82.67k fps 零丢帧（≈969 Mbps 线速）；PRJ9 同款吞吐档 99.99%（修复前 51.45%）|")
new_row = old_row + ("\n| **prj11（路线 B）** | [复现_prj11_指南_2026-10-19.md](复现_prj11_指南_2026-10-19.md) | "
                     "软核控制面 + AXI DMA 数据面（S2MM 写 / MM2S 读，直接寄存器模式）：烧录体检 → S0–S11 一键（13/13 PASS）→ "
                     "四档/10MB+SHA/J3 → 速率量化（1466B 可持续 2000fps、上限≈2560fps）|")
if old_row in r:
    r = r.replace(old_row, new_row, 1)
    print("repro README row added")
else:
    print("WARN repro README row not found")
# prj11 专属坑 2 条
pit_anchor = "| 5 | 跑完 RND 用例后，后续依赖回显的测试「收到 0 片」 |"
extra = ("| 6 | **prj11 上电后 ping 不通 / 计数不动** | R2 设计 `g_dma_mode` 默认 0：无读/写服务 | 上电后先发一次 `'d'`（toggle，用 `'U'` 确认 mode=1），再 ping |\n"
         "| 7 | **prj11 J3 报 `wr+255`/收帧停摆** | J3 对板卡起始态（残留槽/backlog）敏感 | **重烧后再跑**，不重试（脚本会自动 'S'+'d'）|\n")
if "prj11 上电后 ping 不通" not in r:
    r = r.replace(pit_anchor, extra + pit_anchor, 1)
    print("repro README pitfalls added")
write(REPRO, r)

# AGENTS
ag = read(AGENTS)
lines = ag.splitlines()
idx = None
for i, ln in enumerate(lines):
    if "路线 B 收口后剩余（2026-10-19 重审" in ln:
        idx = i
        break
if idx is not None:
    lines[idx] = AG_NEW_BULLET
    ag = "\n".join(lines) + ("\n" if not ag.endswith("\n") else "")
    if AG_OLD_ROW_TAIL in ag:
        ag = ag.replace(AG_OLD_ROW_TAIL, AG_NEW_ROW_TAIL, 1)
    else:
        print("WARN AGENTS row tail not found")
    write(AGENTS + ".tmp", ag)
    os.replace(AGENTS + ".tmp", AGENTS)
    print("AGENTS updated")
else:
    print("WARN AGENTS bullet not found")

# docs 镜像
mirror_pairs = [
    (REC, os.path.join(DOCS, "调试记录", os.path.basename(REC))),
    (WL, os.path.join(DOCS, "操作文档", os.path.basename(WL))),
    (TODO, os.path.join(DOCS, os.path.basename(TODO))),
    (REPRO, os.path.join(DOCS, "复现", os.path.basename(REPRO))),
    (GUIDE, os.path.join(DOCS, "复现", os.path.basename(GUIDE))),
]
for src, dst in mirror_pairs:
    s = read(src).replace("15266", "***").replace("Xuegulin", "***")
    d = os.path.dirname(dst)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    write(dst, s)
    print("mirrored:", os.path.basename(dst), len(s.encode("utf-8")), "B")

# docs/README 索引：复现/（2 篇）→ 3 篇 + prj11 行
dr = read(DREADME)
dr = dr.replace("#### 复现/（2 篇）", "#### 复现/（3 篇）", 1)
anchor = "| [复现/复现_prj10_指南_2026-10-09.md](复现/复现_prj10_指南_2026-10-09.md) | prj10 复现指南 |"
if anchor in dr and "prj11 复现指南" not in dr:
    dr = dr.replace(anchor, anchor + "\n| [复现/复现_prj11_指南_2026-10-19.md](复现/复现_prj11_指南_2026-10-19.md) | prj11 路线 B 复现指南（S0–S11 13/13、四档/10MB、J3、速率量化）|", 1)
    print("docs README repro row added")
else:
    print("WARN docs README repro anchor not found (or already added)")
write(DREADME, dr)
print("ALL DONE")
