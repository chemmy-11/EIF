# §三之二十 最终版（待 Lead 合入调试记录）

- **目标文件**：`C:\Users\***\Desktop\毕设\调试记录\阶段三_prj11_B3-1三主仲裁器与DMA读路径设计_2026-10-12.md`
- **插入位置**：`### 三之十九之补四`（当前 L976–L1002）之后、`## 三、当前状态（末版快照）`（当前 L1003）之前；并按 §⑧ 回填文末「当前状态（末版快照）」。
- **版本**：2026-10-17 21:36 **最终版**（`record_section_draft.md` 为过程草稿，本文件为定稿；两者冲突以本文件为准）。
- **依据等级**：根因与修复复验均已闭合 ⇒ **[L4] 定案**。证据索引：`out\evidence_2026-10-17\R1_evidence_index.md`。
- **写作口径**：记录只增不改——对旧结论的更正一律用「补记」引用，不删原文。

---

### 三之二十、退役位流读侧收口定案（2026-10-17 晚·续）：根因 = 共享模块退役误伤桥②读引擎；修复 = 读 FSM 按 `HAS_DMA` 参数化 + J3 判据脚本 DMA 预热帧缺陷修复（S0–S8 与四判据全过）

**本节一句话（定稿）**：8afa168 把「DMA 为唯一读出路径」的退役改动做进了**两个桥共用**的 `axi4_master_bridge.v`，把桥②（`u_mem2`，`HAS_DMA=0`、没有 DMA shim）的硬件读 FSM 一并删掉 ⇒ 桥② 读路径死、泵B 无输入 ⇒ 出向帧不上线。修复按 `HAS_DMA` 参数化恢复读 FSM；**修复版位流 `c8cd3a32` 上 S0–S8 全 PASS、四判据全过**，S7 桥级 ILA 计数直接闭合（桥② 读帧随 ping +4、outstanding 恒 0），S8c 发射流与绿参考掩码后**逐字节同构**。另定案一处**判据脚本缺陷**（J3 `--dma` 预热帧占槽）并修复复验——该缺陷与 RTL/位流无关。

---

#### 1) 现象与有效判据（含原始日志引用）

**1.1 有效序列（唯一可用的板上判据序列）**

