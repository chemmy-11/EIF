# R3C 楔死根因候选集（lite AXI 楔死 + S2MM 写侧零 commit）

- 产出：rtl-auditor（独立审计，只读；未碰板、未启动 Vivado 工程/综合/实现）
- 快照时间：2026-10-19 12:02–12:10（Lead 的 round3c 综合进行中）
- 依据等级：L4 定案 / L3 板证 / L2 对照成立（≥2 方向正交对照）或同版本实物直证 / L1 相容假说 / L0 猜测（AGENTS §6a）
- **本文件不产生"判定/根因"结论**：除明确标 L2 的对照结论外，全部为候选假说 + 判别签名，待 round3c 的 ILA4/ILA5 上板判读。

---

## 0. 证据基线与可靠性重估（必须先读）

### 0.1 round3b 本轮证据清单与局限

| 证据 | 内容 | 等级/局限 |
|---|---|---|
| `out/evidence_2026-10-19/R2_ila_wed1_ui_pre.csv`（1024 行） | ILA3@ui_clk 静态快照：`calib=1`；`mem_wm/mem_wr_frm/mem_rd_frm/mem_stall/mem_len_err/mem_ost=0`；`mem2_*=0`；`s2mm_state=0(IDLE)`；`tvalid=0`；`tready=1` | L2（原始数据） |
| `R2_ila_wed1_user_pre.csv`（2048 行） | ILA0@user_clk 静态快照：`mem_u_wr=2`、`mem_u_rd=0`、`mem2_u_wr=0`、`s2mm_reqpend=0`、`wr_fault=0`、`pfwd_en=0` | L2（原始数据） |
| `R2_ila_wed2_ui_pre.csv` / `..._user_pre.csv` | 同上，`mem_u_wr=6`；其余全 0；窗口内**零跳变**（本审计逐列统计 `nchanges=0`） | L2 |
| `out/r3b_ilacap_wed{1,2}.log` | 仅抓到 ILA0/ILA3 两核（`R2CAP_ILA_TOTAL: 3` 但只 GRAB UI/USER）；**round3b 的 ILA5 从未被采集**（无 ILA5 CSV） | L2（工具事实）→ 故"零 commit"结论只由 user 镜像计数 + ui 计数器支撑，**没有直接观测 GO/introut/tvalid 时刻** |
| `out/r3b_*_diag.log` | LMB 变量快照 | 旧版工具存疑；**新版 r3c_diag（符号校验+3读）已证其值真实，但内容是"陈旧值"（见 §0.2 更新与 §E.1）** |

**结论**：wed1/wed2 快照只能证明"捕获时刻系统静止、无 commit、引擎 IDLE、无 fault"；**不能区分** "从未 arm/GO" 与 "WAITGO 超时后已回 IDLE"。这是 round3c ILA5 probe5 存在的全部意义。

### 0.2 LMB 快照不可信（重要，修正输入事实）

> **2026-10-19 晚更新（见 §E.1）：本结论已修正。** 新版 `r3c_diag.tcl` 已做 **mb-nm 符号表地址校验（mismatch=0）+ 同址 3 读 stable=1**，`0x80010056` 是**真实 LMB 内容**（不再是坑 #54 工具伪影）；但该值本身是"读回数据陈旧/冻结"的**证据**（5 个不同变量同值）。本节以下"不可信"判据只对**旧版脚本（地址未校验、跨址单读）**成立，保留作历史推导。

`out/r3b_{wa,step,v3,v4}_diag.log` 由 `out/evidence_2026-10-18/tools/r2_step_diag.tcl` 类脚本经 JTAG `mrd` 读取（地址 0x450c–0x4534，每地址先哑读 2 次取第 3 次）。实测值：

```
r3b_v4_diag.log : PC=0x738  WA_S2CR=80010056 WA_S2SR=80010056 WA_S2LEN=80010056 WA_S2SR2=0
                  WA_S2LEN2=0 WA_WREQ=80010056 WA_WDBG=80010056 WA_CNT=1 WA_DONE=0 G_STEP=0x0b
r3b_v3_diag.log : G_STEP=0x11 WA_CNT=0；r3b_step_diag.log: G_STEP=0x0e WA_CNT=0
r3b_wa_diag.log : WA_CNT=0（16D06BD3 固件，无 g_step）
```

不合理点（任一都足以否定其作为判据）：

1. **值与语义不符**：`S2MM_DMACR` 在 `s2mm_channel_init` 后应为 `0x00001001`（RS+IOCEN）；`S2MM_DMASR` 应 ∈ {0x0, 0x1, 0x1002, 0x1000/0x0002 等}；`S2MM_LENGTH` 的 bit31 保留为 0。`0x80010056` 一个都对不上。
2. **同一值出现在 5 个不同地址**（S2CR/S2SR/S2LEN/WREQ/WDBG 全为 `0x80010056`）——与 AGENTS 坑 #54（JTAG mrd 跨地址连读混叠）同型；而 `0x80010056` **恰好解码为 `dma_wr_req` 镜像格式** `{pending=1, toggle=0, slot=0x01, len=0x56=86}`，说明它极可能是**某一地址的真值被搬到别的标签下**。
3. **跨版本矛盾**：同一脚本同一位流，`WA_CNT` 在 16D06BD3/step 两套固件上读 **0**，在 v4 上读 **1**；地址表由 `mb-nm` 在会话中途更新过（脚本 11:46:50 修改）。
4. 判据未获得 ≠ 判据通过（AGENTS §6a 硬规则 3）：`WA_CNT=1` 曾被用作"首个写服务已完成（LENGTH+GO 已写入）"的证据 —— **该前提本审计不予采信**，降为 L1/未证。

### 0.3 `g_step=11` 的精确含义（live ELF F5E0F1F3）

`sw/j3_soft/src/main.c`（43211 B，11:47:40，ELF `F5E0F1F3`）`serve_write_once()`：

```
:322  g_step = 10u;
:323  v_dbg = dread(&R_WRDBG);   // +0x44, 3 连读
:324  g_step = 11u;              // ← 观测到 11 说明已过 R_WRDBG 读
:325  if (v_dbg & 0x80000000) {...}
:335  v_req = dread(&R_WRREQ);   // +0x40, 3 连读 ← g_step=11 时卡在这里
:336  g_step = 12u;
...
:364  g_step = 13u;
:365  S2MM_LENGTH = len;         // 写 LENGTH = 启动 S2MM
:366  g_step = 14u;
:367  g_wr_last_toggle = tog;
:368  R_WRGO = 1u;               // 翻 GO（lite_regs +0x48 写）
:369  g_step = 15u;
:372  busy_ms(20);               // 实测时基：busy_ms(1)≈0.15ms（坑 #51）→ ≈3ms
:373  g_step = 16u;
:374  g_wa_s2len = dread(&S2MM_LENGTH);  … :383 g_step = 19u; :384 busy_ms(1);
```

⇒ `G_STEP=0x0b` = **卡在读 +0x40 的 3 连读里，且发生在 LENGTH/GO 之前**。若这是该帧的**第一次** `serve_write_once` 调用，则 **GO 从未写出**（见 §1 D1/D2）。

---

## 1. 【Lead 指定】round2f `wm=5` vs round3b/诊断固件 `wm=0` 的矛盾分析

### 1.1 变量对齐（同一对照只差一个变量）

| # | 位流（RTL） | 固件 | GO 前是否插入了 Lite 读 | 板端观测 | 证据/等级 |
|---|---|---|---|---|---|
| ① | **8A8FE378**（round2f：bridge `c92c20c7` / fmi `96d5b136` / **lite fix1 `d133b508`** / top `1885225f`） | **f8cf4022**（纯，无 GO 后间隔） | 否（仅 `dread` WRDBG/WRREQ 预读） | `'d'`+ping 后 **AXI 楔死**（marker：PC 停 `lread` +0x40，`G_ADDR=44a00040`；UART 静默） | `R2_round2f_board_session_20261018.md:13-15` [L2 板证] |
| ② | 同上 8A8FE378 | **b614a2dc**（= f8cf4022 + **GO 后 `busy_ms(1)` 间隔**；`round3` 归档 main.c 39493 B/ELF 50944 B） | 否 | **连续多次 'd'+ping 不再楔死**；`dbg_mem_wm/wr_frm/rd_frm=5/5/5`、`mem2_*=5/5/5`、`WR_DBG.last_commit_len=86` | 同上 `:15-17` [L2 板证] |
| ③ | 同上 8A8FE378（**同一颗位流**） | **16D06BD3**（f8cf4022 基线 + **在 `S2MM_LENGTH` 与 `R_WRGO` 之间插入 5×`rd_reg`** + LMB 快照 + 10ms 慢轮询 + 'W'） | **是**（5 个 `rd_reg`，每个含哑写 + `busy_ms(1)` + 2 读 ⇒ ≈15 笔 Lite 事务） | `'d'` 正常；**第一次 ping 后 UART 立即静默**；`WA_CNT=0` ⇒ **写服务一次都没执行到** ⇒ 无 GO ⇒ 无 commit | `R2_official_tool_diagnosis_20261018.md:25-29` [L2 板证] |
| ④ | **02F7153A**（round3b：bridge/fmi 同 ①，**lite fix2 `d5d16d46`**，top+探针 alias） | 16D06BD3 / 2288FA40 / A613FBAD / **F5E0F1F3(v4)** | ③ 是；v4 已把 GO 移回 LENGTH 之后、但仍保留 GO **之前**的 WRDBG/WRREQ 预读 | 不同固件卡在不同 Lite 点：g_step=0x0e（GO 写附近）/0x11（DMA 读）/0x0b（+0x40 读）；wed2 快照 `wm=0`、`state=0`、`tvalid=0` | `out/r3b_*_diag.log`、wed2 CSV [L2 观测；因果 L1] |

