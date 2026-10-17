# §三之二十 完整草稿（待 Lead 审后合入调试记录）

- **目标文件**：`C:\Users\***\Desktop\毕设\调试记录\阶段三_prj11_B3-1三主仲裁器与DMA读路径设计_2026-10-12.md`
- **插入位置**：`### 三之十九之补四`（当前第 976–1002 行）**之后**、`## 三、当前状态（末版快照）`（当前第 1003 行）**之前**；同时按 §⑦/§⑧ 回填 `## 三、当前状态（末版快照）`。
- **写作纪律**：本稿所有数字均可在 `out\evidence_2026-10-17\` 原始文件中复算（逐条给路径）；未发生的结果一律 `{{PENDING:…}}`，**不编造**；结论带依据等级（AGENTS.md §6a）。
- **当前状态**：修复在工作树（未提交）、上板复验未发生 ⇒ 根因 **[L3]**、修复效果 **PENDING**、尚**不能**写 [L4] 定案。**另有一项独立软件侧 [L4]（J3 判据脚本缺陷）已修复复验 PASS**（见 §4.2）——它不改变"RTL 修复仍待板上复验"这一状态。

---

### 三之二十、退役位流读侧收口（2026-10-17 晚·续）：根因 = 共享模块退役误伤桥②读引擎；修复 = 读 FSM 按 `HAS_DMA` 参数化（板上复验 PENDING）

**本节一句话**：昨天把「DMA 是唯一读出路径」的退役改动做进了**两个桥共用的** `axi4_master_bridge.v`，把桥②（`u_mem2`，`HAS_DMA=0`、没有 DMA shim）的硬件读 FSM 一并删掉 ⇒ 桥② 读路径死、泵B 没有输入 ⇒ 所有出向帧不上线。今天用两组板上取证把断点锁死在桥②（而不是"发射口之后"的 Aurora/PHY），并按 `HAS_DMA` 把读 FSM 参数化恢复；离线回归全绿，**上板四判据复验尚未执行**。

---

#### 1) 现象与有效判据（含原始日志引用）

**1.1 有效序列（这是今天唯一可用的板上判据序列）**

上电 → 发**一次** `'d'`（翻转语义）→ 解析回显 `DMAMODE now=DMA` → `'U'` 断言 `req` bit24=1 → **ping×4（中途不跑任何 M/A/B 轮）** → 再 `'U'` + 读 PC 网卡计数。
配置：退役位流 **`3aa600aa`**（`archive\b31b_rdclose_2026-10-16\aurora_mem_bridge_rdclose_3aa600aa.bit`）+ ELF **`2961b585`**（`archive\b31b_n7_2026-10-17\j3_soft_n7_2961b585.elf`）。
原始日志：`out\evidence_2026-10-17\clean_engine1_ping_204321.log`（UTF-16LE，3280 B，SHA256 前 8 `B56EB203`）。

| 观测量（`'U'` 解码） | ping 前 | ping 后 | 判读 |
|---|---|---|---|
| `wmwr`（`+0x08`，`WM_WR`） | 11 | **15** | **+4** = ping×4 的写帧 |
| `wmrd`（`+0x0C`，`WM_RD`） | 11 | **15** | **+4** ⇒ 桥① 读侧逐帧退休，DMA 唯一读出路径**是通的** |
| `req`（`+0x34`） | `0x010A0056` | `0x010E0056` | bit24(engine)=**1**；bit25(dreq_new)=0 ⇒ 无待服务请求、无"请求挂死" |
| `emit`（`+0x3C`） | `0x00560A55` | `0x00560E55` | `{len=0x56=86, slot=10→14, byte0=0x55}` ⇒ 发射口拿到**帧长/槽号/首字节都正确**的帧 |
| `arl`（`+0x38`） | `0x0010A000` | `0x0010E000` | 末笔 DMA AR = `SLOT_BASE(0x00100000)+slot*0x1000`，**地址正确、随 slot 前进** |
| PC 网卡 `ReceivedUnicast/Bytes` | 7023 / 1310802 | 7023 / 1310802 | **delta=0 / 0** |
| `ping -n 4 192.168.1.10` | — | — | **0/4（100% loss）** |

⇒ **判据 C1**：桥① 的读退休、DMA AR 地址、发射字段（len/slot/byte0）全部正常而线上零帧 ⇒ 失败段**严格在「桥① 发射口之后」**（即第二跳：`axis_word_pack→Aurora TX/RX→u_unpack→桥②→泵B→mux→gmii_to_rgmii`）。

> `'U'` 解码口径（`sw\src_j3\main.c:448-472`）：单读行（id/req/wmrd/stat/wmwr/ust）**首值是上一地址残值，只取第 2..6 值**；`dread` 双读行（reqX/arl/emit）3 值均为新鲜值。`emit` 布局 `{len[31:16], slot[15:8], byte0[7:0]}`（`rtl\frame_mem_if.v:507-524`）。`mode=` 打印的是软件标志 `g_dma_mode`，**不是** `R_ENGINE`/`cfg_mode` 的硬件状态（`main.c:470-471`）。

**1.2 桥级 ILA 计数：断点直接指向桥②（[L3]）**

同一轮（engine=1、ping×4 前后各抓一次）ILA 快照：`out\evidence_2026-10-17\ilacap_pre_user.csv` / `ilacap_post_user.csv` / `ilacap_pre_ui.csv` / `ilacap_post_ui.csv`，解析汇总 `ilacap_counters_summary.txt`（工具 `out\jb31b_ilacnt_parse.py`；抓取流程 `r1cap3_vivado.log`，`R1CAP_DONE`）。

| 域/实例 | 观测量 | ping 前 | ping 后 | 判读 |
|---|---|---|---|---|
| ui / **桥① u_mem** | `dbg_mem_wm` | 19 | 23 | +4 |
| ui / 桥① | `dbg_mem_wr_frm` | 19 | 23 | +4 |
| ui / 桥① | `dbg_mem_rd_frm` | 19 | **23** | **+4** ⇒ 桥① 读退休正常 |
| ui / 桥① | `dbg_mem_ost` | 0 | **0** | 无在飞堆积 |
| ui / **桥② u_mem2** | `dbg_mem2_wm` | 19 | 23 | +4（帧从 Aurora 侧到达） |
| ui / 桥② | `dbg_mem2_wr_frm` | 19 | **23** | **+4** ⇒ 帧确实**已写入桥②**（Aurora 链路/解包/写侧都活着） |
| ui / 桥② | `dbg_mem2_rd_frm` | 0 | **0** | **一次都没读出**（不是"读错"，是读 FSM 从未退休一帧） |
| ui / 桥② | `dbg_mem2_ost` | 19 | **23** | **outstanding 只增不减** |
| user / 桥① | `dbg_mem_u_wr` / `dbg_mem_u_rd` | 19 / 19 | 23 / 23 | +4/+4 |
| user / 桥② | `dbg_mem2_u_wr` / `dbg_mem2_u_rd` | 19 / 0 | 23 / **0** | 同上：写增、读恒 0 |

⇒ **判据 C3（[L3]）**：ping×4 让**桥② 写帧数 +4 而读帧数 +0**、outstanding 只增不减 ⇒ **泵B 无输入 ⇒ 线上零帧**。这与"桥① 发射口之后"的收窄**不矛盾**：桥① 发射出去的帧经 Aurora 到了桥②，卡在桥② 的读侧。

**同环境的绿位流对照（[L3]）**：`green_engine1_ping.log`（ping **4/4**、0% loss）+ `green_engine1_uart_pre.log`（`req` bit24=1）+ `green_engine1_4tier.log`（**四档全 PASS**：ping 20/20、基础 12/12、槽深 12/12、稳定 300/300） + `rdcap2_green.csv`（同工具/同环境抓的绿发射流：1526 拍 `dbg_mem_rden=1`；首采样 `dbg_mem2_u_wr=11`、`dbg_mem2_u_rd=11` ⇒ **绿侧桥② 在读**）。

> **⚠️ 同一绿场次的 J3 异常已定案（[L4]，判据脚本缺陷，不是 RTL/位流回归）**：绿位流 `--dma` 下 J3 四链当次 FAIL（`green_engine1_j3_dma.log`：`[M] wr+255` → 读阶段不启动 → 级联 FAIL），与 §三之十九之补 §1 "DMA 引擎三链全 PASS" 看似矛盾。**根因（[L4]）= `scripts/j3_soft_verify.py` 自身缺陷**：`run_round()` 在 SEQOK 之后、GO 之前**无条件发 1 个预热帧**；DMA 模式下此刻是 SEQ 窗且软核正停在 `round_command` 里等 GO（驻留服务不在跑）⇒ 该帧写进内存后读请求永泊 `R_DRET`、占住 1 槽；随后写阶段 256 帧的第 256 帧因**槽表满**被拒 ⇒ 板端 `WAITWR-FAIL got+255`。桥模式（engine=0）下该帧由硬件读引擎自动读出退休、不留残槽 ⇒ 同一脚本桥模式一直 PASS（`green_bridge_j3_run1.log`）。**修复**：`run_round(..., warm_probe=True)`，`--dma` 时跳过（`warm_probe=(not args.dma)`），+15/−4；**修复复验 [L4]**：`green_dma_j3_run5_warmfix.log`（21:17:36）`[B2-SOFT-VERIFY] PASS`（`[M] wr+256 rd+256 inv=32385 miss=0` / `[A] wr+256 rd+255 inv=32131 miss=[5356]`=恰帧#100 / `[B] wr+256 rd+256`）。**该结论独立于 RTL 修复**；配套纪律见 §9-⑧⑨。
> 另：绿场次的位流本应写入烧录日志（`jb31b_burn_pair`）但本目录未见这次烧录的日志，**位流身份按操作顺序推定**（绿 `708f15a4`），收口时补烧录留痕。

**1.3 桥① 发射字节流：字节级正确（[L3]）**

同一台退役位流、engine=1，用 `out\jb31b_rdcap2.*` 抓桥① 发射口（`dbg_mem_rden` + `mem_rd_data[7:0]`，ILA1，触发 `dbg_mem_rden_1 eq 1`）：`rdcap2_retired.csv`（`RDCAP2_CSV_SAMPLES: 2048`）+ 比对日志 `rdcap2_cmp_retired.log`（参考流 = 归档绿 `b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv`）：

- 长度 **1526 = 1526**、首 8B `55 55 55 55 55 55 55 D5`（前导+SFD）在、`1526` 个 `dbg_mem_rden=1` 采样**连续无气泡**；
- 严格逐字节差 **14 B**，位置 = `8–13`（dst MAC）、`26–27`（IPv4 ID）、`32–33`（IP 头校验和）、`1522–1525`（FCS）；**其余全部相同**（帧布局/载荷逐字节同构，偏移 50 起的自描述载荷一致）；
- **dst MAC 差异是环境性的、不是缺陷**：10-17 给 PC 加了**永久静态邻居**后 PC 不再发 ARP，板的 ARP 表学不到 PC MAC ⇒ 板自发帧 dst 用广播 `ff:ff:ff:ff:ff:ff`；参考流是 10-16 的 `08:3c:03:a0:26:96`。⇒ **"发射流同构"判据必须掩掉 dst(8–13)+IP-ID(26–27)+IP 校验和(32–33)+FCS(末 4B)**，或同环境同轮抓绿参考流（`rdcap2_green.csv` 已抓）。
- **同环境绿参考比对（[L3] 补强）**：`rdcap2_green.csv`（绿位流 engine=1、同静态 ARP 环境、同工具抓取）与 `rdcap2_retired.csv`，按上述掩码比对 **`ndiff_after_mask=0`（Lead 实测）** ⇒ **桥①→Aurora 发射字节流与绿位流逐字节同构**（对比日志待归档，见 §8 PENDING）。这条与"桥① 段无缺陷"互证，把缺陷进一步压到桥② 读路径。

⇒ **判据 C2（[L3]）**：桥①→Aurora 段的字节流**正确且与绿同构** ⇒ 缺陷严格在桥② 读路径，与「发射字节流/帧长/槽号/前导」无关。

**1.4 无效实验的识别（本轮作废样本，留痕）**

- `s2_s6_204148.log`（`3aa600aa` + `2961b585`，旧 S2–S6 脚本）：S5 ping 0/4，且 `'U'` 解码 **`WM_WR 2→7`、`WM_RD 2→2`** ⇒ ping 期间**读侧一次都没启动**。原因见 §9-①（M 轮末 `R_ENGINE=0` + `R_MODE` 停在 RND）。**该轮不能用于"位流差异"结论**。
- `s2_s6_201701.log`（`0ecb8438` + `2961b585`）：同一脚本同形态，`WM_RD` 不涨。
- 20:51 的第一轮 ILA 抓取（`r1cap_vivado.log`）：`'U' mode=0`（`r1cap_uart_pre.log`/`r1cap_uart_post.log`）⇒ **engine 被 `'d'` 翻转翻回了 bridge**，无效；其 CSV 已被 20:53 第二轮覆盖（当前 `ilacap_*.csv` 是第二轮=有效轮）。
- `clean_engine1_ping_204258.log`：抓取失败（内容仅 `[%s] %s` 格式串），无效。
- `rdcap2_retired_vivado_10272.backup.log`：第一次字节流抓取失败（4 个 ILA 都 `mem_rd_data_probes=0`，"no ILA carrying a mem_rd_data* probe"）⇒ 判据未取得；tcl 修后 20:54:57 那轮成功（`rdcap2_retired_vivado.log`，`RDCAP2_DONE`）。

---

#### 2) 根因（[L3] 代码级 + 板上计数器直接观测）

**2.1 代码级：退役改动落在两个桥共享的模块里，桥② 被连坐**

- 提交 `8afa168`（2026-10-16 18:37，"B3-1c 退役桥②读引擎…"）在 `prj\project_11\rtl\axi4_master_bridge.v` 里把 R_PRE 的引擎二选一：

```verilog
// 退役前（3f847e3）
end else if (dma_engine) begin   // DMA 读引擎：发 {slot,len} 请求，等 shim frame_done
    dma_req_new <= 1'b1; ... rstate <= R_DRET;