上电 → 发**一次** `'d'`（翻转语义）→ 解析回显 `DMAMODE now=DMA` → `'U'` 断言 `req` bit24=1 → **ping×4（中途不跑任何 M/A/B 轮）** → 再 `'U'` + PC 网卡计数。
旧退役位流 **`3aa600aa`**（`archive\b31b_rdclose_2026-10-16\`）+ ELF **`2961b585`**。
原始日志：`out\evidence_2026-10-17\clean_engine1_ping_204321.log`（UTF-16LE，3280 B，SHA256 前 8 `B56EB203`）。

| 观测量（`'U'` 解码） | ping 前 | ping 后 | 判读 |
|---|---|---|---|
| `wmwr`（`+0x08`） | 11 | **15** | +4 = ping×4 的写帧 |
| `wmrd`（`+0x0C`） | 11 | **15** | +4 ⇒ 桥① 读侧逐帧退休，DMA 唯一读出路径**是通的** |
| `req`（`+0x34`） | `0x010A0056` | `0x010E0056` | bit24(engine)=1、bit25(dreq_new)=0 |
| `emit`（`+0x3C`） | `0x00560A55` | `0x00560E55` | `{len=0x56=86, slot=10→14, byte0=0x55}` ⇒ 发射口字段正确 |
| `arl`（`+0x38`） | `0x0010A000` | `0x0010E000` | 末笔 DMA AR = `SLOT_BASE+slot*0x1000`，随 slot 前进 |
| PC 网卡 | Unicast 7023 / Bytes 1310802 | 同左 | delta=0 |
| `ping -n 4` | — | — | **0/4（100% loss）** |

⇒ **判据 C1（[L3]）**：桥① 读退休/AR 地址/发射字段全部正常而线上零帧 ⇒ 失败段**严格在「桥① 发射口之后」**（第二跳：`axis_word_pack→Aurora TX/RX→u_unpack→桥②→泵B→mux→gmii_to_rgmii`）。

> `'U'` 解码口径（`sw\src_j3\main.c:448-472`）：单读行（id/req/wmrd/stat/wmwr/ust）**首值是上一地址残值，只取第 2..6 值**；`dread` 双读行（reqX/arl/emit）3 值均新鲜。`emit` 布局 `{len[31:16], slot[15:8], byte0[7:0]}`（`rtl\frame_mem_if.v:507-524`）。`mode=` 是软件标志 `g_dma_mode`，**不是** `R_ENGINE`/`cfg_mode` 的硬件状态（`main.c:470-471`）。

**1.2 桥级 ILA 计数（旧位流 vs 修复位流，[L4] 直接闭合）**

同一 `'d'`→ping×4 序列，ping 前后各抓一次 ILA（`out\evidence_2026-10-17\ilacap_*.csv` + 汇总）：

| 位流 | 实例 | 观测量 | ping 前 | ping 后 | 判读 |
|---|---|---|---|---|---|
| **旧退役 `0ecb8438`** | 桥① u_mem | `dbg_mem_wr_frm` / `rd_frm` / `ost` | 19/19/0 | 23/23/0 | 桥① 正常 |
| 旧退役 `0ecb8438` | **桥② u_mem2** | `dbg_mem2_wr_frm` / `rd_frm` / `ost` | 19/**0**/19 | 23/**0**/23 | **写帧 +4、读帧恒 0、outstanding 只增不减 ⇒ 桥② 读路径死**（旧版缺陷直证，`ilacap_counters_summary.txt`） |
| **修复版 `c8cd3a32`** | 桥① u_mem | `dbg_mem_wr_frm` / `rd_frm` / `ost` | 777/777/0 | 781/781/0 | 正常（+4/+4） |
| **修复版 `c8cd3a32`** | **桥② u_mem2** | `dbg_mem2_wr_frm` / `rd_frm` / `ost` | 777/**777**/0 | 781/**781**/0 | **写帧 +4、读帧 +4、outstanding 恒 0 ⇒ 桥② 读路径已通**（`ilacap_rdfix_counters_summary.txt`，21:34 轮） |
| 修复版 `c8cd3a32` | user 域 | `dbg_mem2_u_wr` / `u_rd` | 777/777 | 781/781 | 与 ui 域一致 |

⇒ **判据 C3（[L4]）**：修复前"桥② 写帧在涨、读帧恒 0、ost 只增不减"、修复后"读帧同步 +4、ost 恒 0"——**同一观测口径的前后对照闭环**，桥② 读路径是本次缺陷的唯一断点。

**1.3 桥① 发射字节流：字节级正确且与绿参考同构（[L3→L4 闭环]）**

旧退役位流、engine=1，`out\jb31b_rdcap2.*` 抓桥① 发射口（ILA1，`dbg_mem_rden`+`mem_rd_data[7:0]`，触发 `dbg_mem_rden_1 eq 1`）：

- `rdcap2_retired.csv`（20:54 轮）：1526 B、首 8B `55×7,D5`、1526 拍无气泡；与归档绿参考严格差 14 B，位置 = `8–13`（dst MAC）、`26–27`（IPv4 ID）、`32–33`（IP 校验和）、`1522–1525`（FCS）——**dst 广播是静态 ARP 环境所致**（板端学不到 PC MAC），不是缺陷。
- `rdcap2_cmp_green_retired.log`（21:30）：绿 `rdcap2_green.csv` vs 旧退役 `rdcap2_retired.csv`，掩 `8-13,26-27,32-33,-4..-1` 后 **`ndiff_after_mask=0`、`ISOMORPHIC=YES`**。
- 修复版 `c8cd3a32`：`rdcap2_rdfix.csv`（21:35，1526 B）vs 同环境绿参考 `rdcap2_green.csv`，同掩码 → **`ndiff_after_mask=0`、`ISOMORPHIC=YES`**（`rdcap2_cmp_green_rdfix.log`；修复版 dst 已恢复为 PC MAC `08:3c:03:a0:26:96`——因为修复后 ping 通、板端 ARP 学到了 PC MAC，属环境态恢复，非逻辑变化）。

⇒ **判据 C2（[L4]）**：桥①→Aurora 发射字节流**始终正确**（旧位流与修复位流均与绿参考同构）⇒ 缺陷只在桥② 读路径，与「发射字节流/帧长/槽号/前导」无关。

**1.4 无效实验的识别（作废样本留痕，详见 §9-①⑤）**

- `s2_s6_204148.log` / `s2_s6_201701.log`：旧 S2–S6 脚本 S4 跑 M 轮后 S5 ping ⇒ `WM_WR 2→7`、`WM_RD 2→2`（`0ecb8438` 轮）——**读侧零启动，无效实验**；不能用于"位流差异"结论。
- 20:51 第一轮 ILA（`r1cap_vivado.log`，`'U' mode=0`）⇒ engine 被 `'d'` 翻回 bridge，无效；CSV 已被第二轮覆盖。
- `clean_engine1_ping_204258.log`（空格式串）、`rdcap2_retired_vivado_10272.backup.log`（probe 未解析）⇒ 抓取失败留痕。

---

#### 2) 根因（[L4] 定案：代码级 + 板上直接观测 + 修复前后对照）

**2.1 代码级：退役改动落在两个桥共享的模块里，桥② 被连坐**

- 提交 `8afa168`（2026-10-16 18:37）在 `prj\project_11\rtl\axi4_master_bridge.v` 把 R_PRE 的引擎二选一：

```verilog
// 退役前（3f847e3）
end else if (dma_engine) begin   // DMA 读引擎：发 {slot,len}，等 shim frame_done
    dma_req_new <= 1'b1; ... rstate <= R_DRET;