### 1.2 结论（按证据强度排序）

- **[L2 对照成立] ③ vs ②：同一颗位流（8A8FE378）+ 仅换固件 ⇒ commit 由 5 变 0。** 16D06BD3 的差异核心是**把 5 个 Lite 读插到 `LENGTH`（启动 S2MM）与 `GO`（桥放流）之间**，且把 `WA_CNT++` 移到这些读之后。板端 `WA_CNT=0` 直接证明**连自增都没到**，即 **GO 从未写出**。⇒ **"诊断固件在 GO 前加读"足以独立打破 commit 链**（不需要位流变化）。这是"round2f wm=5 vs 诊断固件 wm=0"的**首选解释**。
- **[L1，待 round3c 判别] ④：round3b（lite fix2）+ v4 仍 `wm=0` 的原因**。v4 已恢复 GO-first，但仍保留 GO 之前的 2 次 `dread`（+0x44/+0x40）与 stale 复核 `dread`（+0x40）。`g_step=0x0b` 表明它卡在**预读**里 ⇒ 若该次为首次服务，则 **GO 从未写出**，零 commit 仍是"楔死先于 GO"的下游症状。相反，若上板证明该次之前已有成功服务（WA_CNT 可靠），则要转向引擎侧（§3 Z2/Z3）。
- **[L1，当前证据不支持] "lite fix2 把 commit 链打破"**：没有"同位流、仅 fix1↔fix2"的对照；且 fix1（①）与 fix2（④）**都**在 +0x40/0x34 读楔死（①的 marker 就是 `44a00040`）。fix2 是"仍不够"，不是"变坏"。⇒ **不得**把 wm=0 归因于 lite fix2 或位流回退。
- **反向约束（防错归因）**：②证明 **S2MM 写引擎 + GO 协议在 round2f 位流上能 commit**；④的 bridge/fmi RTL 与 ②**逐字相同**（round2f 归档 `rtl_axi4_master_bridge.v` 69591 B = blob `c92c20c7`；`rtl_frame_mem_if.v` 31954 B = `96d5b136`；round3b 同）。⇒ 若 round3c 显示 GO 已到桥而引擎不 commit，才是"引擎/位流侧零 commit"；否则不得写成引擎问题。

### 1.3 可判别签名（ILA5 probe5 专为此设计）

| 观测（ILA5 probe5 / 快照） | 结论方向 | 对应候选 |
|---|---|---|
| `dbg_wd_go_ui == 0` 且（楔死后快照仍 0） | **GO 从未到桥** ⇒ 零 commit = 上游（firmware 预读楔死/lite 楔死）下游症状；引擎与位流洗清 | §3 Z1；§1 D1/D2 |
| `dbg_wd_go_ui == 1` 且 `dbg_wd_intr_ui == 1` | GO 已到，但 `s2mm_introut` 粘滞高 → 桥 `WD_WAITGO` 条件 `!s2mm_introut` 永不满足 | §3 Z3 |
| `dbg_wd_go_ui == 1` 且 `dbg_wd_go_ok == 0` | GO 电平已翻但桥内 `wd_go_seen` 没捕捉到（2FF/复位失配） | §3 Z1b |
| `dbg_wd_go_ui == 1`、`go_ok == 1`、`state` 长时间 = 1(WAITGO) | 条件二（`wf_level >= wd_len`）不满足 | §3 Z2 |
| `state` 2→3（STREAM/PUSH）且 `tvalid` 有拍、`tready` 有拍、`intr_ui` 不来 | S2MM 未完成（IP 编程/参数/流内容） | §3 Z4b |
| `state` 6（HALT）或 `wr_fault=1` | 桥 fail-stop（STREAM/PUSH/WAITDONE 超时）——注意 WAITGO 超时**不置 fault** | §3 Z5/Z6 |

**round3c 必须做的两拍**：① `'d'` 前 arm ILA5（触发 `go_ui==1` 上升）→ 抓 GO 边沿后 3.4µs；② 楔死后 `R2_SNAPSHOT_ONLY=1` 抓 ILA0/3/4/5 静态电平（`go_ui/intr_ui/state` 在快照里直接读）。

---

## 2. lite AXI 楔死候选集（H1–H6）

> 共同事实（代码级 [L2]）：lite 是 **4 相电平邮箱 + 2FF**（`axi_lite_regs.v:120-153`），两侧时钟/复位不同源：aclk 侧 `aresetn` = BD `peripheral_aresetn`；user 侧 `rst_user_n = ~aurora_rst`，而 `aurora_rst = ~sys_rst_n | ~link_ok`、`link_ok = channel_up & channel_up_b`（`aurora_mem_bridge.v:207-210`，实例连接见 `:676,704,717,819,976`）。**邮箱任何一侧单独复位/时钟停，另一侧即无超时死等**（读 `LR_RACK/LR_DRQ`、写 `LW_EXEC`），AXI 事务永不响应 ⇒ MicroBlaze `lwi/swi` 永久挂起（本次 PC 停 `lwi` 的现象级）。

### H1【高·代码级 L2；板端 L1】邮箱无超时 + 两侧复位失配

- 机制：读在 `LR_RACK` 等 `r_ack_s[1]`（`:305-314`）、`LR_DRQ` 等 `d_req_s[1]`（`:315-322`）；写在 `LW_EXEC` 等 `a_ack_s[1]`（`:233-241`）。三者均无超时。若 user 侧因 `link_ok` 短暂丢失而复位（或 `clk_user` 因 MMCM 失锁停振），aclk 侧永远等不到回程。
- 反向补充：user 侧复位同时清掉 `cfg_wr_go/cfg_wr_ack/cfg_mode`（`:351-352`）——即 **GO 协议状态也会被 link 抖动清零**，即使 aclk 侧没卡，GO 语义也已错。
- ILA4 签名：`lrst=1(LR_RACK)`+`r_req=1`+`r_ack_s1=0`（bit31 置位），或 `lrst=2(LR_DRQ)`+`d_req_s1=0`；写侧 `lwst=1`+`a_req=1`+`a_ack_s1=0`（bit32 置位）；**bit29（rst_user_n 2FF）在触发窗口内出现 0**、bit30 sticky=1。
- 排除法：若 ILA4 显示 `rst_user_n` 全程 1 且邮箱位闭合，则排除本项。**不能**用"复位没发生"的先验排除——本板 link_ok 是两通道 AND，抖动未观测过。
- 支持：代码结构 [L2]；`link_ok` 依赖两个 Aurora 通道 [L2]；round3b 无 `dbg_ch_up` 探针（旧 ILA0 有，本轮 101b 裁掉）⇒ **当前无链路状态观测**，是本轮盲区。
- 反对：若 user 侧持续复位，`mem_u_wr` 计数不会到 6（wed2 观测到 6）⇒ 至少捕获时刻 user 域在跑；但"曾瞬时复位"仍可能。
- 等级：机制 **[L2 代码]**；本板发生 **[L1]**。

### H2【高·L1】axi_interconnect M01 读写串行/流水窗口（跨 IP 协议组合）