end else begin                   // 桥硬件读引擎：R_AR→R_R→R_UNPACK→R_FIN
    r_slot<=p_eff; ... rstate <= R_AR;
end
// 8afa168 之后：去掉 dma_engine 条件，无条件进 DMA 分支，并删除 R_AR/R_R/R_UNPACK/R_FIN 四个状态
```

- 该模块被 `frame_mem_if` 内**同一个 `u_bridge`** 例化，而 `frame_mem_if` 的 `HAS_DMA` 参数由顶层决定：桥① `u_mem`（`aurora_mem_bridge.v:772`，**默认 `HAS_DMA=1`**，有 DMA shim）与桥② `u_mem2`（`aurora_mem_bridge.v:917`，**`HAS_DMA=0`**，DMA 口恒 0：`aurora_mem_bridge.v:956` `.dma_engine(1'b0)`）。
- 于是桥②（`HAS_DMA=0`、**没有 DMA shim**）在退役后：
  1. R_PRE 无条件进 **R_DRET**；而 `shim_frame_done` 在 `HAS_DMA=0` 分支**无驱动**（`b31b_retire_2026-10-16\axi4_master_bridge_retired.v:547` 只声明 wire，只有 `gen_dma_engine` 里由 shim 驱动）⇒ 恒 0 ⇒ **R_DRET 没有出口**（无超时/看门狗，H6）⇒ 读 FSM **永久停泊**；
  2. `gen_no_dma` 里 `rf_wr_en = brf_wr_en`（`:569`），而 `brf_wr_en` 只在 **R_UNPACK** 置位（已被删）⇒ **读数据口无源**（`rf` 字节 FIFO 永远空）；
  3. 桥② 是**泵B 的唯一数据源**（`aurora_mem_bridge.v:1194-1206`）⇒ 泵B 读不到字节 ⇒ 所有出向帧（含栈自发 ARP/ICMP、回环帧）全部停在桥② 内、不上线。
- **结论**：退役的**正确作用域**是 `HAS_DMA=1` 实例（桥①，DMA shim 唯一所在）；8afa168 用"无条件删分支"实现，等效于把作用域扩大到了 `HAS_DMA=0` 实例 ⇒ 结构性误伤。

**2.2 板上计数器直接观测（[L3]，非推论）**

见 §1.2 表：桥② `dbg_mem2_wr_frm` **19→23**（帧已到桥②）而 `dbg_mem2_rd_frm` **0→0**、`dbg_mem2_ost` **19→23**（outstanding 只增不减）；桥① 同轮 `dbg_mem_rd_frm` +4、`ost=0`。**"帧到了桥②、一帧没读出、只增不减"就是读 FSM 停泊的直接观测**。

替代解释已排除：
- Aurora 链路/解包/桥② 写侧：`mem2_wr_frm`/`mem2_wm` +4 ⇒ 活着；
- 复位：`mem2_wr_frm` 在涨 ⇒ `aurora_rst=0`、桥② 未复位；
- 桥① 读出路径：`mem_rd_frm` +4、`emit`/`arl` 正确 ⇒ 与故障无关；
- 泵B 输入端无数据：`mem2_rd_frm=0` 是泵B 上游的直接原因（不是"泵B 本身坏"）。

**2.3 对 20:45 离线审计的更正（重要）**

`out\evidence_2026-10-17\rtl_audit_204519.md` §2 Δ5 / §4.1 判断"`u_mem2` 的读 FSM 仍是硬件读引擎、未被退役影响"，理由是"本次改动没碰 `u_mem2` 实例的端口接线"。**该判断错误**：被删的读 FSM 在 `axi4_master_bridge.v` **模块内部**，实例差异由 `HAS_DMA` 参数在模块内展开；只看顶层实例端口接线会漏掉"共享模块内部逻辑"这一层。本记录以板上 ILA（§1.2）直接反证，并保留该审计原文不改（记录只增不改，更正集中写在本节）。

---

#### 3) 修复（RTL 差异、参数化理由）

**3.1 改动清单（工作树，未提交；`git diff --stat` = 3 文件 +68/−4）**

| 文件 | 改动 |
|---|---|
| `rtl\axi4_master_bridge.v` | ① R_PRE 引擎判定改为 `if (HAS_DMA)`：`HAS_DMA=1` 保持"只走 DMA、泊 R_DRET"（收口语义不变）；`HAS_DMA=0` **恢复 `R_AR` 入口**（`r_slot/r_len/r_beats/r_beat` 赋值 + `dbg_rd_slot` + `rstate<=R_AR`）。② **恢复 `R_AR/R_R/R_UNPACK/R_FIN` 四个状态**（与退役前 `3f847e3` 逐字节相同，独立复核 `rtl_fix_review_205656.md` §5.1 已证）。③ `gen_no_dma` 分支新增 `assign shim_frame_done = 1'b0;`（把原悬空网变确定 0；R_DRET 在该实例不可达）。④ 注释写明作用域。 |
| `sim\mem_bridge_tb.sv` | `frame_mem_if` 实例显式 `.HAS_DMA(0)`（W2 是硬件读语义的回归） |
| `sim\w4_joint_tb.sv` | 两个 `frame_mem_if` 实例显式 `.HAS_DMA(0)` |

**3.2 为什么用 `HAS_DMA` 而不用 `dma_engine`**

1. **作用域是结构性的**：退役 = "桥① 只留 DMA 读出"；这是实例级决策（由 `HAS_DMA` 决定），不是运行时引擎位（`R_ENGINE`/`dma_engine`）能表达的。`dma_engine` 是软核 `'d'` 可翻转的**运行态**开关；若用它守卫，`engine=0` 时桥② 恢复硬件读、`engine=1` 时又断——缺陷会随 `'d'` 时隐时现，且桥① 的"唯一读出路径"会被破坏。
2. **两个实例的 `dma_engine` 本来就不同**：桥② 恒 0（`aurora_mem_bridge.v:956`），退役前的 `else if (dma_engine)` 对桥② 恒选硬件读；退役后无条件选 DMA ⇒ 只有 `HAS_DMA` 能区分"这个实例有没有 shim"。
3. **可达性/剪枝已验证**：`HAS_DMA=1` 时 R_AR/R_R/R_UNPACK/R_FIN **不可达**（唯一入口在 `HAS_DMA=0` 分支），综合可剪枝 ⇒ 桥① 仍是 DMA-only；`HAS_DMA=0` 时 R_DRET 不可达（`shim_frame_done` tie-0）⇒ 无悬空/无多驱动。两种参数值都已实际 elaborate + 仿真（`sim\xsim_run.log:30`、`sim\w4_joint_run.log:35` 的 `Compiling module work.axi4_master_bridge(HAS_DMA=0)`）。
4. **最小且可审计**：恢复块与退役前逐字节相同（不引入新逻辑），`gen_no_dma` 仅多一条 tie-0。

**3.3 独立复核（离线，[L2]）**

`out\evidence_2026-10-17\rtl_fix_review_205656.md`（20:57，复核对象工作树 blob `7fe880e`）：
- **A 完备性 OK**：退役删除状态所驱动的 23 个信号全部有驱动、无悬空、无新增多驱动；
- **B 正确性 OK**：`HAS_DMA` 常量分支合法（xvlog/xelab 0 warning）、`HAS_DMA=1` 下 R_AR..R_FIN 不可达、`HAS_DMA=0` 下 R_DRET 不可达；
- **C 单一驱动 OK**；**D 语义等价 OK**（4 个恢复块与 `3f847e3` 逐字节相同）；
- **E 桥① 仅 DMA OK**（R_DRET 与 R_FIN 退休字段逐项等价；SEQ 下 `dma_req_slot+1 ≡ rd_seq_slot+1`）；
- 非阻塞项 3 条：① `axi4_master_bridge.v` 端口/注释仍写"engine=0=硬件读"（已过期，建议只改注释）；② `sim\bridge_dma_tb.sv` 的 P1 标签仍写"桥硬件读"，实际走 DMA 路径（建议改标签/注明覆盖边界）；③ 新位流必须由工作树 `7fe880e` 重建（构建闸门：MDRV=0、WNS/WHS≥0、无 2023.1 Mimic Skeleton 崩溃）。
- **警告**（复核 §6.3，上板判据必须带）：`req[24]` 的回读语义已过期（RTL 不看 engine 位）；`'d'` 不要按两次（第二下会关掉 DMA 驻留服务）；`cfg_mode` 必须 SEQ 才会自动发读（`'d'` 会顺手置 SEQ）；`dbg_rd_beats` 在 DMA 路径按帧 +1、硬件路径按拍 +1，跨配置比较会误判。

---

#### 4) 离线回归

**4.1 RTL/TB 仿真（全绿；日志已归档到 `out\evidence_2026-10-17\`）**

| TB | 编译参数（证据） | 结果 | 原始日志（归档副本 / 原路径） |
|---|---|---|---|
| `bridge_dma_tb`（桥① DMA 路径） | `axi4_master_bridge` 默认 `HAS_DMA=1`（`sim\bridge_dma_tb.sv:113`） | **PASS 0 errors**（P1/P2/P3；NEG 按设计） | `sim_bridge_dma_run.log` / `sim\bdma_run.log`（20:47:36，SHA256 前 8 `A4C3F4DD`） |
| `mem_bridge_tb`（W2，桥② 硬件读语义） | **`HAS_DMA=0`**（`sim_W2_mem_bridge_run.log` 编译行） | **PASS 0 errors**（T6/T1/T4/T5/T2/T3；`rd_frame=585`、`rd_beats=8202`） | `sim_W2_mem_bridge_run.log` / `sim\xsim_run.log`（20:48:26，`02F7D25E`） |
| `w4_joint_tb`（W4，双桥） | **两实例 `HAS_DMA=0`**（`sim_W4_joint_run.log` 编译行） | **正向 `DEFECT=0` PASS 0 errors**（P1–P5，A/B 各 `rd=148`）；**负向 `DEFECT=1` 按设计 FAIL/deadlock**（判据非恒真） | `sim_W4_joint_run.log` / `sim\w4_joint_run.log`（20:49:10，`FC40B951`）；负向备份 `sim\xsim_21116.backup.log` |

> 注意：`sim\bridge_dma_tb.sv` 的 P1 **打印标签**仍写"engine=0（桥硬件读）"，退役后实际走的是 DMA 路径（R_PRE 不再看 `dma_engine`）；判读时勿被标签误导（复核报告 §8-② 已记，建议改标签，不影响结果）。

**4.2 J3/J3′ + 负向 A/B（判据脚本侧）：[L4] 机制定案 + 修复复验**

> 这一段是**软件/脚本判据**的回归，不是 RTL 仿真；根因与修正在 `scripts\j3_soft_verify.py`（工作树 M，+15/−4，blob `59a2d7e`）。

| 项 | 内容 |
|---|---|
| **现象（[L3]）** | 绿位流 `708f15a4` + ELF `2961b585`，`--dma` 模式连续 3 次 `[M] wr+255`（写阶段少 1 帧）→ 读阶段不启动 → 槽满级联 FAIL（`green_engine1_j3_dma.log` / `run2` / `run3_nowarmup`） |
| **根因（[L4-机制]）** | `run_round()` 在 SEQOK 之后、GO 之前**无条件调用 `warmup_probe()` 发 1 个预热帧**。DMA 模式（`g_dma_mode=1`、`R_ENGINE=1`）下此刻是 SEQ 窗且软核正停在 `round_command` 里等 GO（**驻留服务不在跑**）⇒ 该帧写入内存后读请求**永泊 `R_DRET`**、占住 1 槽；随后写阶段 256 帧的第 256 帧因**槽表满**被拒 ⇒ 板端 `WAITWR-FAIL got+255`。桥模式（engine=0）下该帧由硬件读引擎自动读出退休、不留残槽 ⇒ 同一脚本桥模式一直 PASS（`green_bridge_j3_run1.log`：`[M] wr+256 rd+256 inv=32132 miss=0`；`[A] wr+256 rd+255 miss=[5356]`=恰帧#100；`[B] PASS`） |
| **修复** | `run_round(..., warm_probe=True)`，主流程 `--dma` 时传 `warm_probe=(not args.dma)`（附 6 行机制注释）⇒ DMA 模式跳过预热帧；桥模式保留预热（行为不变） |
| **验证（[L4-修复复验]）** | 绿位流 + 新烧录 + `--dma`：`green_dma_j3_run5_warmfix.log`（21:17:36）→ **`[B2-SOFT-VERIFY] PASS`**；`[M] PASS wr+256 rd+256 inv=32385 miss=0` / `[A] PASS wr+256 rd+255 inv=32131 miss=[5356]` / `[B] PASS wr+256 rd+256` |
| **加严纪律（[L4]）** | ① **`wr+255` / 收帧停摆不得重试**（会级联假 FAIL 并可能把板卡留在"256 槽未读 + 读 FSM 泊 `R_DRET`"半楔死状态，需重烧恢复）；② J3 必须在**新烧录后**跑（残留"已写未读"帧会让 M 轮 `wr+255`；旁证 `green_fresh_manual_round_256.log` = 新烧绿后 `manual_round 256` PASS）；③ 跑完轮末固件把 `R_ENGINE` 写回 0、`R_MODE` 留在 RND ⇒ **后续 ping 判据必须重发 `'d'`/`'S'`**（与旧 `retire_s2_s6.ps1` S5 失效同一机制） |
| **判据工具口径（当前）** | `out\retire_s0_s8.ps1` / `out\j3_fourchains.ps1` 采用"**不带 `--dma`** 跑 M/A/B + 前置清槽 + 失败即停"口径（`out\S0S8_DESIGN.md` §1.7）；但修复后 `--dma` 已可 PASS ⇒ **最终采用哪种口径由 Lead 统一（PENDING）** |

---

#### 5) 上板判据 S0–S8 结果（**全部 PENDING**）

> 前提：新位流必须由当前工作树（bridge blob `7fe880e`）重建；烧录用**绝对路径 + 先核 hash**。
> 严格序列：上电 → **只发一次** `'d'`（回显 `DMAMODE now=DMA` 才算数）→ `'U'` 断言 `req` bit24=1 → ping/round（**ping 前若跑过 round 必须补 `'S'` 回 SEQ 或重新确认**）。
> 工具：Lead 已备好 `out\retire_s0_s8.ps1`（默认 DRY-RUN 只打印计划；`-Run` 才上板；内置 `'d'` 翻转确认、S2 身份判据、网卡 delta、`emit` 掩码判据）；**本节表格为判据口径，执行结果以该脚本落盘日志为准**。

| 步 | 动作 | 判据 | 实测 | 状态 |
|---|---|---|---|---|
| S0 | 构建新位流（含探针） | 构建日志 `V5_SWEEP_OK`、WNS/WHS≥0、MDRV=0、blob=`7fe880e` | {{PENDING:S0 结果}} | **PENDING** |
| S1 | 烧绿 `708f15a4` + ELF 基线 | ping 3/3～4/4、`'L'` 应答、邻居 `Permanent` | 今日绿基线已取值：`green_engine1_4tier.log` 四档 **PASS**（20/20·12/12·12/12·300/300）、`green_engine1_ping.log` **4/4**（NIC `Unicast=0/Bytes=+296`）；`green_bridge_j3_run1.log` 桥模式 J3 **PASS**。**J3 DMA 当次 FAIL 已定案为脚本缺陷并修复复验**（§4.2）⇒ S1 仍需在收口场次**当场确认烧录身份**（绿位流烧录日志未归档） | **PENDING（绿基线已取值，烧录留痕待补）** |
| S2 | 烧新退役位流 + ELF，**先不发 `'d'`**：S2a `manual_round.py COM5 1` 必须失败；S2b（加严）确认 engine=0 → `'S'` → `ping -n 1` 必须 0 回包且 NIC delta=0 | S2a：`WAITWR-FAIL/STALL`、无 `DONE`、echo=0；S2b：0/1 回包、delta=0 ⇒ 烧进去的是退役版（**真正的原位身份判据**） | {{PENDING:S2 结果}} | **PENDING**（工具已备：`retire_s0_s8.ps1` S2/S2b；旧退役版 `0ecb8438` 的 DRY-RUN 自检仅验证脚本逻辑） |
| S3 | 发一次 `'d'` → 回显 `DMA` → `'U'` | `req` bit24=1；`mode=1`；整段原始行落盘 | {{PENDING:S3 结果}} | **PENDING**（`Set-EngineMode` 口径：`'U'` 回读 `mode`+`req.bit24` 双确认，最多翻转 3 次；**不要盲发两次**） |
| S4 | **单帧判据（工具口径已更新）**：`ping -n 1`（**不跑 M 轮**）+ NIC delta + `'U'` 前后差分 | ping 1/1、**NIC `ReceivedBytes` delta ≥74**（ICMP 回包帧 14+20+8+32=74B）、`WM_WR` +1、`WM_RD` +1；`ReceivedUnicast` 仅辅助（恒 0） | {{PENDING:S4 结果}} | **PENDING**（Lead 的 `retire_s0_s8.ps1` 已把旧"`manual_round.py COM5 1`"改为 ping 单帧，避免 M 轮副作用） |
| S5 | ping×4 + `Get-NetAdapterStatistics` 前后 | **NIC `ReceivedBytes` delta ≥296**（4×74B）、ping 4/4；`ReceivedUnicast` 恒 0（辅助打印）、`ReceivedBroadcastPackets` 辅助 | {{PENDING:S5 结果}} | **PENDING** |
| S6 | `'U'` 读 `+0x38 arl` / `+0x3C emit` / `wmwr/wmrd` | `wmwr/wmrd` 同步前进、`emit` len/slot 正确、首字节 0x55 | {{PENDING:S6 结果}} | **PENDING** |
| S7 | ILA 桥② 计数（现有 u_ila_3：`dbg_mem2_wm/rd_frm/ost`） | **`dbg_mem2_rd_frm` 随 ping 前进、`ost` 回落**（这是本次修复的判别性观测） | {{PENDING:S7 结果}} | **PENDING** |
| S8 | 四档零回归 + J3 四链（默认 256）+ 发射流同构 | 四档同 §二之五；J3 口径见 `S0S8_DESIGN.md` §1.7（前置清槽、失败不重试）；发射流按"掩 dst(8–13)+IP-ID(26–27)+IP 校验和(32–33)+FCS"口径（绿 vs 退役同掩码已并列 ndiff=0） | {{PENDING:S8 结果}} | **PENDING** |

失败矩阵（新位流仍失败时）：见 `rtl_fix_review_205656.md` §7.4（`wmrd` 不涨 / 桥② `wm` 不涨 / `rd_frm` 不涨 / 泵B `dbg_prev_wr` 不涨 / 线上无帧，五档 30 秒定位）。

---

#### 6) 结论与依据等级

1. **根因（[L3]）**：退役提交 `8afa168` 在**共享**模块 `axi4_master_bridge.v` 内无条件删除硬件读 FSM，使 `HAS_DMA=0` 的桥②（`u_mem2`，无 DMA shim）读 FSM 永久停泊、读数据口无源 ⇒ 泵B 无输入 ⇒ 出向帧不上线。板上直接观测：桥② `mem2_wr_frm` +4 而 `mem2_rd_frm` 恒 0、`mem2_ost` 只增不减；桥① `mem_rd_frm` +4、发射字节流正确。替代解释（Aurora/解包/写侧/复位/桥① 读路径/泵B 本身）已逐项排除。
2. **修复（离线 [L2] 已过；板上 [L4] 待复验）**：读 FSM 按 `HAS_DMA` 参数化（`HAS_DMA=1` DMA-only 不变 / `HAS_DMA=0` 恢复硬件读）+ `shim_frame_done` tie-0 + 两个 TB 显式 `HAS_DMA(0)`。独立复核 A–E 全过、无功能性缺陷。**另有一项独立的软件侧 [L4]**：J3 判据脚本 `scripts\j3_soft_verify.py` 的"DMA 模式预热帧"缺陷已修复并复验 PASS（§4.2）——它解释的是"绿位流 DMA 下 J3 FAIL"，**与 RTL/位流无关**，不要混入 RTL 修复结论。
3. **升 [L4] 定案的条件（缺一不可）**：① 新位流由 `7fe880e` 构建并过闸门；② S0–S8 全过（尤其 S7 桥② `rd_frm` 前进）；③ **四判据**（ping/ARP、四档逐字节、J3/J3′、负向 A/B）全过；④ 产物 hash 记录（§8）；⑤ 记录 §5 表格回填。**在此之前只写 [L3]/PENDING。**
4. **对既有结论的更正（记录只增不改，此处集中列）**：
   - §三之十九之补四 的对照表（"两侧 `wmwr/wmrd` 均 1/1→4/4、逐项相同"）**与归档原始日志矛盾**：`s2_s6_204148.log` 实为 `WM_WR 2→7`、`WM_RD 2→2`（旧脚本无效，§9-①）。该轮不能作为"位流差异"的证据；有效序列（`clean_engine1_ping_204321.log`）下退役侧 `WM_WR/WM_RD` 为 11→15/11→15（+4/+4），说明"读退休"本身正常，问题只在"上不上线"。
   - `rtl_audit_204519.md` §2 Δ5/§4.1 "`u_mem2` 未被退役影响"**判断错误**（见 §2.3）。
   - §三之十九之补二 提出的"归档位流与 RTL 不对应 / 网表级差异"候选（H2/H4）**已不必要**：机制已由板上直接观测锁定，修复复验后即可收口；这些候选降为历史记录，不再作为 R1 阻塞项。
5. **剩余未决（不属本节结论）**：① 修复后四判据 PENDING；② `0ecb8438` 的 WNS=0.000 零余量旁证——功能结论仍建议用 +0.004 的 `3aa600aa` 或新位流（若新位流余量 <+0.05 需标注"低余量打折"）；③ ~~绿位流 J3 DMA 当次 FAIL 判读 PENDING~~ **已定案 [L4]**：判据脚本缺陷，已修复复验（§4.2），不再是未决；④ `out\S0S8_DESIGN.md` §1.7/§5-10 写"J3 不带 `--dma`"（修复前临时口径），而修复后 `--dma` 已 PASS ⇒ **最终执行口径需 Lead 统一（PENDING）**；⑤ 绿场次的位流烧录日志未归档（位流身份按操作顺序推定，PENDING）。

---

#### 7) 运维口径变化（上板前先读）

1. **`'d'` 是翻转不是置位（今天因此白跑两轮）**（`sw\src_j3\main.c:436-446`：`g_dma_mode = !g_dma_mode; R_ENGINE = g_dma_mode?1:0; if(g_dma_mode) R_MODE=MODE_SEQ;`，回显 `[B2] DMAMODE now=DMA|bridge`）。脚本必须**双重确认**：「`'U'` 回读 `mode`+`req.bit24` → 不匹配才发 `'d'` → 再回读；**最后同时满足 `mode=1` 且 `req.bit24=1` 才继续**」，最多翻转 3 次（`retire_s0_s8.ps1` 的 `Set-EngineMode` 已实现）。**不要盲发两次**（第二下会关掉 DMA 驻留服务）。今日两次翻回 bridge 的留痕：`r1cap_uart_pre/post.log`（20:51，`mode=0` 无效轮）、`r1cap_uart_pre2.log` 等。
2. **退役位流每次上电必须先 `'d'` 才有桥① 读出路径**（`g_dma_mode` 上电默认 0、`serve_dma_once` 不被调用）；但**桥② 的硬件读路径与 `'d'` 无关**（`HAS_DMA=0` 恒开）——修复后不要误以为"桥② 也归 engine 位管"。
3. **烧录**：一律绝对路径 + `Get-FileHash` 核对，**不要引用默认名产物**（`out\aurora_mem_bridge.bit` 的 hash 随每次构建变化：写本节时（21:18）实测 = **`0ecb8438`**（旧退役版），修复版构建会覆盖它；旧文档写死 `3aa600aa` 的表述需更正，见 `doc_update_checklist.md`）。
4. **`'U'` 探针口径**：单读行首值是上一地址残值（只用第 2..6 值）；`dread` 行（reqX/arl/emit）3 值新鲜；`U mode=` 是软件标志 `g_dma_mode`，**不能**当硬件 engine/`cfg_mode` 证据；`req` bit24 的回读语义也已过期（RTL 不再消费 engine 位做读出选择）。
5. **ILA 可观测性足矣**：现有 u_ila_3 已含 `dbg_mem2_wm/rd_frm/ost`（`scripts\build_debug.tcl:241-265`），**修桥② 不需要改 RTL 加探针**；S7 判据就是 `rd_frm` 前进、`ost` 回落。
6. **发射流"同构"判据要带环境掩码**：静态邻居 ⇒ 广播 dst；掩 dst(8–13)+IP-ID(26–27)+IP 校验和(32–33)+FCS，或同环境抓绿参考（`rdcap2_green.csv`；绿 vs 退役同掩码已并列 ndiff=0）。
7. **旧 `out\retire_s2_s6.ps1` 不再用于 R1 判据**（S4/S5 无效，§9-①）；若要保留作流程回归，必须在 S5 前插「重新 `'d'`（确认 DMA）+ `'S'`（回 SEQ）+ `'U'` 断言」。
8. **NIC 主判据 = `ReceivedBytes`（不是 `ReceivedUnicast`）**：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ Unicast 恒 0。S4 要求 `Bytes ≥74`（单帧 ICMP 回包），S5 要求 `Bytes ≥296`（4×74）；`ReceivedUnicast`/`ReceivedBroadcastPackets` 仅辅助打印。绿侧实测 ping 4/4：`Unicast=0/Bytes=+296`（`out\S0S8_DESIGN.md` §1.3/§5）。**用 Unicast 会假 FAIL。**
9. **J3 执行纪律（[L4]）**：① 必须**新烧录后**跑（残留"已写未读"帧会让 M 轮 `wr+255`）；② 跑前 `'S'` + 只读轮询 `'U'` 直到 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍（清槽，不发 `'d'`）；③ **`wr+255`/收帧停摆不得重试**（级联假 FAIL + 可能半楔死，需重烧）；④ 跑完轮末 `R_ENGINE=0`、`R_MODE=RND` ⇒ 后续 ping/emit 判据必须重新 `Set-EngineMode DMA` + `'S'`。详见 §4.2 与 `S0S8_DESIGN.md` §1.7。
10. **判据工具也是被测件**：`j3_soft_verify.py` 的预热帧缺陷（§4.2）说明"脚本异常先查脚本"——尤其 `wr+255` 这类 off-by-one 形态，先核对脚本在判据前的副作用，再怀疑 RTL/位流。

---

#### 8) 产物 hash（占位；完整值见 `R1_evidence_index.md` §3/§5）

| 产物 | SHA256 | 状态 |
|---|---|---|
| 旧退役位流 `3aa600aa`（取证基线） | `3AA600AA2899C3612F77127BA260FAF38DC6ED55C21F49C6E74A32DBF7FDD30F` | 已核（`SHA256.txt` 7/7 一致） |
| ELF `2961b585` | `2961B585133DDE6D5C47AFAE9AA722A52D7B4E0813474ACED384B39D3771ADDF` | 已核（文件名前缀一致；n7 目录无 SHA256.txt） |
| 旧退役位流 `0ecb8438` / 探针 `probes_0ecb8438.ltx` | `0ECB843807D122…FB7C12` / `352A5F283D22…C3A11A2` | 已核（探针与 v5rtl `probes.ltx` 逐字节相同） |
| 修复版 `.bit` | `{{PENDING:完整 SHA256}}` | **PENDING**（构建中） |
| 修复版 `.ltx` | `{{PENDING:完整 SHA256}}` | **PENDING** |
| 修复版构建日志 | `{{PENDING:路径 + SHA256}}` | **PENDING** |
| 修复版 `.xsa` / 新 ELF（如需） | `{{PENDING:完整 SHA256}}` | **PENDING** |
| S0–S8 原始日志 | `{{PENDING:路径 + SHA256}}` | **PENDING** |
| 修复版 ILA 计数 / 发射流 CSV | `{{PENDING:路径 + SHA256}}` | **PENDING** |
| **J3 判据脚本修复**（`scripts\j3_soft_verify.py`，+15/−4） | `4E96E45031E4A30F04670A564196DAA344DBE83B0C2B0AF770A3A0E71845CA25` | 已核（工作树 M；blob `59a2d7e`）——**独立软件侧 [L4]**，详见 §4.2 |
| **J3 修复复验日志** | `green_dma_j3_run5_warmfix.log`（`EC88E541`，1699 B） | 已核（[L4] 复验 PASS，21:17:36） |
| S0–S8 设计说明（Lead） | `out\S0S8_DESIGN.md`（`8EBAA048`，36364 B） | 已核（判据口径文档，非产物） |
| 绿 vs 退役 发射流掩码比对日志 | `{{PENDING:rdcap2_cmp_green_retired.log}}` | **PENDING**（`ndiff_after_mask=0` 目前为 Lead 实测口述；建议把 cmp 输出落盘归档） |
| NIC `+296` 原始前后读数 | `{{PENDING:Get-NetAdapterStatistics 前后值}}` | **PENDING**（现记于 `S0S8_DESIGN.md` §1.3） |
| 修复提交 commit | `{{PENDING:git hash}}` | **PENDING**（工作树未提交：**4 个 M 文件** = RTL + 2 TB + `j3_soft_verify.py`） |

---

#### 9) 教训（写进坑账本候选）

**① 旧 S2–S6 脚本两处失效（今天最重要的方法论坑）**

`out\retire_s2_s6.ps1` 的 S4 跑 `manual_round.py COM5 1`（即 `'M'` 轮），随后 S5 直接 ping。固件 `round_command()`（`sw\src_j3\main.c:340-382`）有两条副作用，使 S5 变成**无效实验**：

- **(a) M 轮末把引擎位写回 0**（`main.c:375-379`：`if (g_dma_mode) { g_dma_service=0u; R_ENGINE=0u; }`）⇒ S5 ping 时 `R_ENGINE=0`；
- **(b) `R_MODE` 停在 RND、轮末不恢复**（`main.c:358` 置 `MODE_RND`；`:380-381` 注释明说"不在此恢复 SEQ"）⇒ 顶层只在 SEQ 下自动装读请求（`aurora_mem_bridge.v:322-327`），RND 下没人发读命令 ⇒ **读侧零启动、`WM_RD` 冻结**。

⇒ **判据：任何"M/A/B 轮之后直接 ping"的对照都无效**（绿位流同样 0/N）。有效判据必须「上电 → `'d'`（确认 DMA）→ ping 中途不跑 M/A/B → 前后 `'U'` + NIC delta」。今天 `s2_s6_201701.log`/`s2_s6_204148.log` 两个 S5 都是无效样本；`clean_engine1_ping_204321.log` 才是有效样本。**开跑前先问：这个序列会不会在判据前把 engine/mode 改掉？**

**② 共享模块的"退役/删除"必须按实例作用域做**

删逻辑/状态机前先枚举**所有实例及其参数化差异**（本模块 2 实例：`HAS_DMA=1`/`0`）。只看顶层实例的端口接线（"`u_mem2` 的 DMA 口恒 0、没碰它"）会漏掉**模块内部共享逻辑**——20:45 的离线审计就是这么漏的。正确写法 = 用 `HAS_DMA` 之类的**结构常量**在模块内分支，并写明"该分支对哪个实例生效"。

**③ 参数化守卫要选结构常量，不要选运行态位**

`dma_engine` 是 `'d'` 可翻转的运行态开关；用它守卫会让缺陷随 `'d'` 时隐时现、并破坏桥① 的 DMA-only 收口。结构差异用 `HAS_DMA` 守卫；运行态开关只用于"设计上本就允许的运行模式"。

**④ 无超时的 `R_DRET` 是放大器，不是根因**

R_DRET 唯一出口是 `shim_frame_done`，单笔丢失即永久停泊（H6）。排查时先用**读退休计数**定位"FSM 停没停"（桥② `mem2_rd_frm` 恒 0 一眼定性），再谈字节流；不要从最下游（PHY/网卡）倒推。

**⑤ "文件存在 ≠ 证据有效"**

今天有三份"看起来是证据"的无效产物：第一轮 ILA（engine 被翻回 bridge，CSV 已被覆盖）、第一次 `rdcap2` 抓取（probe 未解析）、`clean_engine1_ping_204258.log`（空格式串）。收口前必须按 `R1_evidence_index.md` §1/§6 核对**哪一份是有效轮**；同名 CSV 被覆盖时，用流程日志（`r1cap3_vivado.log`）+ UART 时间戳界定轮次。

**⑥ 判据口径依赖环境态（静态邻居 → ARP 行为改变）**

10-17 加 PC 永久静态邻居后，PC 不再发 ARP ⇒ 板 ARP 表学不到 PC MAC ⇒ 自发帧 dst 变广播。**"发射流同构"判据必须带环境掩码或同环境绿参考**，否则 S8 会假红；反过来，若看到 dst 广播就判"帧构造错了"也是误判。

**⑦ 对照基线必须带"模式/序列前缀"**

同一个绿位流、同一天：`green_engine1_4tier.log` 四档全 PASS，而 `green_engine1_j3_dma.log` 的 J3 四链当次 FAIL（`wr+255`、PC 收帧 0）。该 FAIL 的根因后来**不是**位流/序列，而是**判据脚本**的预热帧副作用（§4.2）⇒ "绿位流是好的"这句话同样只在**具体模式+脚本版本**下成立；把"绿 = 全好"或"脚本 = 中立"当无条件基线，会把工具缺陷错算成回归。收口判据要写成「**绿 + 桥模式 + 四档** = PASS」「**绿 + DMA + `j3_soft_verify`（修复后）** = PASS」这种带前缀的形式。

**⑧ 判据工具自身也是被测件：先查脚本，再查 RTL（[L4] 实证）**

`j3_soft_verify.py --dma` 的三次"`wr+255`"，最终定位为脚本在 SEQ 窗发的 1 个预热帧占槽（不是 RTL/位流问题），且桥模式下同一脚本一直 PASS。⇒ 看到"判据前 1 帧之差/差 1 槽"这类 off-by-one，优先核对**脚本在判据前的副作用**（预热帧、哑写、状态查询、引擎翻转），而不是先怀疑硬件。这也解释了 §三之十九之补 §1 "DMA 三链 PASS" 与今日 FAIL 的"矛盾"：不是硬件退化，是脚本缺陷在不同模式下暴露不同。

**⑨ 失败纪律：`wr+255` / 收帧停摆不得重试**

重试会级联出更多假 FAIL（`[A]/[B] wr+0`），并可能把板卡留在"256 槽未读 + 读 FSM 泊 `R_DRET`"的**半楔死状态**（需重烧恢复）。正确处置 = 判「判据未取得 + 板卡需重烧」，**新烧录后重跑**；J3 前必须清槽（`'S'` + 只读轮询 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍）。

**⑩ NIC 判据要按环境选计数器（同一机制的两处表现）**

静态 ARP 邻居 ⇒ 板自发帧 dst MAC = 广播 ⇒ `ReceivedUnicast` delta 恒 0，**主判据必须用 `ReceivedBytes`**（单帧 74B、4 帧 296B）；这与"发射流掩码要掩 dst(8–13)"是同一机制的两处表现。看到"ping 通但 NIC Unicast 不动"不要判"没到线上"——先看 `ReceivedBytes`/`ReceivedBroadcastPackets`。
