# -*- coding: utf-8 -*-
"""2026-10-19 重审落地：把路线 B 剩余工作/技术债的官方知识库复核结果写入
文档（记录 §二十一 / 剩余清单 §七 / 开工草案附注 / 短期待办更新 / AGENTS §十）
并同步 docs 脱敏镜像。本脚本只改文档，不改代码/判据。
"""
import io
import os
import shutil

VAULT = r"C:\Users\15266\Desktop\毕设"
REPO = r"D:\FPGA"
DOCS = os.path.join(REPO, "docs")

REC = os.path.join(VAULT, "调试记录", "阶段三_prj11_R2写侧S2MM换层_2026-10-17.md")
WL = os.path.join(VAULT, "操作文档", "阶段三_prj11_路线B剩余工作清单_2026-10-16.md")
DRAFT = os.path.join(VAULT, "操作文档", "阶段三_prj11_路线B软核与DMA开工草案_2026-10-10.md")
TODO = os.path.join(VAULT, "追踪_cross_短期待办_2026-10-10.md")
AGENTS = os.path.join(REPO, "AGENTS.md")
README = os.path.join(DOCS, "README.md")

MARK = "2026-10-19 重审"


def read(p):
    return io.open(p, "r", encoding="utf-8", newline="").read()


def write(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


# ---------------------------------------------------------------- 记录 §二十一
REC_SEC = r'''
## 二十一、路线 B 剩余工作与技术债重审（2026-10-19，接官方知识库核对）

> 触发：用户要求排除"规划期未接入官方知识库"造成的方向/必要性偏差。方法：把剩余清单每条判据拆成三层核对——①**工具是否真实存在** ②**官方文档是否支持该说法** ③**本工程落点是否一致**；官方依据按 AGENTS §二"两件套"（URL + family/version + 本工程落点）给出。

### 21.1 结论速览

| 项 | 原判据/表述 | 重审结论 | 必要性 | 量级 |
|---|---|---|---|---|
| R3 | `mentor_verify.py --ctl soft` 全过 + 吞吐/pace 三档 + 82.67k fps 基线（归因：DMA 描述符开销/中断延迟） | **回归半已由 S0–S11 13/13 覆盖**（S9=j3_fourchains M/A/B=导师四环节）；`--ctl soft` 工具不存在；归因两项均与实现不符（见 21.2）⇒ **只剩"速率量化"** | **保留（改写）** | 0.5 天（板 1 场次） |
| R4 | W6 三件套扩展 + 复现指南 B 章 + 文档三件套同步 + prj11 入仓清单 + 归档索引 0 缺失 | 三件套为 prj10 硬编码、不可直接用；"文档三件套"未定义 ⇒ 改为 prj11 口径四项（见 21.5） | **保留（改写）** | 0.5 天（离线） |
| D1 | W2/W4 联合 TB 改造成 DMA 版 | **已完成/不需做**：10-17 R1 已给两 TB 加 `.HAS_DMA(0)` tie 且三回归（含负向）全绿；prj11 另有 `r2_wr_tb`（T1–T9 PASS，规则号1 golden model 100 帧逐槽比对）覆盖 R2 写路径 | **结项** | 0 |
| D2 | 坑 #39 根治 + 撤 `rd_reg` 双读/哑写 | 方向正确但非收口阻塞：AXI4-Lite 从站须按本事务返回数据（官方时序），持续"读落后一笔"属协议级异常；当前 `dread`=3 读是吞吐成本 ⇒ 降为**可选诊断**并入 R3 | **降级（可选，0.5 天）** | 0–0.5 天 |
| K1 | 时序门限抖动风险 | 已形成 recipe（单掷 ExtraTimingOpt + ILA 裁剪 + retry/裁剪两级余量）；官方 UG906/WP480 也支持"指令集扫描评估收敛难度"，但 IDR（编译 2.5×）无必要 | **保留风险条** | 0 |
| K2 | 板卡 wedge ×2 未决 | R2 会话定案 = module-ref IP cache 陈旧（坑 #68，[L2 强推断]），全程未复现 ⇒ **结项**（机械证明可选：旧 cache 网表离线 TB 重放） | **结项** | 0 |

**路线 B 收口实际剩余 ≈ 1 天**（R3 板场次半天 + R4 离线半天），不含论文写作。

### 21.2 规划期幻觉逐条修正（3 条 + 证据）

1. **`mentor_verify.py --ctl soft` 不存在**。
   - 事实：`prj/project_10/prj_loop/scripts/mentor_verify.py` 的 `argparse` 只有 `--nslots/--seed/--pace-us/--mode/--fast/--mock/--pc-ip`，**无 `--ctl`**；它是 prj10 路线 A 的终端口径（引擎 = `j3_random_read.py`，PC 侧 UDP 下发）。
   - 由来：`--ctl soft` 是 2026-10-10 开工草案里 B2 的**计划改造**；prj11 实际改为 C 侧固件 + `scripts/j3_soft_verify.py`（软核控制下复现导师四环节），**B2 已于 10-12 收口**（J_B2 三轮全 PASS）。
   - 修正：B4/R3 回归判据改为 **S0–S11（run3 13/13 PASS）**，其中 S9 = `j3_fourchains`（M/A/B）即导师四环节的软核版；不移植 mentor_verify。
2. **"DMA 描述符开销"不成立——本工程是 Direct Register Mode，没有描述符**。
   - 官方：PG021《Direct Register Mode (Simple DMA)》——`C_INCLUDE_SG=0` 时传输由 DMACR/SADDR/LENGTH 寄存器写入启动，**无 descriptor fetch**；描述符环只在 SG 模式（CURDESC/TAILDESC）。URL：https://docs.amd.com/r/en-US/pg021_axi_dma/Direct-Register-Mode-Simple-DMA （family 含 Kintex UltraScale+，version All）。
   - 本工程落点：`scripts/create_bd_b.tcl` L111 `CONFIG.C_INCLUDE_SG {0}`；`sw/src_j3/main.c` 每帧写服务 = `S2MM_DMASR` 清中断 + `S2MM_SA/LENGTH` 编程 + 翻 GO，读服务 = MM2S 复位/RS/SA/LENGTH 编程。
   - 修正：正确的**每帧成本**归因 = ①MicroBlaze 经 AXI-Lite 的寄存器编程（每访问一次 `dread` = 3 次读，见坑 #39 缓解）②读服务里的**整引擎软复位**（PG021：MM2S_DMACR.Reset 复位整个 AXI DMA，环 R2 已踩）③轮询循环与 `busy_ms` 实时间隔 ④桥侧握手（GO/ACK/introut）。
3. **"中断延迟"不成立——s2mm_introut 没有接进 MicroBlaze**。
   - 事实：BD 里 `s2mm_introut` 只作为顶层输出端口（`create_bd_b.tcl` L167-168），**没有 axi_intc、没有 MB 中断连接**；固件是**轮询 DMASR**（`dread(&S2MM_DMASR)` 等），`IOC_IrqEn` 仅用于让 DMASR.IOC 置位。
   - 修正：归因写"轮询/服务延迟"；若真要上中断需改 BD（接 axi_intc 到 MB interrupt），属后续演进，不在收口范围。
4. （补充）**82.67k fps 基线的适用边界**：该数字是 prj10 路线 A 的**旁路帧泵**实测（1466B≈969 Mbps，`复现_prj10_指南 §第9步`）；路线 B 每帧都经软核服务，**不能作为同口径目标**，只能作"差距参照"。
5. （补充）**"pace 三档"原文档未定义**：prj9 口径只有质量档（1 ms）与吞吐档（13 µs）；本次明确为 **{1000, 200, 13} µs** 三档 + 0（纯循环）参考档。

### 21.3 过时/已完成项（从剩余清单删除）

- **D1**：prj11 `sim/w4_joint_tb.sv` 与 `sim/mem_bridge_tb.sv` 已在 10-17 R1 中显式 `.HAS_DMA(0)` 并回归——`w4_joint_tb` 正向 PASS（A/B 各 rd=148）/负向（DEFECT_ROUTING=1）按设计 FAIL、`mem_bridge_tb` PASS（rd_frame=585）、`bridge_dma_tb` PASS；R2 另有 `sim/r2_wr_tb.sv` PASS（T1–T9，101 提交，规则号1 golden model 100 帧逐槽比对）。"DMA 版 joint TB"无消费者（架构未再变），**撤销**。
- **K2**：见 21.1；楔死根因已定案（记录 §19.6）。
- **R3 回归半**：S0–S11 13/13 已覆盖（run3 日志），不再重复跑；R3 只做速率。

### 21.4 口径未定义项（改写）

- **"W6 三件套扩展"**：`w6_inventory.py`/`w6_healthcheck.py`/`w6_archive.py` 均硬编码 `project_10`（路径/四域 CSV/`VAULT` 路径），不能直接用于 prj11；prj11 已有等价物：`out/r2_counter_recon.py`（恒等式判据）、`EVIDENCE_INDEX_r3c.md`、各轮 `SHA256.txt`。⇒ R4 改为**只移植 inventory 思路**（自动生成 prj11 探针/计数清单），不搬另两件。
- **"文档三件套"**：全库无定义 ⇒ 改为显式清单：AGENTS §十 / 调试记录（本记录）/ 操作文档（剩余清单）/ docs 镜像+README / 短期待办。

### 21.5 方向性新发现（需与论文口径对齐）

1. **开题 4.2 写的是 "AXI DMA + 描述符环"**（开题报告 L197），而 R2 实现为 **Direct Register Mode（无描述符环）**。两者都合法：PG021 里 simple/direct 模式适合"逐笔软件启动"，SD 描述符环适合"链式批处理"。建议论文口径写成"首版直接寄存器模式 + 描述符环（SG）为后续演进"（依据：PG021 SG 模式；URL：https://docs.amd.com/r/en-US/pg021_axi_dma/Scatter/Gather-Mode-Register-Address-Map ），不要把未实现的功能写成既成事实。
2. **双板双链路**：开题时间线（第一阶段 2026-10）含"双板双链路组网"，但 2026-09-30 Q4 已定案**单板（暂不做双板）**；路线 B 是单板双笼回环。若论文仍按原时间线，需要**与导师确认范围已随单板决策调整**，否则这是比 R3/R4 大得多的下一阶段工作。

### 21.6 修订后的最小收尾计划

**R3 速率量化（0.5 天，板卡现成：round3d `F6012BA0` + perf1 ELF `BA3C0220`，模式 mode=1/engine=1）**
- 回归引用：S0–S11 run3 13/13（不重跑）；如需现跑，用 10-19 的 `r2_board.ps1` 命令。
- 速率曲线：`json_storm.py --chunk 1466` 跑 pace ∈ {1000, 200, 13} µs + 0 参考档，各档记录 recv/lost/corrupt/rtt/goodput，产出 fps–失配曲线并取"膝点"。
- 归因测量：①PC 侧吞吐/时延；②读固件事件环 `g_evt_n` 计数（事件/帧）+ `'I'/'U'` 计数差分给每帧服务调用次数；③ILA5/ILA3 抓 `dbg_wd_go_ui`→`dbg_s2mm_introut` 的 ui 域延迟（硬件路径），总帧周期减硬件延迟 = 软件服务成本；④静态核算（每帧 Lite 访问次数×3 读、寄存器编程次数、读服务整引擎复位）。
- 验收行：给出"路线 B 上限 = X fps / Y Mbps（1466B），瓶颈 = 每帧软件服务 Z µs；**无描述符/中断开销（未使用该机制）**；与路线 A 82.67k fps 的差距 = 软件介入手册化成本"，并给 2 条优化候选（删读服务整引擎复位 / 撤 3 读缓解）各自预期收益。
- 可选（0.5 天）：D2 原语读实验——固件加命令对同一已知寄存器做 N 次单读 vs 3 读比对，判定当前 netlist 是否仍存在"读落后一笔"，决定 3 读缓解能否撤。

**R4 文档收口（0.5 天，离线）**
- R4-1 `复现/复现_prj11_指南_2026-10-19.md`（烧 round3d/ELF、`'d'`、`U/W` 体检、S0–S11 一键命令、四档/10MB/J3 预期、坑：GO 后 1ms、S9 起始态敏感、Lite 读滞后）+ `复现/README.md` 索引行。
- R4-2 prj11 探针/计数清单自动生成（移植 `w6_inventory.py` 思路，扫 `scripts/build_debug.tcl`+`rtl/*.v` 的 `dbg_*`，输出 `out/W6_prj11_可观测性清单.md`；含 ILA/probe/宽度/域/判据归属）。
- R4-3 `out/archive/ARCHIVE_INDEX_prj11.md`：跨轮归档总表（每轮 key hash + SHA256.txt 有无 + 缺失说明）⇒ "0 缺失"以可核对形式成立。
- R4-4 文档同步：AGENTS §十 / 本记录 §二十一 / 剩余清单 §七 / 短期待办 / docs 镜像+README；CI PASS；提交。

### 21.7 官方依据（两件套）

| # | 依据 | URL | family/version 核对 | 本工程落点 |
|---|---|---|---|---|
| 1 | PG021 Direct Register Mode (Simple DMA)：无描述符，DMACR/SADDR/LENGTH 启动 | https://docs.amd.com/r/en-US/pg021_axi_dma/Direct-Register-Mode-Simple-DMA | FPGA/Kintex UltraScale+ 等；version All | `create_bd_b.tcl` `C_INCLUDE_SG=0`；固件每帧寄存器编程 |
| 2 | PG021 Performance：MM2S 399.04 MB/s、S2MM 298.59 MB/s @100 MHz（SG 默认配置口径） | https://docs.amd.com/r/en-US/pg021_axi_dma/Performance | 同上；version All | 本工程 512b@300MHz 且实测 ~0.92 MB/s ⇒ IP 非瓶颈，瓶颈在软件服务 |
| 3 | PG058 AXI4-Lite 单拍读写时序（从站按 AR 返回 RVALID/RDATA） | https://docs.amd.com/v/u/en-US/pg058-blk-mem-gen | All | 坑 #39"读落后一笔"若持续存在属协议级异常；`dread`=3 读是吞吐成本 |
| 4 | UG906 设计分析与收敛（IDR / QoR suggestions） | https://docs.amd.com/r/2025.1-English/ug906-vivado-design-analysis/Overview | All；version 2023.1–2025.1 | K1 不引入 IDR（编译 2.5×）；保留单掷 ExtraTimingOpt+裁剪 recipe |
| 5 | WP480 可重复时序收敛方法（多指令测量收敛难度） | https://docs.amd.com/v/u/en-US/wp480-timing-closure-methodology | All | 本工程 `build_v5_sweep2`/单掷扫描 = 同类做法 |
| 6 | UG1292 Timing Closure Quick Reference（timing baselining 流程） | https://docs.amd.com/v/u/2025.1-English/ug1292-ultrafast-timing-closure-quick-reference | version 2023.1/2023.2/2024.1/2025.1 | 本工程实现流程 = synth→post-place 报告→phys_opt→route→post-route phys_opt |
| 7 | PG021 SG 模式寄存器图（描述符环依据，仅作后续演进） | https://docs.amd.com/r/en-US/pg021_axi_dma/Scatter/Gather-Mode-Register-Address-Map | 同上 | 开题 4.2"描述符环"若实现需此模式；当前未实现 |

### 21.8 结语

R2 收口后，路线 B **只剩 1 天量级的收尾**（R3 速率量化 + R4 文档收口）；技术债 D1/K2 已结项、D2 降为可选诊断；同时清掉 3 处规划期幻觉（`--ctl soft`、描述符开销、中断延迟）与 2 处口径未定义（W6 三件套、文档三件套）。**论文口径另需对齐**：描述符环（开题）vs 直接寄存器模式（实现）、双板双链路（开题时间线）vs 单板决策。
'''

# ---------------------------------------------------------- 剩余清单 §七
WL_SEC = r'''
## 七、2026-10-19 重审（R2 收口后；接官方知识库核对，修正规划期幻觉）

> 触发：用户要求排除"规划期未接官方知识库"造成的方向/必要性偏差。完整复核（含官方 URL 两件套）见记录 `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` **§二十一**；本节只留执行口径。

### 7.1 重审后剩余工作（替代 §一/§三 的 R3/R4/D1/D2/K1/K2）

| # | 工作包 | 修订判据 | 必要性 | 量级 |
|---|---|---|---|---|
| **R3** | 速率量化（回归半已由 S0–S11 覆盖） | `json_storm --chunk 1466` pace ∈ {1000,200,13} µs + 0 参考档 → fps–失配曲线膝点；固件事件环计数 + ILA GO→intr 硬件延迟 + 静态成本核算 ⇒ **每帧软件服务成本分解**；验收行给出"路线 B 上限 X fps/Y Mbps + 瓶颈=软件服务 + 优化候选收益" | 保留（改写） | 0.5 天（板 1 场次） |
| **R4** | 文档/可观测性收口 | ①`复现/复现_prj11_指南_2026-10-19.md`+README；②prj11 探针/计数清单自动生成（移植 w6_inventory 思路，非搬三件套）；③`out/archive/ARCHIVE_INDEX_prj11.md` 跨轮索引 0 缺失；④AGENTS§十/记录§二十一/本清单/docs 镜像同步 | 保留（改写） | 0.5 天（离线） |
| ~~D1~~ | ~~W2/W4 TB 改 DMA 版~~ | 已由 10-17 `.HAS_DMA(0)` tie + 三回归（w4_joint 正 PASS/负 FAIL、mem_bridge PASS、bridge_dma PASS）+ `r2_wr_tb` PASS 覆盖 | **结项** | 0 |
| **D2** | 坑 #39 根治 | 降为**可选诊断**并入 R3：单读 vs 3 读对比实验，判定当前 netlist 是否仍有"读落后一笔"⇒ 决定 3 读缓解能否撤（吞吐收益） | 可选 | 0–0.5 天 |
| **K1** | 时序抖动 | 保留风险条（recipe 已固化：单掷 ExtraTimingOpt + ILA 裁剪 + retry）；不引入 IDR | 保留风险条 | 0 |
| ~~K2~~ | ~~wedge ×2~~ | 根因定案 = module-ref IP cache 陈旧（坑 #68）；R2 全程未复现 | **结项** | 0 |

**⇒ 路线 B 收口剩余 ≈ 1 天**（不含论文写作）。

### 7.2 规划期幻觉/过时项（3+2 条，证据见记录 §21.2–21.4）

1. `mentor_verify.py --ctl soft`：**工具无此参数**（prj10 脚本参数仅 --nslots/--seed/--pace-us/--mode/--fast/--mock/--pc-ip）。B2 实际由 `scripts/j3_soft_verify.py` 落地（10-12 收口）；B4 回归以 **S0–S11 13/13**（S9=j3_fourchains）为准。
2. "DMA 描述符开销"：**不成立**——`C_INCLUDE_SG=0` = Direct Register Mode，无 descriptor（PG021 Direct Register Mode 页）。修正归因：每帧 MicroBlaze 寄存器编程（含 3 读缓解）+ 读服务整引擎复位 + 轮询/busy_ms。
3. "中断延迟"：**不成立**——`s2mm_introut` 仅到顶层（无 intc/MB 中断），固件轮询 DMASR。修正为"轮询/服务延迟"。
4. "W6 三件套扩展"：三脚本硬编码 project_10（路径/四域 CSV/vault 路径），**不可直接复用**；prj11 已有 `r2_counter_recon.py` + `EVIDENCE_INDEX` + 各轮 SHA256 ⇒ 只移植 inventory 思路。
5. "文档三件套"：全库未定义 ⇒ 改为显式清单（AGENTS§十/记录/操作文档/docs镜像+README/短期待办）。
6. "pace 三档"：原未定义 ⇒ 明确 {1000, 200, 13} µs（prj9 质量档/吞吐档口径 + 中速）+ 0 参考档。
7. "82.67k fps 基线"：真实但属 prj10 旁路帧泵（1466B≈969Mbps），**不能作路线 B 同口径目标**，仅作差距参照。

### 7.3 方向性对齐（论文口径）

- 开题 4.2 写"AXI DMA + **描述符环**"，实现为 **Direct Register Mode（无描述符环）** ⇒ 论文写成"首版直接寄存器模式 + SG 描述符环为后续演进"（PG021 SG 模式为依据），勿把未实现写成既成事实。
- 开题时间线（第一阶段 2026-10"双板双链路"）与 2026-09-30 **Q4 单板定案**不一致 ⇒ 需与导师确认范围调整；这是比 R3/R4 更大的下一阶段内容。
'''

# ---------------------------------------------------------- 开工草案附注
DRAFT_NOTE = r'''
---

> **2026-10-19 附注（R2 收口后重审）**：本草案 B2 的 "`mentor_verify.py --ctl soft`" 属计划期表述——实际 **B2 已由 `scripts/j3_soft_verify.py`（软核控制下导师四环节）于 10-12 收口**；B4 回归半由 **S0–S11 13/13**（S9=j3_fourchains）覆盖，速率部分按《剩余工作清单》**§七 重审版**执行（归因口径已修正为"每帧软件服务/轮询"，本工程 `C_INCLUDE_SG=0` 无 DMA 描述符、`s2mm_introut` 未接 MB 中断）。详见记录 §二十一。
'''

# ---------------------------------------------------------- 短期待办更新
TODO_NOTE = r'''
## 2026-10-19 更新（R2 收口 + 路线 B 剩余重审）

- ✅ **R2 收口**：round3d `F6012BA0`（WNS+0.002/WHS+0.004）+ S0–S11 **13/13 PASS**；固件 `s2mm_rearm` 修掉 50% 丢帧；楔死根因=module-ref IP cache 陈旧（坑 #68）。
- ⏭️ **路线 B 剩余 ≈ 1 天**（重审版，替代原 R3/R4 描述）：**R3 速率量化**（0.5 天，板场次；pace {1000,200,13}µs+0 参考档 → 膝点 + 每帧软件服务成本分解；**无描述符/中断开销**——本工程 Direct Register Mode、introut 未接 MB 中断）+ **R4 文档收口**（0.5 天；复现指南 B 章 / prj11 探针清单 / 跨轮归档索引 / AGENTS+记录+docs 同步）。
- ✅ 结项：D1（W2/W4 TB 改造已完成）、K2（wedge 根因定案）。D2（坑#39）降为可选诊断并入 R3。
- ⚠️ 论文口径待对齐：开题 4.2 "描述符环" vs 实现 Direct Register Mode；开题时间线"双板双链路" vs 2026-09-30 单板定案。详见记录 §二十一。
'''

# ================================================================ 执行
if MARK in read(REC):
    print("record already patched, skip record")
else:
    s = read(REC).rstrip("\n") + "\n" + REC_SEC
    tmp = REC + ".tmp21"
    write(tmp, s)
    assert os.path.getsize(tmp) > os.path.getsize(REC)
    os.replace(tmp, REC)
    print("record §二十一 appended, size=", os.path.getsize(REC))

if "## 七、2026-10-19 重审" in read(WL):
    print("worklist already patched, skip")
else:
    s = read(WL).rstrip("\n") + "\n" + WL_SEC
    write(WL + ".tmp7", s)
    assert os.path.getsize(WL + ".tmp7") > os.path.getsize(WL)
    os.replace(WL + ".tmp7", WL)
    print("worklist §七 appended, size=", os.path.getsize(WL))

if "2026-10-19 附注（R2 收口后重审）" in read(DRAFT):
    print("draft already patched, skip")
else:
    s = read(DRAFT).rstrip("\n") + "\n" + DRAFT_NOTE
    write(DRAFT + ".tmpnote", s)
    os.replace(DRAFT + ".tmpnote", DRAFT)
    print("draft note appended, size=", os.path.getsize(DRAFT))

if "2026-10-19 更新（R2 收口 + 路线 B 剩余重审）" in read(TODO):
    print("todo already patched, skip")
else:
    s = read(TODO).rstrip("\n") + "\n" + TODO_NOTE
    write(TODO + ".tmpupd", s)
    os.replace(TODO + ".tmpupd", TODO)
    print("todo update appended, size=", os.path.getsize(TODO))

# ---------------------------------------------------------------- AGENTS §十
ag = read(AGENTS)
new_bullet = (
    "- ⏭️ **路线 B 收口后剩余（2026-10-19 重审，官方知识库核对）**：R2 已收口（上条：round3d `F6012BA0` + S0–S11 13/13）。"
    "剩余仅 **≈1 天**：**R3 速率量化**（0.5 天，板场次；`json_storm --chunk 1466` pace {1000/200/13}µs + 0 参考档 → fps–失配腿点；"
    "归因**修正**：本工程 `C_INCLUDE_SG=0`=Direct Register Mode **无描述符**（PG021），`s2mm_introut` **未接 MB 中断**（BD 无 intc，固件轮询 DMASR）"
    "⇒ 瓶颈=每帧软件服务/轮询，**不是**\"描述符/中断开销\"；82.67k fps 系 prj10 旁路帧泵基线，仅作差距参照）+ "
    "**R4 文档收口**（0.5 天；复现指南 B 章 / prj11 探针-计数清单（移植 w6_inventory 思路，非搬 prj10 三件套）/ 跨轮归档索引 0 缺失 / AGENTS+记录+docs 同步）。"
    "**已结项**：D1（W2/W4 TB 改造已由 10-17 端口 tie + 回归完成，且 `r2_wr_tb` PASS）、K2（wedge 根因=IP cache 陈旧，坑 #68）、"
    "`mentor_verify --ctl soft` 判据不存在（B2 已由 `scripts/j3_soft_verify.py` 落地，S9 覆盖）。**D2（坑#39）**降为可选诊断并入 R3。"
    "**论文口径待对齐**：开题 4.2 \"AXI DMA+描述符环\" vs 实现 Direct Register Mode（建议写\"首版直接寄存器 + SG 为后续演进\"）；"
    "开题时间线\"双板双链路\" vs 2026-09-30 Q4 单板定案。详见记录 `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` **§二十一** 与剩余清单 **§七**。"
)
lines = ag.splitlines()
idx = None
for i, ln in enumerate(lines):
    if "路线 B 未决三项（下一步）" in ln:
        idx = i
        break
if idx is None:
    print("WARN: old AGENTS bullet not found")
else:
    lines[idx] = new_bullet
    ag2 = "\n".join(lines)
    if not ag2.endswith("\n"):
        ag2 += "\n"
    write(AGENTS + ".tmp", ag2)
    os.replace(AGENTS + ".tmp", AGENTS)
    print("AGENTS bullet replaced at line", idx + 1)

# project_11 行状态替换
ag = read(AGENTS)
old_row_tail = "**当前位流 `a432addd…a023`（v3 版，WNS +0.004）待上板板验**；未决 = 板卡 wedge ×2 · 坑 #39"
new_row_tail = ("**2026-10-19：R1/R2 已收口（round3d `F6012BA0` WNS+0.002/WHS+0.004 + S0–S11 13/13 PASS）；"
                "剩 R3 速率量化 + R4 文档收口（≈1 天，重审版见剩余清单 §七/记录 §二十一）；D1/K2 结项、D2 可选、坑#39 降级**")
if old_row_tail in ag:
    ag = ag.replace(old_row_tail, new_row_tail, 1)
    write(AGENTS + ".tmp2", ag)
    os.replace(AGENTS + ".tmp2", AGENTS)
    print("AGENTS project_11 row updated")
else:
    print("WARN: project_11 row tail not found")

# ---------------------------------------------------------------- README 索引
rd = read(README)
pairs = [
    ("| [操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md](操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md) | 路线 B 剩余工作清单（2026-10-16 基线） |",
     "| [操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md](操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md) | 路线 B 剩余工作清单（2026-10-16 基线；**2026-10-19 重审**：R3/R4 修订、D1/K2 结项、3 处规划期幻觉修正——见 §七） |"),
    ("| [操作文档/阶段三_prj11_路线B软核与DMA开工草案_2026-10-10.md](操作文档/阶段三_prj11_路线B软核与DMA开工草案_2026-10-10.md) | 阶段三 · prj11 路线 B 实施单 v1.0 —— 软核 + C 控制 + AXI DMA（MicroBlaze 控制面正式版） |",
     "| [操作文档/阶段三_prj11_路线B软核与DMA开工草案_2026-10-10.md](操作文档/阶段三_prj11_路线B软核与DMA开工草案_2026-10-10.md) | 阶段三 · prj11 路线 B 实施单 v1.0 —— 软核 + C 控制 + AXI DMA（MicroBlaze 控制面正式版；**2026-10-19 附注**：B2/B4 判据按重审版修正） |"),
]
for old, new in pairs:
    if old in rd:
        rd = rd.replace(old, new, 1)
        print("README row updated:", old[:40])
    else:
        print("WARN README row not found:", old[:50])
write(README + ".tmp", rd)
os.replace(README + ".tmp", README)

# ---------------------------------------------------------------- docs 镜像
mirror_pairs = [
    (REC, os.path.join(DOCS, "调试记录", os.path.basename(REC))),
    (WL, os.path.join(DOCS, "操作文档", os.path.basename(WL))),
    (DRAFT, os.path.join(DOCS, "操作文档", os.path.basename(DRAFT))),
    (TODO, os.path.join(DOCS, os.path.basename(TODO))),
]
for src, dst in mirror_pairs:
    s = read(src)
    # 脱敏（本批文档当前无 15266/Xuegulin，保险起见再跑一次）
    s = s.replace("15266", "***").replace("Xuegulin", "***")
    write(dst, s)
    print("mirrored:", os.path.basename(dst), "->", len(s.encode("utf-8")), "B")

print("ALL DOC PATCHES DONE")