- 机制：M01 是 AXI4→AXI4-Lite 转换器 + `fix2` 的单拍 ready/严格串行门控。fix2 让从机在"写未完全关闭（`lwst!=IDLE`/`aw_pending`/`w_pending`/`bvalid`）"期间**不受理 AR**（`:289-290`）。若转换器/主机在写通道仍有未完成事务时推进 AR，从机会让 ARREADY 保持 0，转换器正确做法是等；但**转换器内部若把 AR 与 AW/B 跟踪耦合**，可能出现双方互等（经典跨 IP 组合死锁）。
- 已有同族证据：坑 #36（SmartConnect M01 写转换 × 自研 Lite 从机真硬件楔死，已换 axi_interconnect）、坑 #39（axi_interconnect M01 读"一笔滞后"——最终归因到旧 lite_regs 重复 R 握手，但说明 M01 转换层行为敏感）。
- ILA4 签名：`arvalid=1`、`arready=0` 长期（bit33 置位），而 `lrst=0(IDLE)`、`lwst` 可能=0 或非 0；邮箱 22-27 可能全 0（AR 未受理）；若 `bvalid=1,bready=0`（bit8=1,bit9=0）则属 H4。
- 排除法：若 ILA4 显示 AR 被受理（arvalid&arready 握手）后卡在邮箱（H1 签名），则 H2 排除；若 AR 根本没出现（H3 签名），也排除 H2。
- 等级：L1（是本次"写后紧接读"现象最直接的结构候选，但无探针实证）。

### H3【中·L1】MicroBlaze/上游挂死（AR 从未到 lite_regs）

- 机制：MicroBlaze 卡在更上游（自身 AXI-DP 排队、异常/中断、或 interconnect 主端跟踪错位），M01 从机侧收不到 AR。PC 停在 `lwi` 与之一致。
- ILA4 签名（H-ARnever）：`arvalid=0`、`arready=1`、`rvalid=0`、`lrst=lwst=0`、邮箱全 0、`aresetn=1`；**无触发**（stuck_or 需要 arvalid 或 FSM 非 IDLE）。
- 排除法/利用法：这正是"stuck_or 触发 + 快照"双模式的用武之地。若 ILA4 触发+波形显示全 idle ⇒ H3 升主因；若触发在 H1/H4 签名 ⇒ H3 排除。
- 注意：**H3 无法用"A 侧没看到 ⇒ B 侧坏"来证明**（归因三禁）；只能收敛候选集。
- 等级 L1。

### H4【高·L1】写通道 B/R 响应未被消费 ⇒ fix2 串行化门控冰封

- 机制：`s_axi_bvalid` 只在 `bvalid&&bready` 时清（`:188`），而读受理条件含 `!s_axi_bvalid`（`:290`）。若主端（互联转换器）在某个窗口内 `bready=0`，B 挂住 ⇒ **后续所有读永远不被受理** ⇒ `lwi` 永久挂。同理 `rvalid=1 && rready=0` 会让 `LR_IDLE` 的 `!s_axi_rvalid` 门控阻止新 AR。
- 现探针覆盖：`bvalid=bit8`、`bready=bit9`、`rvalid=bit2`、`rready=bit3` 都在 ILA4 总线上，**可用快照直接读出该形态**；但**当前无 sticky 检测位**（stuck_or 不覆盖"bvalid 静默挂住"），所以依赖快照。
- ILA4 签名（H-bstuck）：`bit8=1,bit9=0`；`lwst=2(LW_CLOSE)` 或 IDLE；`arvalid=1,arready=0` + bit33；无 bit31/32。
- 等级 L1（fix2 门控是 [L2 代码]；该形态是否发生待快照）。

### H5【中·L1】lite_regs 内部残余协议窗口

- 静态复核结论（fix2 后）：在**合法 AXI 主端行为**下未发现确定性死锁点 [L2 代码]。逐项核过：AW/W 单拍 ready（`:197-212`）、B 串行化（`:197,205`）、AR 单拍 ready 且与写事务串行（`:289-304`）、R/B 握手即撤（`:188,276`）、四相邮箱各自闭合（`:305-328,340-469,474-532`）。**残余**：
  1. 读受理条件里 `!s_axi_bvalid` 与写通道 `bvalid` 清条件的组合（H4）；
  2. 读在 `LR_IDLE` 受理当拍**同时**允许写通道推进（两邮箱并行是设计允许的，但若主端在写事务中途撤/重发 AW，fix2 的 ready 单拍可能吞掉一笔——属主端非法行为，不列为缺陷）；
  3. **无超时**本身（H1 的使能条件）。
- 签名：假握手（`awvalid&awready` 同拍而 `lwst!=0`；或 `arvalid&arready` 同拍而 `lrst!=0`）——fix2 后理论上不应出现；若 ILA4 原始波形出现即协议缺口。当前无专用 sticky，需看波形（触发可选 `stuck_or` 后窗口内识别）。
- 等级 L1。

### H6【低·L1】`clk_user` 停振/MMCM 失锁

- 机制：`user_clk` 来自 Aurora 例程 MMCM；若失锁停振，user 侧全部停止 ⇒ 邮箱不闭合（与 H1 同签名），且 `mem_u_wr` 冻结。
- 签名：ILA4 与 H1 相同（`rst_user_n` 可能仍=1，因复位来自 link_ok 而非 MMCM locked！⇒ **rst 位不暴露时钟停振**，需 user 侧 liveness 证明）；ILA0/ILA5 完全静止。
- 排除法：若 ILA4 波形中 `rst_user_n=1` 且 aclk 邮箱永远等不到 ack，而 ILA0（user_clk）在楔死后仍能触发/有活动 ⇒ 时钟没停，转 H1。**建议 round3d 增加 `clk_user` 活性观测**（例如把 user 侧一个翻转位 2FF 进 aclk）。
- 等级 L1/L0。

### 2.1 H 候选的判别优先级（建议按此顺序读 ILA4）

1. 先看 **bit29/30**（复位是否动过）→ H1/H6；
2. 再看 **lrst/lwst + 邮箱位**（谁在等谁）→ H1 具体通道；
3. 再看 **bit8/9**（B 未消费）→ H4；
4. 再看 **bit0/1**（AR 有没有来/受不受理）+ 是否触发 → H2（AR 在接口悬置） vs H3（AR 未到）；
5. 最后才考虑 H5（假握手/协议窗口）。

---

## 3. S2MM 写侧零 commit 候选集（Z1–Z6）

> 事实基线：写引擎与 round2f 逐字相同（§1.2），且 ② 已证明其可 commit（`wm=5/5/5`、`last_commit_len=86`）[L2 板证]。因此 Z 候选的**先验**是"GO/条件链"而非"引擎结构性缺陷"。引擎关键代码：`axi4_master_bridge.v:711-756`（WD_WAITGO 条件与超时）、`:758-768`（WD_ARM）、`:770-803`（WD_STREAM，字节流水 + 56ms 超时→HALT）、`:805-830`（WD_PUSH）、`:832-853`（WD_WAITDONE，commit 在此 `:833-842`）、`:855-869`（WD_DRAIN）；GO/ACK/intr 2FF 在 `frame_mem_if.v:454-527`。

### Z1【首选·L1】GO 未到桥（`dbg_wd_go_ui` 恒 0）

- 机制：固件在写 GO 之前被 Lite 读楔死（§1 D1/D2）；或 GO 写本身被吞（H4/H1 形态）。则引擎永远停在 WD_WAITGO → 56ms 超时（`:745-751`）→ `wd_req_pending<=0` → WD_DRAIN → IDLE。**超时路径不置 fault、不清 pending 之外的计数**（`wr_timeout_r` 未上探针）⇒ 与"从未启动"在旧探针下不可区分。
- ILA5 签名：`probe5.go_ui=0` 全程；`state=0` 或 1；`intr_ui=0`；`tvalid=0`；`wr_fault=0`。快照同。
- 排除/确认：round3c ILA5（arm 在 'd' 前）抓到 `go_ui` 上升与否即定。
- 等级 L1（有 ③/② 对照与 g_step 支持，缺 GO 直接观测）。

### Z1b【低·L1】GO 电平已翻但桥内 `wd_go_seen` 未捕捉

- 机制：WD_WAITGO 首拍 `wd_go_seen <= dma_wr_go`（`:722`）；若此时 GO 已翻（例如复位后基线不齐、或 GO 在引擎进入 WAITGO 之前就翻了），引擎会等"下一次翻转"——但该帧已无 GO 可等 ⇒ 超时。固件 `'d'` 处理器在读 WRREQ 后对 `g_wr_last_toggle` 做过基线对齐（`main.c:612-617`），理论上避免；但若读陈旧值，仍可能。
- 签名：`go_ui=1`（电平）而 `go_ok=0`，`state=1` 超时前；快照 `go_ui=1,go_ok=0`。
- 等级 L1。

### Z2【中·L1】`wf_level < wd_len`（整帧字节不可见）