end else begin                   // 桥硬件读引擎：R_AR→R_R→R_UNPACK→R_FIN
    r_slot<=p_eff; ... rstate <= R_AR;
end
// 8afa168：去掉 dma_engine 条件，无条件进 DMA 分支，并删除 R_AR/R_R/R_UNPACK/R_FIN
```

- 该模块由 `frame_mem_if` 内 `u_bridge` 例化，而 `HAS_DMA` 由顶层决定：桥① `u_mem`（`aurora_mem_bridge.v:772`，默认 `HAS_DMA=1`，有 DMA shim）与桥② `u_mem2`（`:917`，**`HAS_DMA=0`**，DMA 口恒 0：`:956`）。
- 桥②（`HAS_DMA=0`、无 shim）在退役后：① R_PRE 无条件进 **R_DRET**，而 `shim_frame_done` 在 `HAS_DMA=0` 分支**无驱动**（退役归档 `axi4_master_bridge_retired.v:547` 只声明 wire）⇒ 恒 0、R_DRET 无出口（无超时/看门狗，H6）⇒ 读 FSM **永久停泊**；② `gen_no_dma` 的 `rf_wr_en=brf_wr_en`，而 `brf_wr_en` 只在已删的 R_UNPACK 置位 ⇒ **读数据口无源**；③ 桥② 是泵B 唯一数据源（`aurora_mem_bridge.v:1194-1206`）⇒ 泵B 无输入 ⇒ 出向帧全部停在上线前。
- **结论**：退役的正确作用域是 `HAS_DMA=1` 实例；8afa168 用"无条件删分支"实现，等效于把作用域扩大到 `HAS_DMA=0` ⇒ 结构性误伤。

**2.2 板上直接观测（[L4]）**：见 §1.2 表（旧位流：桥② 写 +4/读 0/ost 19→23；修复位流：写 +4/读 +4/ost 恒 0）。替代解释已逐项排除：Aurora/解包/写侧（`mem2_wr_frm` +4 活着）、复位（计数在涨）、桥① 读出（`mem_rd_frm` +4）、泵B（`mem2_rd_frm=0` 是其上游原因）。

**2.3 对 20:45 离线审计的更正（补记）**

`out\evidence_2026-10-17\rtl_audit_204519.md` §2 Δ5/§4.1 判"`u_mem2` 未被退役影响"**错误**：被删的读 FSM 在 `axi4_master_bridge.v` **模块内部**，实例差异由 `HAS_DMA` 在模块内展开；只看顶层实例端口接线会漏掉"共享模块内部逻辑"。本记录以 §1.2 的 ILA 前后对照直接反证；审计原文保留不改。

---

#### 3) 修复（RTL + 判据脚本；构建结果）

**3.1 RTL 修复（工作树 M，未提交；`git diff --stat` = 3 文件 +68/−4）**

| 文件 | 改动 |
|---|---|
| `rtl\axi4_master_bridge.v` | ① R_PRE 判定改为 `if (HAS_DMA)`：`HAS_DMA=1` 保持 DMA-only 泊 `R_DRET`；`HAS_DMA=0` **恢复 `R_AR` 入口**。② **恢复 `R_AR/R_R/R_UNPACK/R_FIN` 四态**（与退役前 `3f847e3` 逐字节相同，独立复核 §5.1 已证）。③ `gen_no_dma` 增 `assign shim_frame_done = 1'b0;`。④ 注释写明作用域。 |
| `sim\mem_bridge_tb.sv` | `frame_mem_if` 实例显式 `.HAS_DMA(0)` |
| `sim\w4_joint_tb.sv` | 两个实例显式 `.HAS_DMA(0)` |

**参数化理由**：① 作用域是结构性的（实例级决策），`HAS_DMA` 才表达"该实例有没有 shim"；`dma_engine` 是 `'d'` 可翻转的运行态开关，若用它守卫会让缺陷随 `'d'` 时隐时现并破坏桥① 的 DMA-only 收口；② 桥② 的 `dma_engine` 恒 0（`:956`），退役前的 `else if (dma_engine)` 对它恒选硬件读；③ 可达性/剪枝已验证：`HAS_DMA=1` 时 R_AR..R_FIN 不可达、`HAS_DMA=0` 时 R_DRET 不可达（tie-0），无悬空/无多驱动；④ 恢复块与退役前逐字节相同，最小可审计。