- 机制：WD_WAITGO 完成条件 = `go_ok && (wf_level >= wd_len[12:0]) && !s2mm_introut`（`:742`）。`wf_level` 是 user→ui 同步指针的保守字节数；若写侧 FIFO 指针同步/满度异常（或 len 异常大），条件永不满足 → 56ms 超时 → DRAIN。
- 签名：`state` 长时间=1(WAITGO)、`go_ui=1`、`go_ok=1`、`intr_ui=0`；`tvalid=0`；超时后状态回 0、pending=0。**当前探针读不到 wf_level/timeout**，只能靠 state 时序间接判。
- 等级 L1；round3d 需补 `stat_wr_timeout` sticky（1b）或 `wf_level`。

### Z3【中·L1】`s2mm_introut` 粘滞高 ⇒ WAITGO 条件 `!introut` 永不满足

- 机制：桥在 `!s2mm_introut` 时才进 ARM（`:742`）。若 axi_dma 的 S2MM introut 因旧 IOC 未清/错误位（DMAIntErr 等）/复位序列不干净而恒高，引擎永远等。固件每次 arm 前写 `S2MM_DMASR=IOC`（W1C）清 IOC（`main.c:352`），并 `s2mm_channel_init` 里清过一次（`:313`）——但若楔死使这些写没生效/顺序错，仍可能。
- 签名：ILA5 `intr_ui=1` 在 GO 前后保持；`state=1` 或超时后 0；`go_ui=1,go_ok=1`。
- 等级 L1（**probe5 的 `intr_ui` 就是为此设计**）。

### Z4【低·L1】桥 ui 域复位/calib 失配（`wd_desc_av` 不成立）

- 机制：`wd_desc_av = (wdst==WD_IDLE) && calib_ok && !wd_empty`（`:621`）。若 `ui_rst_n` 脉冲（MIG 校准重跑等）清掉引擎/FIFO 指针，或 `calib_ok=0`，引擎根本不取描述符。
- 签名：ILA3 `dbg_calib=1` 已证 calib OK（wed1/wed2 全 1）⇒ 本项弱；若 ILA3 在 round3c 看到 calib 掉 0，则升级。
- 等级 L1（现有观测反对）。

### Z5【中·L1】WAITGO 超时 → DRAIN 循环（"形似从未启动"）

- 机制：见 Z1/Z2/Z3 的超时出口。`state` 回 0、`fault=0`、`pending=0`，但 `wr_timeout_r` 已累加（未上探针）。多帧会逐个耗 56ms。
- 签名：与 Z1 相同的静态态；区别在 **GO 级别**（Z5 有 GO 翻转历史、Z1 没有）与 **state 曾=1** 的边沿证据。因此必须"arm 在序列前"才能区分。
- 等级 L1。

### Z6【低·L1】固件读到陈旧 pending → 从未 arm（空转）

- 机制：`dread()` 3 连读仍可能拿到滞后值（坑 #39：2 读不够，3 读是经验值；互连/负载变化下不保证）。若读成 `pending=0`，`serve_write_once` 直接 return（`main.c:337-338`），不发生任何写/GO。
- 签名：与 Z1 同（go_ui=0），但 ILA4 侧应显示"Lite 读成功返回"（AR/R 握手完整）而非卡死；`wr_fault=0`、`s2mm_state=0`。
- 等级 L1；区别手段=ILA4 是否卡死。

### 3.1 推荐判读顺序（ILA5 快照 + ILA4 交叉）

```
go_ui==0 ?
 ├─ 是 → Z1/Z6：零 commit 是上游（固件预读/楔死）症状；结合 ILA4 是否卡死区分 Z1(卡死) vs Z6(Lite 正常但读了旧值, 需 firmware 证据)
 └─ 否 → intr_ui==1 ? → Z3
          ├─ go_ok==0 ? → Z1b
          └─ go_ok==1 && state==1 持续 → Z2（或 Z3 的 level 未采样到）
若 state 2/3 有活动而 intr_ui 不来 → S2MM 未完成（Z4b: IP/编程/流内容；参考 out/ip_sim_r2 期望 DMASR=0x1002、LENGTH=86）
若 fault=1 → Z5 类超时（STREAM/PUSH/WAITDONE 超时，桥已 HALT）
```

---

## 4. 判读矩阵（供 round3c 板验逐条对号）

### 4.1 lite 楔死（ILA4）

| 形态 | ILA4 关键位 | 结论 |
|---|---|---|
| **H-ARnever** | `arvalid=0, arready=1, rvalid=0, lwst=lrst=0`；邮箱 22-27=0；无触发 | 上游（MCU/互联/时钟）问题，非 lite_regs |
| **H-acklost** | `lrst=1,r_req=1,r_ack_s1=0`（bit31）或 `lrst=2,d_req_s1=0`；或 `lwst=1,a_req=1,a_ack_s1=0`（bit32）；看 bit29/30 | 跨域邮箱复位失配/死等（H1） |
| **H-bstuck** | `bvalid=1,bready=0`（bit8/9）；`lwst=2`；`arvalid=1,arready=0`（bit33）；无 bit31/32 | B 响应未被消费冰封（H4） |
| **H-rvalid** | `rvalid=1,rready=0`（bit2/3）；`lrst=3(DACK)`；bit34 | 响应已回、主端不取（H2/H4 变体） |
| **H-false-hs** | 同拍 `awvalid&awready` 而 `lwst!=0`，或 `arvalid&arready` 而 `lrst!=0`（需原始波形） | lite_regs 协议残余窗口（H5，fix2 后理论上不应出现） |

### 4.2 S2MM 零 commit（ILA5 probe5 + ILA3）

| 形态 | ILA5 关键位 | 结论 |
|---|---|---|
| go_ui 全程 0 | `probe5[0]=0`；state=0；intr=0；无 tvalid | GO 未到桥（Z1/Z6）→ 上游症状 |
| go_ui=1, intr=1 | `probe5[0]=1,probe5[2]=1`；state=1 | introut 粘滞（Z3） |
| go_ui=1, go_ok=0 | `probe5[0]=1,probe5[3]=0` | GO 电平未被桥捕捉（Z1b） |
| go_ui=1, go_ok=1, state 长时间 1 | `probe5[0]=1,[3]=1`；state=1；tvalid 可能=0 | wf_level 不足（Z2） |
| state 2/3 有拍、tvalid/tready 活动、intr 不来 | state∈{2,3}；`probe2/3` 有脉冲；`probe5[2]=0` | S2MM 未完成（Z4b）；查 IP 编程/SA/LEN/流内容（ip_sim_r2 期望） |
| fault=1 或 state=6 | `dbg_wr_fault=1`；state=6 | 桥 fail-stop（STREAM/PUSH/WAITDONE 超时，Z5 的 fault 分支） |
| state=0、pending=0、fault=0、go_ui=1 | 静态快照 | WAITGO 超时后已回 IDLE（Z5）——**与 Z1 的区别只看 GO 历史** |

---

## 5. round3c 板验建议（离线建议，供 Lead 采用）

1. **时序**：同一 Vivado hw_manager batch 会话内完成 arm+capture（arming 易失，AGENTS §六.2）。
2. **ILA5**：在 `'d'` 之前 arm（触发 `dbg_wd_go_ui==1`），随后 `'d'` → `'W'` → ping 1 → 等 3–5s → 若未触发则 `wait_on_hw_ila -timeout 1`（单位分钟，坑 #66）超时后按步骤 4 抓快照。
3. **ILA4**：在 `'d'` 之前 arm（触发 `dbg_l_stuck_or==1`），同会话等触发；触发位置取 512/1024（前后各半）。
4. **楔死后快照**：`R2_SNAPSHOT_ONLY=1` 抓 ILA0/3/4/5 静态电平——这是判断 H-ARnever / H-bstuck / go_ui=0 的关键（stuck_or 不触发时的唯一证据）。
5. **串口/串行纪律**：ping 前先看 `'U'` 基线；ping 后不再穿插 AXI 读（坑 #44），先抓 ILA 再跑 `r3c_diag.tcl`（diag 的 JTAG 读按坑 #54 每地址哑读）。
6. **不要用 LMB 快照当判据**（§0.2）；diag 只作辅助（`g_step/PC` 可用于确认卡死点，但同样受 JTAG 读口径影响，需 r3c_diag.tcl 的符号表核对+哑读）。
7. 若 ILA4 触发但 ILA5 无 GO：**先修 lite 楔死/固件预读顺序，再谈 S2MM**（引擎已由 round2f ② 洗清到 L2）。

---

## 6. 待证清单（round3c 后应闭环/降级）

| # | 待证 | 需要的观测 | 当前等级 |
|---|---|---|---|
| 1 | GO 是否到桥（`go_ui`） | ILA5 probe5（arm 在 'd' 前）+ 楔死快照 | L1 → L2/L3 |
| 2 | lite 楔死形态（H-ARnever/H-acklost/H-bstuck/H-rvalid/H-false-hs） | ILA4 触发+快照 | L1 → L2/L3 |
| 3 | `rst_user_n` 是否在楔死窗口内动过 | ILA4 bit29/30 + 波形时标 | L1 → L2 |
| 4 | `s2mm_introut` 是否粘滞 | ILA5 probe5[2] | L1 → L2 |
| 5 | WAITGO 超时是否发生（Z5） | round3d 加 `stat_wr_timeout!=0` sticky（本轮无） | 未测 |
| 6 | `wf_level >= wd_len`（Z2） | round3d 加 wf_level 探针（本轮无） | 未测 |
| 7 | round2f ②（b614a2dc→wm=5）与 round3b 差异的位流侧贡献 | 同位流 + 同固件的 2×2（建议 round3d 补） | L2（固件侧）/L1（位流侧） |

---

## 7. 关键 file:line 索引

- lite fix2：`rtl/axi_lite_regs.v:188`（bvalid 握手即撤）、`:197-212`（AW/W 单拍 ready）、`:233-247`（LW_EXEC/CLOSE）、`:276`（rvalid 握手即撤）、`:289-304`（AR 单拍 + 写事务串行门控）、`:305-331`（LR_RACK/DRQ/DACK）、`:340-469`（user 命令 FSM，无超时）、`:474-532`（user 读快照 FSM，无超时）、`:590-601`（rst_user_n 2FF，缺 ASYNC_REG）、`:607-641`（round3c 卡死检测）。
- 复位：`rtl/aurora_mem_bridge.v:207-210`（link_ok/aurora_rst）、`:676,704,717,819,976`（rst_user_n 连接）。
- 写引擎：`rtl/axi4_master_bridge.v:621`（wd_desc_av）、`:711-756`（WAITGO 条件 `:742`、超时 `:745-751`）、`:758-768`（ARM）、`:770-803`（STREAM）、`:805-830`（PUSH）、`:832-853`（WAITDONE/commit `:833-842`）、`:855-869`（DRAIN）、`:872-883`（HALT）。
- 2FF 镜像：`rtl/frame_mem_if.v:454-527`（go/ack/intr/req/dbg 五组同步器）。
- 固件：`sw/j3_soft/src/main.c:141-150`（dread 3 读）、`:158-164`（rd_reg：哑写+0.15ms+2 读）、`:318-386`（serve_write_once；g_step 映射见 §0.3）、`:389-414`（serve_any）、`:599-621`（'d' 处理器）、`:567-577`（空闲环 10ms 慢轮询）。
- 固件差分证据：`out/archive/b31b_r2_2026-10-18_round3/main.c`（39493 B = b614a2dc）vs `out/archive/b31b_r2_2026-10-19_round3b/main.c`（42653 B = 16D06BD3），`git diff --no-index` = +60/−3 行；关键插入块在 `S2MM_LENGTH` 与 `R_WRGO` 之间。
- 板端对照：`out/evidence_2026-10-18/R2_round2f_board_session_20261018.md:13-17`（②，wm=5/5/5）、`out/evidence_2026-10-18/R2_official_tool_diagnosis_20261018.md:25-29`（③，WA_CNT=0）。

*本文件由 rtl-auditor 产出；除 §1.2 标 L2 的对照结论外，均为待 round3c 判读的候选假说，不写成"根因/判定"。*

---

## §E 2026-10-19 新实验（round3b + P/J/K 单变量 + JTAG 现场 + ILA 复演）

> 本节回应 Lead 的新证据与 Q1/Q2。所有文件均在 `out/evidence_2026-10-19/` 下；本审计**未碰板**，仅只读解析。等级：L2=日志/数据直证；L1=相容假说（未做对照或机制未证）；L0=猜测。

### E.0 新增证据清单与等级

| 证据 | 内容 | 等级 |
|---|---|---|
| `R3C_serial_ping_rehearsal.txt`（round3b bit `02F7153A` + ELF `F5E0F1F3`） | `'U'`(618B 正常)→`'d'`(DMAMODE now=DMA)→`'W-pre'`(正常：s2cr=00011003/s2sr=0/s2len=0/wreq=01000048/wdbg=0)→`ping 1`(timeout) → **post 12s + W-post 2.5s + U-post 2.5s 全 0 字节** | L2 |
| `R3C_diag_rehearsal_round3b.log` / `...2.log`（新版 r3c_diag） | mb-nm 符号表 **mismatch=0**、同址 3 读 **stable=1**：G_STEP=0x0b、GDMA_MODE=1、G_DMA_SERVICE=0、G_WR_LAST_TOGGLE=0、WA_CNT=1、WA_DONE=0、**WA_S2CR=WA_S2SR=WA_S2LEN=WA_WREQ=WA_WDBG=0x80010056**；PC=0x738 | L2（数据） |
| `R3C_lmb_dump_rehearsal.log` | 连续 LMB dump：0x4510/0x4514/0x4518=2147549270(0x80010056)×3，0x451c/0x4520=0，0x4524/0x4528=0x80010056，0x452c=1，0x4534=11；每地址 3 次读一致 | L2 |
| `R3C_elf_disasm.txt` + `R3C_elf_symtab.txt` | `uputc`=0x718：0x72c..0x73c = `addik r3,0x40600000; lwi r3,8; andi r3,8; bnei` ⇒ **PC=0x738 = UART_ST 的 TX_FULL 轮询循环内**；diag 显示 stop 前 `PC_RUNNING=0x730`（循环体内），resume 后仍 0x730 | L2 |
| `R3C_jtag_axi_probe_rehearsal.log` | 经 MicroBlaze 目标 `mrd` 读 0x44A0001C/0x44A00018/0x44A00040/0x44A00044/0x44A10030/0x44A10034/0x44A10058/0x44A10004/0x44A10028/0x44A10000 **全部报 `data read overrun` / `instruction insert overrun`**；PC 0x738→0x748→0x738 | L2（现象）/L1（解释） |
| `R3C_cap_rehearsal_console.log` + `R3C_r3breh_ILA*_{pre,post}.csv`（12:43） | 3 核（round3b 位流）；**未发 `'d'`**（cap 脚本只跑 `R2_STIM_CMD=ping`；12:43 烧的 ELF 为 PGC 版，`g_dma_mode` 默认 0）⇒ CPU 不服务；ILA5 `dbg_s2mm_tvalid` 60s 无触发；ILA0 `u_wr` pre=1→post=2（帧进写口）、ILA3 `state=0/wm=0/reqpend=0/fault=0/tready=1` | L2（工具/数据） |
| Lead 口述（P/J/K 实验，ELF `DB88C9D0`） | `'P'`（M02 写 SA/IOC/LENGTH+读）**不楔死**、s2len=0x56 正确；`'J'`（M02 写 + 读 WRREQ + M02 LENGTH + **M01 GO** + 20ms + 读）**不楔死**、读正常；`'K'` 未跑 | L1（**未见归档串口原文**，建议补 `R3C_serial_PJ.log`） |
| `R3C_ab_round2f_burn.log`（12:56） | Lead 已开始同位流对照：round2f `8A8FE378` + `DB88C9D0` | L2（动作已发生，结果待出） |

### E.1 对上一版结论的修正（重要）

1. **LMB 快照从"不可信"改为"可信但内容是陈旧值"**：新 r3c_diag 有符号表校验（`R3C_SYMTAB_MISMATCH: 0`）+ 同址 3 读一致，说明 `0x80010056` 确实是 LMB 里的值；但 5 个不同变量同值、且该值 = 固件在 `LENGTH/GO` 之前读到的 **WRREQ 值**（`{pending=1,toggle=0,slot=1,len=86}`）——DMACR/DMASR/LENGTH 不可能同时等于它。⇒ 这是**读回数据陈旧/冻结**的直接证据，不是 JTAG 工具伪影。[L2 数据 / L1 机制]
2. **"round3b ILA5 60s 无触发 ⇒ 桥从未发流"不成立**：该复演**没发 `'d'`**（cap 脚本只 ping；且 12:43 烧的是 PGC 固件、默认 `g_dma_mode=0`），此时 CPU 根本不服务写请求（P/J 结论同向：无服务=无 GO=无流）。并且 cap 复演前板子已重新烧录（12:41/12:43），**不能回溯 12:39 wedge 时刻的桥状态**。⇒ 修正为："round3b 的 ILA5 从未在**已发 'd'、已 arm、且真实服务**的窗口内被观测"；**"fix2/位流是否阻断 GO→流"仍是开放候选**，必须用 round3c 位流（ILA4 + probe5）判。
3. **`g_step=11` 的两种读法**（上一版 §0.3 只写了"卡在 WRREQ 读"）：F5E0F1F3 中 `g_step=11` 也覆盖 **`v_dbg` 读到 bit31=1 后的 `WRFAULT recover` 分支**（该分支在 11→12 之间，含 `uputs` + `s2mm_channel_init` + `R_WRACK`）。结合 `g_wa_wdbg=0x80010056`（bit31=1，陈旧值），**"固件被陈旧 WRDBG 误判为 fault → 进入打印/恢复路径"是与 PC=0x738 自洽的候选**。[L1]
4. 同理 `WA_CNT=1` 现在可解释为：一次 serve 执行完（LENGTH+GO 已写、快照读到陈旧值、计数++）；**GO 是否被桥消费/是否产生流仍未观测**。