**3.2 J3 判据脚本修复（独立 [L4]，与 RTL/位流无关）**

`scripts\j3_soft_verify.py`（工作树 M，+15/−4，blob `59a2d7e`）：`run_round(..., warm_probe=True)`，主流程 `--dma` 时传 `warm_probe=(not args.dma)`（附 6 行机制注释）。根因见 §4.2。

**3.3 修复版构建（`c8cd3a32`；构建闸门全过）**

| 项 | 值 |
|---|---|
| 位流 | **`c8cd3a32`**（`archive\b31b_rdfix_2026-10-17\aurora_mem_bridge_rdfix_c8cd3a32.bit`，9,746,300 B） |
| 构建日志 | `archive\b31b_rdfix_2026-10-17\build_retire_fix_sweep.log`：`SWEEP_ExtraTimingOpt: WNS=0.004 WHS=0.004`、`V5_SWEEP_OK`、DRC **0 Errors**；`build_retire_fix_synth.log` 同归档 |
| RTL 身份 | 工作树 blob **`7fe880e`**（`git hash-object` 实算；归档 `axi4_master_bridge_rdfix.v` 同 hash `18dc7c4b…`） |
| 探针 `.ltx` | `probes_rdfix_c8cd3a32.ltx`，hash **`352a5f28…`**（与旧 v5rtl probes.ltx **逐字节相同**） |
| `.xsa` | `c9b52dd7…`（2,526,101 B，`out\mb_ctrl.xsa`） |
| ELF | `2961b585`（未变） |

**3.4 独立复核（离线，[L2]→已被上板覆盖）**

`out\evidence_2026-10-17\rtl_fix_review_205656.md`：A 完备性 / B 参数化可达性 / C 单一驱动 / D 与退役前语义等价 / E 桥① 仅 DMA 全过，无功能性缺陷（3 条非阻塞项：过期注释、TB P1 标签、构建闸门）。

---

#### 4) 离线回归

**4.1 RTL/TB 仿真（全绿；日志已归档为 `sim_*_run.log`）**

| TB | 编译参数 | 结果 | 日志（本目录副本 / 原路径） |
|---|---|---|---|
| `bridge_dma_tb`（桥① DMA 路径） | 默认 `HAS_DMA=1` | **PASS 0 errors**（P1/P2/P3；NEG 按设计） | `sim_bridge_dma_run.log` / `sim\bdma_run.log`（`A4C3F4DD`） |
| `mem_bridge_tb`（W2，桥② 硬件读语义） | **`HAS_DMA=0`** | **PASS 0 errors**（T1–T6；`rd_frame=585`、`rd_beats=8202`） | `sim_W2_mem_bridge_run.log` / `sim\xsim_run.log`（`02F7D25E`） |
| `w4_joint_tb`（W4，双桥） | 两实例 `HAS_DMA=0` | **正向 `DEFECT=0` PASS**（P1–P5，A/B 各 `rd=148`）；**负向 `DEFECT=1` 按设计 FAIL/deadlock** | `sim_W4_joint_run.log` / `sim\w4_joint_run.log`（`FC40B951`） |

> 注：`bridge_dma_tb` 的 P1 打印标签"engine=0（桥硬件读）"是退役前遗留字样，实际走 DMA 路径（R_PRE 已不看 `dma_engine`）；判读勿被标签误导（复核报告 §8-②）。

**4.2 J3/J3′ + 负向 A/B（判据脚本侧）：[L4] 机制定案 + 修复复验**

| 项 | 内容 |
|---|---|
| **现象（[L3]）** | 绿位流 `708f15a4`+ELF `2961b585`，`--dma` 模式连续 3 次 `[M] wr+255`（写少 1 帧）→ 读阶段不启动 → 槽满级联 FAIL（`green_engine1_j3_dma.log`/`run2`/`run3_nowarmup`） |
| **根因（[L4-机制]）** | `run_round()` 在 SEQOK 后、GO 前**无条件发 1 个预热帧**；DMA 模式下此刻是 SEQ 窗且软核正停在 `round_command` 等 GO（**驻留服务不在跑**）⇒ 该帧写入后读请求**永泊 `R_DRET`**、占 1 槽；写阶段第 256 帧因**槽表满**被拒 ⇒ `WAITWR-FAIL got+255`。桥模式（engine=0）下该帧由硬件读引擎自动退休、不留残槽 ⇒ 同脚本桥模式一直 PASS（`green_bridge_j3_run1.log`） |
| **修复** | `warm_probe=(not args.dma)`（`--dma` 跳过预热帧，桥模式保留预热） |
| **修复复验（[L4]）** | 绿位流新烧录 + `--dma`：`green_dma_j3_run5_warmfix.log` **`[B2-SOFT-VERIFY] PASS`**（`[M] wr+256 rd+256 inv=32385` / `[A] wr+256 rd+255 inv=32131 miss=[5356]`=恰帧#100 / `[B] wr+256 rd+256`）；修复版位流上同一脚本亦全 PASS（§5 S8b） |
| **加严纪律** | ① `wr+255`/收帧停摆**不得重试**（级联假 FAIL + 可能留 256 未读槽半楔死，需重烧）；② J3 必须**新烧录后**跑（旁证 `green_fresh_manual_round_256.log`=新烧绿后 `manual_round 256` PASS）；③ 跑完轮末 `R_ENGINE=0`、`R_MODE=RND` ⇒ 后续 ping 判据必须重发 `'d'`/`'S'` |
| **最终 J3 口径（口径统一）** | **带 `--dma` 跑 M/A/B**（脚本已修、`j3_fourchains.ps1` 已改为 `--dma`；`j3_fourchains_20261017_213200.log` 头部为"带 --dma 跑 M / A / B"、`j3_m` 板端 `DMAMODE now=DMA`）。`retire_s0_s8.ps1` 内"S8b 不带 --dma"是旧文案，Lead 同步改文字（不影响实测行为） |

---

#### 5) 上板判据 S0–S8 结果（**全 PASS**）

- 执行工具：`out\retire_s0_s8.ps1`（`-Run`）；原始日志：`out\evidence_2026-10-17\s0s8_20261017_213020.log`（36,448 B）+ 控制台全量 `s0s8_run_console.log`（66,436 B）。
- **总判据：`S0S8_RESULT: PASS`（exit 0）**；配置 = 修复版位流 `c8cd3a32` + ELF `2961b585`。

| 步 | 动作 | 实测结果 | 状态 |
|---|---|---|---|
| S0 | 离线核对位流/ELF/构建日志 | `WNS=0.004 WHS=0.004`、成功标记有、bit8=`c8cd3a32`、elf8=`2961b585` | **PASS** |
| S1 | 绿配置对照 `708f15a4`+`2961b585` | ping **3/3**、`'L'` 应答、邻居 `Permanent` | **PASS** |
| S2a | 新位流先不发 `'d'`，M 轮 1 帧 | `WAITWR-FAIL got+1`、无 DONE、echo=0（"非身份判据"但确认不冒充通过） | **PASS** |
| **S2b** | **不发 `'d'` ping 1** | ping **0/1**、NIC `ReceivedBytes delta=0` ⇒ **无读出路径 = 退役版身份** | **PASS** |
| S3 | `'d'` 后回读 | `req.bit24=1` & `mode=1`；bit25=0；slot=2 len=86 | **PASS** |
| S3b | 静默窗 | `wmwr==wmrd` & `sticky=0` 连续两拍 | **PASS** |
| **S4** | **单帧端到端**（`ping -n 1`，不跑 M 轮） | ping **1/1**、NIC `ReceivedBytes +74`、**`WM_WR +1` / `WM_RD +1`** | **PASS** |
| **S5** | **ping×4** | ping **4/4**、NIC `ReceivedBytes +296`、**`WM_WR +4` / `WM_RD +4`** | **PASS** |
| **S6** | `'U'` 分叉 | `emit` 字段正确（len/slot/首字节 0x55）+ 线上 4/4 + NIC +296 ⇒ 第一跳与第二跳全通 | **PASS** |
| S7 | ILA 计数（Lead 补跑） | 桥② `dbg_mem2_wr_frm` 777→781、**`dbg_mem2_rd_frm` +4**、`ost` 恒 0；桥① 同步 +4、ost 0（`ilacap_rdfix_counters_summary.txt`） | **PASS（[L4]）** |
| **S8b** | **J3 四链（带 `--dma`）** | `[M] PASS wr+256 rd+256 inv=30417 miss=0`；`[A] PASS wr+256 rd+255 inv=30171 miss=[5100]`（base 5000 ⇒ **恰帧#100**，负向设计）；`[B] PASS wr+256 rd+256`；`[B2-SOFT-VERIFY] PASS`；`FOURCHAINS_RESULT: PASS` | **PASS** |
| **S8c** | **发射流同构**（Lead 补跑） | `rdcap2_rdfix.csv` 1526 B/前导 OK；与绿 `rdcap2_green.csv` 掩码后 **`ndiff_after_mask=0` / `ISOMORPHIC=YES`** | **PASS** |
| **S8d** | **四档零回归**（修复版 engine=1） | `DDR_VERIFY: PASS`：ping 20/20、基础 12/12、槽深 12/12、稳定 300/300（100%、0 超时 0 损坏、15.3s） | **PASS** |