### E.2 Q2：P/J 不楔死 vs 真实服务楔死 —— 候选与 ILA4/ILA5 签名

**单变量差异**：真实服务 = ①有 pending 写请求 ②固件写 LENGTH（启动 S2MM）+ GO ③**桥真正进入 STREAM → axi_dma S2MM 开始向 DDR 写数据**。P 无流（LENGTH 后无数据）；J 无待服务请求（GO 对 IDLE 引擎无效果）⇒ 两者都没有 "桥→S2MM→DDR 写" 活动。

| # | 候选 | 等级 | 签名（round3c 可观测） | 排除/确认实验 |
|---|---|---|---|---|
| **K1** | **真实 STREAM / S2MM DDR 写活动是触发条件**（不是 GO 写本身，也不是帧到达本身） | L1（P/J vs 真实=单变量对照，机制未证） | ILA5 `probe2 tvalid` 出现 >0 拍、`probe5` 出现 state=STREAM(2)/PUSH(3)，且**此后** CPU 读路出现陈旧值；P/J 对照无 tvalid | 同位流 2×2：round2f bit + 同 JK 固件（Lead 在跑）；若 round2f 也楔死 ⇒ 与 fix2 无关，指向 K1 板级/系统机制 |
| **K2** | **读回数据冻结在"最后读到的值"**（跨 M01/M02 从机；退化的坑 #39） | L2（5 变量同值跨从机）＋L1（机制） | ILA4 若显示 lite 的 AR/R 握手**正常完成**（读被受理、RVALID 回）而软件仍读旧值 ⇒ 故障在 ILA4 观测点之外（互联/DP/CPU）；若 ILA4 显示读未成 ⇒ 从机侧 | 固件加"读回值写入 LMB 环形日志"（不打印、无 UART 依赖）；或读同一寄存器 3 次看是否恒为同一陈旧值 |
| **K3** | **固件把陈旧 WRDBG.bit31 误判为 fault** → `WRFAULT recover` 打印/复位循环（`g_step=11`） | L1 | ILA5 若显示 GO→STREAM 后桥已 commit（state 回 0、intr 脉冲）而 CPU 仍挂 ⇒ 固件/读路问题；ILA4 侧无 stuck | 固件用 `+0x50`（round3d 新增）或把 fault 判定改为"连续 N 次 bit31=1"；或打印改 LMB 计数器 |
| **K4** | **UART TX 停摆**：PC 在 `uputc` TX_FULL 轮询循环（0x72c–0x73c），且 `PC_RUNNING=0x730`（CPU 活着）⇒ 不是"单笔 load 永久挂死"；是 TX FIFO 不排空 / TX_FULL 读恒忙 / 固件陷入打印自旋 | L2（PC/反汇编）＋L1（机制） | ILA0/ILA3 仍可被 JTAG 抓取（ILA 独立于 CPU）⇒ 说明 fabric/ILA 没死；UARTLite 状态需另测 | 连续 COM5 抓取（不重开端口）；固件改成"不打印、只翻 LED/写 LMB 计数"的版本；若 UART 静默但 LMB 计数继续涨 ⇒ K4 成立（AXI 存活、仅 UART/打印问题） |
| **K5** | **桥侧 GO→STREAM 未发生**（GO 未到桥 / WAITGO 条件不满足 / introut 粘滞） | L1（round3b 无 probe5/ILA4，**当前不能判**） | ILA5 probe5：`0011001`=GO 到但 WAITGO 未放流；`0011101`=intr 粘滞；`0000001`=GO 到但引擎 IDLE；全 0=GO 未到 | round3c bit 上板（Q1 spec） |
| **K6** | lite fix2 单独阻断 GO | **弱化（反对证据）**：J 在**同一 fix2 位流**上做了 M01 GO 写且不楔死 ⇒ GO 写路径本身正常 | — | round2f 同位流对照（Lead 正在做）+ round3c ILA5 probe5 判 GO 是否到桥 |
| **K7** | BD/MMCM 复位失配（pma_init/peripheral_aresetn 中途复位） | **证据反对**：`pma_init` 是上电 128 init_clk 的一次性移位（`aurora_mem_bridge.v:383-387`），`reset_pb` 仅按键；中途无来源 | ILA4 bit28/30 若在楔死窗口掉 0 才成立 | 快照看 bit28/bit30 |

**综合倾向（不写成判定）**：P/J 对照把变量收敛到"真实 STREAM→DDR 写"；K1 与 K2/K3/K4 可以是一条链：真实服务 → 桥 STREAM/DDR 写 → （板级 PDRC-203/UART 同 bank 干扰 或 fabric 读回异常）→ CPU 读回陈旧值 → 固件误判 fault 打印 → UART TX 停摆/自旋。**K2 的"跨从机同值"是本轮最硬的新观测**：它把"lite_regs 内部协议缺陷"进一步降级（若是 lite_regs 单点，M02 的 DMA 寄存器读不应同值），指向 **MicroBlaze DP 读回 / axi_interconnect S00 读数据路径 / 系统级**。

**Q2 直接回答（"UART_ST 读挂死说明什么"）**：反汇编 + PC 采样显示 PC 在 `uputc` 的 **TX_FULL 轮询循环内、且 CPU 可被 stop/resume 后仍在 0x730** ⇒ 不是"某笔 UART_ST load 永不返回"的简单挂死，而是 **CPU 活着但 TX 侧不排空（或状态读恒忙）**；若固件实际处于 `WRFAULT recover` 打印分支，则"串口全静默"更可能是 **UART TX 输出链路停摆/打印自旋**，而非 CPU 总线死锁。JTAG 经 CPU 的 AXI `mrd` 全部 overrun 只能说明"调试 AXI 通道取不到数"，不能单独证明 fabric 楔死（也可能是 CPU 忙循环无法响应指令插入）——按 L1 处理。

### E.3 Q1：现有 round3c 位流（不改拆）的触发配置建议

**位序（依据 `build_synth_only.tcl:230-237` 的 nets5c 顺序 + `connect_debug_port` LSB-first）**：
`probe5[0]=dbg_wd_go_ui, [1]=dbg_wd_ack_ui, [2]=dbg_wd_intr_ui, [3]=dbg_wd_go_ok, [6:4]=dbg_s2mm_state[2:0]`（`state[0]=bit4`）。
桥写引擎状态编码（`axi4_master_bridge.v:576-577`）：IDLE=0, WAITGO=1, STREAM=2, PUSH=3, WAITDONE=4, DRAIN=5, HALT=6, ARM=7。

**推荐触发（r3c_cap 的 per-ILA spec，全部在 `'U'→'d'→'W'→ping` 序列之前 arm）**：

| Run | ILA5 触发 spec | 含义/判据 | ILA4 触发 |
|---|---|---|---|
| **A（首选）** | `R2_TRIG_ILA5='dbg_wd_go_ui=eq7'b0011001'`（按 ltx 实际 probe 名，见下注） | **GO 已到桥且 go_ok=1、仍停 WAITGO**（持续窗口，稳）⇒ GO→流被引擎条件挡住（Z2/Z3） | `probe1 stuck_or=eq1'b1` |
| **B** | `R2_TRIG_ILA5='dbg_s2mm_tvalid=eq1\'b1'`（单 bit probe2，**最稳**） | 桥真的向 S2MM 推了 beat ⇒ 进 STREAM/PUSH | same |
| **C** | `...probe5 = eq7'b0011101`（go_ui=1,intr_ui=1,go_ok=1,WAITGO） | WAITGO 被 `s2mm_introut` 粘滞挡住（Z3） | same |
| **D** | `...probe5 = eq7'b0000001`（go_ui=1，其余 0） | GO 到但引擎 IDLE（无请求/已 DRAIN）——**仅 1 拍窗口，补充用** | same |
| **E** | `...probe5 = eq7'b1001001`（state=WAITDONE=4, go_ok=1, go_ui=1） | 引擎已等到 intr 但未 commit/或 commit 后异常（Z5） | same |
| **F** | 无触发：`R2_SNAPSHOT_ONLY=1` 全核 trigger_now | 楔死后静态判 H-ARnever/H-bstuck/读冻结/GO 电平 | — |