**四判据（R1 判定）在退役位流上全部取值通过**：① ping/ARP（S2b 0/1 → S5 4/4）；② 四档逐字节（S8d 全 PASS）；③ J3/J3′（S8b M/A/B 全 PASS，含 J3′ 集合一致）；④ 负向 A/B（S8b 中 [A] 恰帧#100、[B] 重读槽不产出，均按设计 PASS）。**「DMA 为唯一读出路径」在修复版退役位流上成立**。

---

#### 6) 结论与依据等级（[L4] 定案）
**定稿判据：修复后在退役位流（`c8cd3a32` + ELF `2961b585`）上，全部 4 条判据均取值通过**——① ping/ARP（S2b 身份 0/1 → S4 1/1 → S5 4/4）；② 四档逐字节（S8d `DDR_VERIFY: PASS`，20/20·12/12·12/12·300/300）；③ J3/J3′（S8b M/A/B 全 PASS，带 `--dma`）；④ 负向 A/B（S8b 中 [A] 恰帧#100、[B] 重读槽不产出，均按设计 PASS）。附加闭合：S7 桥② 读帧 +4/`ost` 恒 0；S8c 发射流与绿参考 `ndiff_after_mask=0`。

1. **根因（[L4]）**：8afa168 在**共享**模块 `axi4_master_bridge.v` 内无条件删除硬件读 FSM，使 `HAS_DMA=0` 的桥②（`u_mem2`，无 DMA shim）读 FSM 永久停泊、读数据口无源 ⇒ 泵B 无输入 ⇒ 出向帧不上线。**对照矩阵闭合**：旧位流 vs 修复位流同一 ILA 口径（桥② 写 +4；读 0 vs +4；ost 19→23 vs 恒 0）；修复后 S0–S8 全 PASS；离线 W2/W4/bridge_dma TB 全绿。
2. **修复（[L4]）**：读 FSM 按 `HAS_DMA` 参数化（`HAS_DMA=1` DMA-only 不变 / `HAS_DMA=0` 恢复硬件读）+ `shim_frame_done` tie-0 + 两个 TB 显式 `HAS_DMA(0)`；修复版位流 `c8cd3a32`（WNS/WHS +0.004）上 S0–S8 与四判据全过。
3. **独立软件侧 [L4]**：J3 判据脚本 `j3_soft_verify.py` 的 DMA 预热帧缺陷已修复（`warm_probe=(not args.dma)`）并复验 PASS；与 RTL/位流无关。
4. **对旧结论的更正（补记，记录只增不改）**：
   - **补记①**：§三之十九之补四 的对照表（"两侧 `wmwr/wmrd` 均 1/1→4/4、逐项相同"）与归档原始日志 `s2_s6_204148.log` 矛盾（实为 `WM_WR 2→7`、`WM_RD 2→2`，旧序列无效）。有效序列下退役侧 `WM_WR/WM_RD` 为 11→15（+4/+4），说明"读退休"正常，问题只在"上不上线"。
   - **补记②**：`rtl_audit_204519.md` §2 Δ5/§4.1 "u_mem2 未被退役影响"判断错误（漏看共享模块内部逻辑），见 §2.3。
   - **补记③**：§三之十九之补二 的"归档位流与 RTL 不对应 / 网表差异"候选（H2/H4）**已排除**：机制由 ILA 直接锁定且修复复验闭环，无需再作为 R1 阻塞项。
   - **补记④**："失败段在桥① 发射口之后"的收窄**成立且已闭环**：桥① 发射流字节级正确（旧/新位流均与绿参考同构），断点在其后第二跳的**桥② 读侧**。
   - **补记⑤**：J3 判据"绿位流 DMA 下 FAIL"不是位流回归，是判据脚本缺陷（[L4]，见 §4.2）。
5. **剩余未决（不属本节结论）**：① 修复提交（4 个 M 文件）与文档回填的 commit；② 零余量旁证（`0ecb8438` WNS=0.000）不再用于功能判据——修复版 `c8cd3a32` 为 +0.004；③ `retire_s0_s8.ps1` 的 S8b 旧文案（"不带 --dma"）待同步（不影响实测）。

---

#### 7) 运维口径变化（上板前先读）

1. **`'d'` 是翻转不是置位**（`sw\src_j3\main.c:436-446`）：脚本必须「`'U'` 回读 `mode`+`req.bit24` → 不匹配才发 `'d'` → 再回读；**最后同时满足 `mode=1` 且 `req.bit24=1` 才继续**」，最多翻转 3 次（`retire_s0_s8.ps1` 的 `Set-EngineMode` 已实现）。**不要盲发两次**（第二下会关掉 DMA 驻留服务）。今天两次翻回 bridge 的留痕：`r1cap_uart_pre/post.log`（`mode=0` 无效轮）、`r1cap_uart_pre2.log`。
2. **退役位流每次上电必须先 `'d'` 才有桥① 读出路径**（`g_dma_mode` 默认 0）；桥② 的硬件读路径与 `'d'` 无关（`HAS_DMA=0` 恒开）——修复后不要误以为"桥② 也归 engine 位管"。
3. **烧录**：一律绝对路径 + `Get-FileHash` 核对，**不要引用默认名产物**（`out\aurora_mem_bridge.bit` 现为修复版 `c8cd3a32`（21:28 写入），下一次构建又会变；认归档 `archive\b31b_rdfix_2026-10-17\`）。
4. **`'U'` 探针口径**：单读行首值是上一地址残值（只用第 2..6 值）；`dread` 行（reqX/arl/emit）3 值新鲜；`U mode=` 是软件标志 `g_dma_mode`，不是硬件 engine/`cfg_mode`；`req` bit24 的回读语义已过期（RTL 不再消费 engine 位做读出选择）。
5. **ILA 可观测性足矣**：u_ila_3 已含 `dbg_mem2_wm/rd_frm/ost`（`scripts\build_debug.tcl:241-265`），修桥② 不需改 RTL 加探针；S7 判据 = 桥② `rd_frm` 前进、`ost` 回落。
6. **发射流"同构"判据**：掩 `dst(8–13)+IPv4 ID(26–27)+IP 校验和(32–33)+FCS(末4B)`；静态邻居下旧退役流 dst=广播、修复后 dst=PC MAC，两者掩码后均与绿参考 `ndiff_after_mask=0`。
7. **NIC 主判据 = `ReceivedBytes`**（不是 `ReceivedUnicast`）：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ Unicast 恒 0。S4 要求 `Bytes ≥74`、S5 要求 `≥296`（4×74）；`ReceivedBroadcastPackets` 仅辅助。绿侧与修复侧实测均满足。
8. **J3 执行纪律（[L4]）**：带 `--dma` 跑；必须**新烧录后**跑；前置 `'S'` + 只读轮询 `'U'` 到 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍；`wr+255`/收帧停摆不得重试；跑完轮末 `R_ENGINE=0`/`R_MODE=RND` ⇒ 后续 ping 判据重新 `Set-EngineMode DMA`+`'S'`。
9. **旧 `out\retire_s2_s6.ps1` 不再用于 R1 判据**（S4/S5 无效，§9-①）；保留作流程回归时须在 S5 前插「重新 `'d'`（确认 DMA）+ `'S'`」。

---

#### 8) 产物 hash（定稿；完整值见 `R1_evidence_index.md` §3/§10）

| 产物 | SHA256 | 状态 |
|---|---|---|
| **修复版位流 `c8cd3a32`** | `C8CD3A32E6AA965F26E9429AD75204C78953366DE31571DDDB379DDA8976BA80` | **已核**（9,746,300 B；`archive\b31b_rdfix_2026-10-17\`；SHA256.txt 8/8 一致） |
| 修复版 RTL 快照 | `18DC7C4B50C0F6457A3FA820D0220745F141F04B7C1DBC7BF02E7EB65F859C3F` | 已核（= 工作树 blob `7fe880e` 的文件 hash） |
| 修复版构建日志 | `07D2F601…6794DB`（sweep，303,467 B）/ `732C340D…471535`（synth，178,197 B） | 已核 |
| 修复版探针 `.ltx` | `352A5F283D229FB91398BEA49036FCFC130CD9988916F23A8257B3297C3A11A2` | 已核（与旧 v5rtl probes 相同） |
| 修复版 `.xsa` | `C9B52DD79E2097250E130A592B3DA2F5DDFB698A8A072F18948B7871AC459350` | 已核（2,526,101 B） |
| ELF `2961b585` | `2961B585133DDE6D5C47AFAE9AA722A52D7B4E0813474ACED384B39D3771ADDF` | 已核 |
| J3 脚本修复 | `4E96E45031E4A30F04670A564196DAA344DBE83B0C2B0AF770A3A0E71845CA25` | 已核（`scripts\j3_soft_verify.py`，+15/−4） |
| 旧退役位流 `3aa600aa` | `3AA600AA2899C361…FDFD30F` | 已核（R1 取证基线） |
| 旧退役位流 `0ecb8438` / 探针 | `0ECB8438…FB7C12` / `352A5F28…C3A11A2` | 已核 |
| 修复提交 commit | `{{PENDING:git hash}}` | PENDING（4 个 M 文件未提交） |

---

#### 9) 教训（写进坑账本：#55 共享模块退役作用域；#56 判据工具缺陷/失败纪律）

**① 旧 S2–S6 脚本两处失效**

`out\retire_s2_s6.ps1` 的 S4 跑 `manual_round.py COM5 1`（`'M'` 轮）后 S5 直接 ping。固件 `round_command()`（`sw\src_j3\main.c:340-382`）：轮末把 `R_ENGINE` 写回 0（`:375-379`）、`R_MODE` 停在 RND 且不恢复（`:358`，注释 `:380-381`）⇒ RND 下顶层不自动发读请求（`aurora_mem_bridge.v:322-327`）⇒ **S5 读侧零启动**。⇒ 判据：**任何"M/A/B 轮之后直接 ping"的对照都无效**（绿位流同样 0/N）；有效判据必须「上电 → `'d'`（确认 DMA）→ ping 中途不跑 M/A/B → 前后 `'U'` + NIC delta」。

**② 共享模块的"退役/删除"必须按实例作用域做**

删逻辑/状态机前先枚举**所有实例及其参数化差异**（本模块 2 实例：`HAS_DMA=1`/`0`）。只看顶层实例端口接线（"u_mem2 的 DMA 口恒 0、没碰它"）会漏掉**模块内部共享逻辑**——20:45 离线审计即此漏。正确写法 = 用 `HAS_DMA` 之类**结构常量**在模块内分支，并写明分支对哪个实例生效。

**③ 参数化守卫要选结构常量，不要选运行态位**

`dma_engine` 是 `'d'` 可翻转的运行态开关；用它守卫会让缺陷随 `'d'` 时隐时现，并破坏桥① 的 DMA-only 收口。

**④ 无超时的 `R_DRET` 是放大器，不是根因**

单笔 `frame_done` 丢失即永久停泊（H6）。排查先用**读退休计数**定性（桥② `mem2_rd_frm` 恒 0 一眼定位），再谈字节流，不要从最下游倒推。

**⑤ "文件存在 ≠ 证据有效"**

今天三份"看起来是证据"的无效产物：第一轮 ILA（engine 被翻回 bridge，CSV 已被覆盖）、第一次 `rdcap2` 抓取（probe 未解析）、`clean_engine1_ping_204258.log`（空格式串）。同名 CSV 被覆盖时用流程日志 + UART 时间戳界定轮次（`ilacap_*` 现为修复版轮，旧退役轮数据见 `ilacap_counters_summary.txt`）。

**⑥ 判据口径依赖环境态（静态邻居 → ARP 行为改变）**

静态邻居 ⇒ PC 不发 ARP ⇒ 板端学不到 PC MAC ⇒ 旧退役流 dst=广播、`ReceivedUnicast` 恒 0。⇒ 发射流判据掩 dst+IP-ID+csum+FCS；NIC 主判据用 `ReceivedBytes`。修复后 ping 通、板端 ARP 学到 PC MAC，dst 恢复单播（环境态恢复，不是逻辑变化）。

**⑦ 对照基线必须带"模式/序列前缀"**

同一绿位流：四档 PASS，而 `--dma` J3 FAIL；后者根因是**判据脚本**缺陷（§4.2）⇒ "绿 = 全好"与"脚本 = 中立"都不成立；判据写成「绿 + 桥模式 + 四档 = PASS」「绿 + `--dma` + 修复后 `j3_soft_verify` = PASS」。

**⑧ 判据工具自身也是被测件：先查脚本再查 RTL（[L4] 实证）**

`j3_soft_verify.py --dma` 的三次 `wr+255` 最终定位为脚本预热帧占槽（不是硬件）。⇒ 看到"判据前差 1 帧/差 1 槽"的 off-by-one，优先核对**脚本在判据前的副作用**（预热帧、哑写、状态查询、引擎翻转）。这也解释 §三之十九之补 §1 "DMA 三链 PASS" 与今日 FAIL 的"矛盾"：不是硬件退化，是脚本缺陷在不同模式下暴露不同。

**⑨ 失败纪律：`wr+255`/收帧停摆不得重试**

重试会级联更多假 FAIL，并可能把板卡留在"256 槽未读 + 读 FSM 泊 `R_DRET`"半楔死状态（需重烧）。正确处置 = 判「判据未取得 + 板卡需重烧」，**新烧录后重跑**；J3 前必须清槽（`'S'` + 只读检查 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍）。

**⑩ 收口顺序（本次验证有效的顺序）**

位流身份（S2b 不发 `'d'` ping 必须 0）→ 引擎位双重确认（S3）→ 静默窗（S3b）→ 单帧（S4）→ ping×4（S5）→ `'U'` 分叉（S6）→ 桥级 ILA（S7）→ J3 四链（S8b）→ 发射流同构（S8c）→ 四档（S8d）。**每一步都先证"判据取得"再谈通过**（NOT_OBTAINED ≠ PASS）。