**关于 Lead 提的 `eq7'b0010001`**：它 = `go_ui=1,go_ok=0,WAITGO` = "GO 上升沿当拍、go_ok 还没置位"，**只存在 1 个 ui 周期**（下一拍 go_ok 就置 1），基本靠运气采样到，**建议改用 `eq7'b0011001`**（`go_ok=1` 后持续到放流/超时，窗口 μs~56ms 级）。

**注意事项（不改位流）**：
- ILA5 的 packed probe5 名字在 ltx 里可能不是 `dbg_wd_go_ui`（多 net 打包探针由 Vivado 命名）。**先 `write_debug_probes`/读 ltx 确认 probe5 的实际名与宽度=7**，r3c_cap 按 literal 子串匹配；若匹配不到，用 `probe5` 字面名或直接退到 Run B（tvalid 单 bit 名一定可匹配）。`R2C_EXPECT_WIDTH_ILA5=82`（75+7）。
- ILA4 的 probe0=36b 打包**不建议**用精确匹配触发：值含 bit28=`aresetn`、bit29=`rst_user_n`(2FF)、bit30=`rst_user_n_evt`(sticky，上电后可能一直=1) ⇒ 精确 pattern 极脆弱。若一定要用：+0x40 读受理 = bits0,1,11,28,29 = **`eq36'h030000803`**（9 个 hex 位；以 bit30=0 且其余位为 0 为前提）；GO 写受理 = bits4,5,15,28,29 = **`eq36'h030008030`**（同前提）。默认仍用 probe1=stuck。
- 当前 4 个 stuck 检测位已覆盖"读侧 BVALID 冰封"的常见形态（主端会持续举 ARVALID ⇒ `arvalid&&!arready` 256 拍触发），但**漏**：AR 从未发出、AW 半锁存且主端只举 AWVALID、纯写挂（lwst=IDLE 但 bvalid 卡）——这正是 round3d 补 4 位的原因。
- `CONTROL.TRIGGER_MODE` 在 2023.1 硬件侧只读（rehearsal 日志 `R3C_SET_WARN ... is read-only`）⇒ r3c_cap 已 catch，按默认 BASIC_ONLY；多 probe AND 用 `CONTROL.TRIGGER_CONDITION AND`（坑 #66）。

**若允许重建（最小改动：只动 build 脚本，不动 RTL/BD）**：
1. ILA5：把 `probe5` 的 7 网拆成 5 个 probe（go_ui / ack_ui / intr_ui / go_ok / state[2:0]）——总位数不变（82b），只改 `create_debug_port`+`connect_debug_port` 连接；触发可写 `go_ui==1 AND go_ok==1 AND state==3'b001`（三条件 AND）。
2. ILA4：把 `probe0` 36b 按语义拆 6 个 probe（AXI 握手 10b / 地址解码 8b / FSM 4b / 邮箱 6b / 复位+sticky 3b / stuck 4b，另加 probe1=|stuck）；总位数不变（36b），ILA4 在 100MHz 无时序风险；触发可写 `arvalid&&arready`、`bvalid&&!bready`、`aw_pending` 等单 bit 组合。
3. 连带改动：`probes.ltx` probe 布局/CSV 列名变化 → `r3c_cap.tcl` 的 `R2C_EXPECT_WIDTH_*` 与 `r3c_ila_analyze.py` 的列名映射需同步；不涉 RTL/BD/XSA。**建议直接并入 round3d 构建**，不必为本轮重开。

### E.4 round3c 上板最小序列（结合本轮修正）

1. burn round3c bit（4 核）+ 固件（F5E0F1F3 或 DB88C9D0 均可；P/J 实验表明固件本身不是主变量）。
2. **同一 Vivado hw_manager 会话**：先 `R2_SNAPSHOT_ONLY=1` 抓全 4 核 PRE；再 arm（Run A 或 B：ILA5 + ILA4 stuck），**然后**发串口 `'U'→'d'→'W'`，再 `ping 1`。
   （**纪律**：不 arm 完再补发 'd'——arming 前 CPU 不服务时无流，会复演 12:43 的"假阴性"。）
3. `wait_on_hw_ila -timeout 2`（分钟，坑 #66）；触发则 upload POST；超时则 stop + trigger_now 快照（楔死静态）。
4. 如触发 A/B/C/E：按 §4.2 判读；如仅快照：按 §4.1 ILA4 判读 H 形态 + ILA5 probe5 电平判 GO 是否到桥。
5. 楔死后**连续串口抓取 ≥30s**（不重开端口）验证 K4；再跑 `r3c_diag.tcl`（已含符号校验/哑读）取 G_STEP/PC/快照。
6. 建议补记：P/J/K 各命令的**串口原文**与 LMB dump（本轮 P/J 只有 Lead 口述，等级仅 L1）。

### E.5 待证清单增补

| # | 待证 | 观测 | 等级 |
|---|---|---|---|
| 8 | 真实 STREAM 是否是触发条件（K1） | round2f 同位流 2×2 + round3c ILA5 tvalid | L1 → L2 |
| 9 | 读回"最后一值冻结"跨从机（K2） | 固件 LMB 环形日志/同址多读 + ILA4 握手 | L2 数据 → L1 机制 |
| 10 | GO 是否到桥/引擎是否进 STREAM（K5） | round3c ILA5 probe5 + tvalid（E.3） | 未测 |
| 11 | UART TX 停摆 vs 总线死锁（K4） | 连续串口 + 无打印固件版本 | 未测 |
| 12 | 桥是否 commit（wm/rd_frm）在 wedge 时刻 | ILA3 在**有服务的窗口内** arm 触发（不能用无 'd' 的复演代替） | 12:43 复演无效，需重做 |

*§E 由 rtl-auditor 于 2026-10-19 晚追加；P/J 结论仅 L1（无归档串口），其余为 L2 日志/数据直证。*

---

## §F 2026-10-19 15:3x–16:0x 收口：数据面首次全通后的两段式根因

> 本节为对 §E 候选集的**收口/降级**记录，基于 round3c-diag 板验（`out/evidence_2026-10-19/R3C_board_session_20261019.md`）与新归档产物。Q1/Q2/Q3 的完整复核另见 `audit/R3C_fw_s2mm_reset_review.md`。

### F.0 结论总览

| # | 结论 | 等级 | 证据 |
|---|---|---|---|
| 1 | **旧位流（round2f/round3/round3b）的"读回冻结/UART 静默"根因 = `axi_lite_regs` 一直在用 10-17 的陈旧 IP-cache 网表，fix1/fix2 从未进入位流** | **L2 强推断**（机制板级直证待 ILA4→L1） | §F.1：cache 时间戳/命中数、`_9` DCP 路径、新旧 xci/stub、功能等价声明 |
| 2 | **修复陈旧网表后暴露的第二个确定性 bug = 固件读服务 `DMA_DMACR=Reset` 复位整个 AXI DMA → S2MM 周期 Halted → 下一帧 LENGTH 写无效 → 严格隔帧丢（50%）** | **L3 板证**（事件环直证 + 修复 A/B）+ **L2** PG021 | §F.2：evt2 事件环 0x16 `s2sr=0x1002` vs `0x0001`；PG021 "either Reset resets the entire AXI DMA engine" / "Halted 时写 LENGTH 无效" |
| 3 | 固件级修复（`s2mm_rearm()` + GO 后 `busy_ms(1)` + 空闲全速）有效；**round3c-diag bit `9852016C` + perf1 ELF `BA3C0220`：ping 20/20、四档 100% PASS、10MB 7022/7022 SHA 一致** | L2 板端实测 | `R3C_fourtier_perf1.log`、`R2_mb10_20261019_155136.log`、`R3C_board_session_20261019.md` |
| 4 | Q1 官方口径准确、无 async/SG/direct-register/版本例外 | L2 官方 | `R3C_fw_s2mm_reset_review.md` §Q1（PG021/DS781 URL 两件套） |
| 5 | Q2 修复时序正确、不改变桥 commit 语义；残余仅"极端时序丢帧/理论 IOC 偷取窗口"，均为"丢一帧+恢复"而非提交错数据 | L1 低 | 同文件 §Q2（含建议：删 `s2mm_rearm` 中冗余 W1C、保留 `busy_ms(1)`） |
| 6 | Q3：BD 全量 regen 不是改了 BD 逻辑，而是**换了 module-ref IP 实例/接口 → 新 IP-cacheID → 迫使 10-19 12:05:50 首次真综合当前 RTL** | L2 强推断 | `audit/R3C_fw_s2mm_reset_review.md` §Q3 |

### F.1 §E 候选集的收口/降级

| §E 候选 | 收口结论 | 依据 |
|---|---|---|
| K1「真实 STREAM/DDR 写是触发条件」 | **只对旧网表成立**；机制=陈旧 lite 网表的协议违例在 GO/流活动下把互连读跟踪弄失步，非板级 DDR/电源问题 | 旧 cache 网表=fix 前版本（单读 5R/单写 5B，10-18 单元仿真）；真 fix2 进流后同序列不再复现 |
| K2「读回最后值冻结（跨从机 0x80010056）」 | **旧网表症状**：fix 前 lite 的重复 R/B 握手使互连读数据路径失步（坑 #39 家族）；真 fix2 后未再观测 | §E.0 数据 + 本次 §F.1 |
| K3「陈旧 WRDBG.bit31 误判 fault 打印」 | 旧网表症状链的一环（g_step=11/PC 0x738 可解释），但**已非现位流问题** | §E.1 + 新位流无楔死 |
| K4「UART TX 停摆」 | 旧网表楔死后的表现（服务面整体死亡）；新位流会话串口正常 | `R3C_board_session_20261019.md:21-25` |
| K5「桥 GO→STREAM 未发生」 | 旧位流的间接观测（无 probe5 不可判）；**新位流 ILA3 已有 `wm=wr_frm=rd_frm=0x0d`** ⇒ commit/读出发生 | `R3C_r3cS1_ILA3_*.csv` |
| H1 邮箱无超时/复位失配 | 本轮**未观测**为楔死主因（`rst_user_n` 事件无常驻证据）；作为**后备结构性风险**保留（round3d lite 超时补丁仍有价值） | §E.2 + 新位流；判据未触发≠排除 |
| H2/H3/H4/H5/H6（互联流水/上游挂死/B 冰封/协议窗口/时钟停） | 新位流上均未复现；保留为 round3d ILA4 的判读对象（ILA4 在 round3c/round3d 均被跳过 ⇒ 无板端直证） | 同上 |
| Z1/Z2/Z3（GO 未到/受阻/粘滞） | 旧位流的"零 commit"已被 stale-netlist 解释；新位流 commit 正常 ⇒ 不需以 Z 类解释当前现象 | ILA3 `wm=0x0d`；§F.2 |
| Z4/Z5/Z6 | 未观测；`stat_wr_timeout` sticky 探针仍是 round3d 可观测性缺口（可选） | 保留 |

### F.2 新根因链（两段式，按时间顺序）

1. **第一段（旧位流"冻结/静默"）**：BD 首建 10-17 22:22 生成的 module-ref OOC DCP 被后续所有构建复用（IP cache `1f8570ac…`，19 次命中，最后命中 10-19 00:10:59=round3b 构建）；`axi_lite_regs.v` 在 10-18 的 fix1/fix2 均未触发 cache 失效（cache key 跟接口/xci 走，不跟内部 RTL 内容走）。旧网表的 AXI4-Lite 协议违例（多拍 RVALID/BVALID → 重复 R/B）在 GO 写 + S2MM 开始搬数后让互连读写跟踪失步 ⇒ 读回冻结（同值 0x80010056）/UART 静默/PC 自旋（§E 的观测全部落在这条线上）。
2. **第二段（新位流"50% 隔帧丢"）**：BD 全量 regen 换 `_9→_10` 实例、新接口（dbg_o）→ 新 `IPCACHESYNTHCRC`（3fdf9d25→08aea834）→ 新 cache `f74c8b84…`（10-19 12:05:50）→ **fix2 首次进流**；总线协议正确 → 楔死消失，暴露固件 bug：读服务 `DMA_DMACR=0x4` 复位整个 DMA → S2MM Halted；下一帧 `S2MM_LENGTH` 写被忽略（PG021）→ 无 introut → 桥 WAITDONE 超时 → WD_HALT → 固件 fault 恢复 → 下一帧成功 ⇒ 严格隔帧 50%。
3. **修复**：固件 `s2mm_rearm()`（RS+IOCEN → 等 Halted 落 → W1C IOC；不动 `g_wr_last_toggle`）在读服务末尾/每次写编程前调用；写服务 GO 后 `busy_ms(20)+5读` → `busy_ms(1)`；空闲环 `busy_ms(10)` → 全速。**无 RTL/位流功能改动**。
4. 验收（[L2] 板端）：ping 20/20（NIC Δ1480=74×20）；`udp_verify_ddr.py` 四档 20/20·12/12·12/12·300/300 100%；`r2_mb10_sha.ps1` 7022/7022、lost=0/corrupt=0、源=重组 SHA256 一致（独立复算 ✓）。

### F.3 事件环证据（`R3C_evt2_dump.txt`，4-word/事件，128 事件）

| 事件序 | 内容（a,b,c,tag） | 判读 |
|---|---|---|
| 0 | `80010056, 0, 1, 0x11` | 新写请求 pending=1,toggle=0,slot=1,len=86 |
| 1-2 | `…,0x14`；`56,1,0,0x15` | stale 复核通过 → 编程 (len=86,slot=1,tog=0) |
| 3 | **`00001002, 56, 0, 0x16`** | 编程后快照：**s2sr=0x1002 (Idle+IOC)，s2len=86** → 成功帧 |
| 4 | `03010056,0,0,0xd1` | 读服务（engine=1,sticky=1,slot=1,len=86）→ **MM2S 复位** |
| 5-7 | `81020056,1,0,0x11`…`56,2,1,0x15` | 下一帧请求 (tog=1,slot=2) → 编程 |
| 8 | **`00000001, 56, 1, 0x16`** | 编程后快照：**s2sr=0x0001 (Halted，无 error)**，s2len 读回仍是 86（LENGTH 被寄存器接受但**不启动**）→ 失败帧 |
| 9+ | `…0x11/0x13` 重复 | 同 toggle 请求不再重编程；桥 56ms 后 WAITDONE 超时→fault 恢复；下一帧再成功 ⇒ 隔帧 |

（对照 PG021：Halted=1 时 LENGTH 写 "has no effect on DMA operations"；`S2MM_LENGTH` 读回 86 不能当"已启动"判据——**这修正了此前 round3b 用 LENGTH 回读作判据的口径**。）

### F.4 对 §E 板验方案的影响

- §E.4 的 round3c 触发方案（ILA5 probe5 `0011001`/tvalid 等）在 **round3c-diag 位流上 ILA4 已被跳过、ILA5 裁为 47b（probe5 仅 4b）**，故 §E.3 的 7b 触发值需按 round3d 最终 ltx 重新映射（Lead 已把 round3d ILA3=152b 全量、ILA5=47b、ILA4 跳过）。
- **lite 总线直证仍缺**：round3d 也跳过 ILA4 ⇒ "陈旧网表→冻结"的 L2→L3 需要离线重放旧网表（旧 cache funcsim/门级 TB）或未来 ILA4 轮次；本轮不阻塞数据面验收。

### F.5 纪律/新坑建议

1. **AGENTS 坑账本候选 #68（module-ref IP cache 陈旧）**：BD module reference 的 OOC/IP-cache **不随 RTL 源文件内容失效**；`reset_run`/`MODULE_REF_RESET` 不清 cache ⇒ "每轮 reset 了 run 仍用旧网表"。判别法：build 日志 `Reading design checkpoint '.../mb_ctrl_*_<N>/...dcp'` 的 `<N>` 目录 mtime 应晚于 RTL mtime；或看 `prj11.cache/ip/.../stats.txt`（NumberHits/Timestamp）。修法：改 module-ref RTL 后 **BD regen**（或删 cache 条目 / `config_ip_cache -disable_cache`）再综合。
2. **固件纪律**：任何"复位整个 AXI DMA"的调用（MM2S 或 S2MM DMACR.Reset）之后必须重新武装**另一通道**（RS+IOCEN、清 IOC、等 Halted），并把 `S2MM_LENGTH` 写放在 RS 确认之后；`LENGTH` 回读值不能当"传输已启动"判据（Halted 时 LENGTH 仍保存写入值）。
3. **保留 `busy_ms(1)`**（GO→读服务间隔），直到 lite/桥有超时兜底；可选加固：删 `s2mm_rearm()` 中冗余 W1C（消除理论 IOC 偷取窗口）。
4. 1000fps/S8 类性能验收：本修复把单帧服务从 ~3ms 降回 ~0.15ms 量级，10MB 7022 帧 PASS；后续若再丢帧，先查 `wr_timeout/fault` 与 ILA3 全量计数（round3d）。

*§F 由 rtl-auditor 于 2026-10-19 16:0x 追加（只读复核；未改任何设计/脚本/固件）。*
