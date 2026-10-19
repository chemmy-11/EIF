# R2 round3c-diag 板验会话记录（2026-10-19 15:2x–16:0x）

> 等级标注按 AGENTS §6a。本场结论：**R2 数据面首次全通**（ping 20/20、四档 PASS、10MB 100%+SHA PASS）；
> 根因 = **固件读服务用 MM2S_DMACR.Reset 连带复位整个 AXI DMA，导致 S2MM 周期性 Halted，下一帧 LENGTH 写入无效 → 隔帧丢（50%）**；修复为固件级（无 RTL/位流改动）。

## 1. 工件身份

| 项 | 路径 | SHA256 前 8 | 大小 |
|---|---|---|---|
| 位流 | `out/archive/b31b_r2_2026-10-19_round3c/aurora_mem_bridge_r2_9852016C.bit` | `9852016C` | 10,010,456 B |
| 探针 | 同目录 `probes_r2_9852016C.ltx` | `DE94D05F` | 61,674 B（3 核：ILA0 110b / ILA3 63b / ILA5 47b） |
| XSA | 同目录 `mb_ctrl_r2.xsa` | `BEB97199` | 2,605,217 B |
| 诊断固件（事件环前） | `j3_soft_r2_DB88C9D0.elf` | `DB88C9D0` | 59,112 B |
| 事件环固件 | `j3_soft_r2_3251406F_evt2.elf` | `3251406F` | —（LMB `g_evt[512]` + 'X' 命令） |
| **50% 修复固件（fix1）** | `j3_soft_r2_69D61B9B_fix1.elf` | `69D61B9B` | 61,788 B（`s2mm_rearm`；诊断读仍 20ms） |
| **验收固件（perf1）** | `j3_soft_r2_BA3C0220_perf1.elf` | `BA3C0220` | —（`s2mm_rearm` + 写服务 GO 后 1ms + 空闲全速） |
| 构建（round3c-diag） | `out/r3c3_synth.log` / `out/r3c3_one.log` | — | `V5_SWEEP1_OK: WNS=0.004 WHS=0.004`（ExtraTimingOpt） |

构建关键点：**BD 全量 regen 后重建**（`out/r3c_regen_bd.log`），lite_regs 新增 dbg_o[35:0] 经 BD 端口 `dbg_l_bus` 引出；ILA4 被 `R3C_SKIP_ILA4` 跳过（attempt1 四核版 WNS=-0.029 被门限拒，日志见 `round3c_build_attempt1/`）；ILA5 裁为 tdata32/probe5 4b；ILA3 裁为 63b 以保 300MHz 余量。

## 2. 板端现象：楔死消失

- 烧 9852016C + DB88C9D0 → `'U'/'d'/'W'` 正常 → ping 1 → **串口仍然活着**（round3b/round2f 上同序列会 ping 后全静默 + 读回冻结 0x80010056）。
- ILA3 快照（`R3C_r3cS1_ILA3_*.csv`）：`wm=wr_frm=rd_frm=0x0d`、`ost=0`、`s2mm_state=IDLE`；ILA0 pre/post：`u_wr` 增长。
- 说明此前"读回冻结/楔死"与 BD 旧工程状态（stale 模块引用/离线状态）相关，BD 全量 regen 后不再复现。**[L2]（现象级：同固件同序列 A/B；机制未逐级定案）**

## 3. 50% 丢帧根因（[L3] 板端机制直证 + 事件环 + PG021）

### 3.1 现象与事件环
- ping 20 → 10/20（恰好隔帧）；`'I'`: wr 与 rd 各按隔帧递增；`wreq.wdbg.last_alloc_slot` 每次 +2。
- 事件环固件（`g_evt[512]`，48 事件/6 ping 全量解码见 `R3C_evt2_dump.txt`）：
  - 成功帧：`0x15` 编程(slot=N) → `0x16` 快照 `s2sr=0x1002`（Idle+IOC）→ 桥 commit → `0xD1` 读服务；
  - 失败帧：`0x15` 编程(slot=N+1) → `0x16` 快照 `s2sr=0x0001`（**Halted**、无 error 位）；
  - 桥随后 WAITDONE 超时 → `wr_fault=1`/WD_HALT → 固件 `0x10` fault 分支 `s2mm_channel_init()` 恢复 → 下一帧又成功 ⇒ 严格隔帧。

### 3.2 根因
`serve_dma_once()`（读服务）每帧执行 `DMA_DMACR = 0x4`（MM2S 软复位）。PG021（S2MM_DMACR 页）明确：
> “Setting either MM2S_DMACR.Reset = 1 or S2MM_DMACR.Reset = 1 resets the entire AXI DMA engine.”

⇒ 读服务把 **S2MM 一并复位为 Halted**；而 PG021 又规定 Halted=1 时写 `S2MM_LENGTH` “has no effect on DMA operations” ⇒ 下一帧写传输根本不会启动 → 无 introut → 桥 commit 不发生。
- URL：https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_DMACR-S2MM-DMA-Control-Register-Offset-30h （family/version 核对：All；本工程落点 Vivado 2023.1 / axi_dma 7.1 / xcku060）

### 3.3 修复（固件级，零 RTL）
1. 新增 `s2mm_rearm()`：写 `S2MM_DMACR = IOC_IrqEn | RS` → 等 Halted 落零 → `S2MM_DMASR = IOC`（W1C）；**不碰 `g_wr_last_toggle`**。
2. 调用点：①`serve_dma_once()` 读服务末尾；②`serve_write_once()` 每次编程写传输前。
3. 性能口径回退：写服务 GO 后诊断用 `busy_ms(20)+5 读` → `busy_ms(1)`；空闲环 `busy_ms(10)` → 全速（S8 1000fps 输入所需）。
- 修复固件：`j3_soft_r2_69D61B9B_fix1.elf`（诊断读版）/ `j3_soft_r2_BA3C0220_perf1.elf`（验收全速版，当前板上）。

## 4. 修复后判据（[L2] 板端实测）

| 判据 | 结果 | 证据 |
|---|---|---|
| ping（DMA 模式） | **20/20，0% loss**，RTT 0–1ms，NIC Rx delta=1480B(=74×20) | 本场串口/`Get-NetAdapterStatistics` |
| S7 四档（`udp_verify_ddr.py`） | **DDR_VERIFY: PASS**：链路 20/20、基础档 12/12、档深档 12/12、稳定档 300/300（100%，0 超时 0 损坏，15.4s） | `R3C_fourtier_perf1.log` |
| S8 10MB 质量档（`r2_mb10_sha.ps1 -Run`） | **R2_MB10_RESULT: PASS**：chunks=7022 recv=7022 lost=0 corrupt=0 inversions=0、`sha_match=true`、源=重组 SHA256 `4F38AF2C…A3BF5` 一致（独立复算 ✓） | `R2_mb10_20261019_155136.log` |
| 写/读计数 | `wr=21/rd=20/drop=0`（含 1 帧 boot 期 ARP/自帧） | 串口 'I' |
| S2MM 状态 | `s2cr=00011003`（RS=1+IOC）、`s2sr=0`（Halted=0、无错误）、`m2sr=00001002`、`m2len=0x56` | 串口 'W' |

## 5. 未完成项（交给 round3d 验收位流 + 完整 S0–S11）

1. **S6/S10 双桥计数对账**：需 ILA3 全量计数（mem/mem2 各自 wm/wr_frm/rd_frm/ost + stall/len_err）——round3c-diag 为省 300MHz 余量已裁掉 mem2/stall/len_err ⇒ 正在构建 **round3d**（ILA3=152b 全量、ILA5=47b、ILA4 跳过）。
2. S9 J3 四链（`j3_fourchains.ps1 --dma`）、S11 收尾、S2/S3/S4 逐步记录需在 round3d 上按 `r2_board.ps1 S0–S11` 全跑一次并归档。
3. 写槽规则/规则号1 逐字等价：S4/S6/S10 计数与槽地址对照（S4 已由四档/10MB 间接覆盖字节级；槽规则证据在 round3d 跑）。
4. 楔死消失的**机制级**解释（BD regen 究竟修了什么）留待 round3d 构建记录对照旧归档日志（未定案，[L1]）。

## 6. 关键文件索引（本轮）

- 构建：`out/r3c3_synth*.log`、`out/r3c3_one*.log`、`out/r3c_regen_bd*.log`、`round3c_build_attempt1/`
- 板验：`R3C_fourtier*.log`、`R2_mb10_20261019_15*.log`、`R3C_evt2_dump.txt`、`R3C_serial_PJK_rehearsal.log.md`、`R3C_cap_*` 彩排日志与 CSV
- 固件源码快照（归档 round3c 目录）：`main_fix1.c`、`main_perf1.c`、`main_evt2.c` 与对应 ELF

## 7. S9 J3 四链（[L2] 板端 PASS，2026-10-19 16:02–16:03）

- 结果（`R3C_j3_fourchains_run2.log`）：**`FOURCHAINS_RESULT: PASS`**
  - M 轮：`wr+=256 rd+=256 inv=32385 miss=0 extra=0 bytediff=0` → PASS
  - A 轮（负向）：`wr+=256 rd+=255 inv=32131 miss=[5100]`（负向缺 1 帧属预期）→ PASS
  - B 轮（重复帧）：`wr+=256 rd+=256 inv=32385 miss=0` → PASS
  - 三轮日志：`R3C_j3_m/a/b_20261019.log`（原件在 `out/evidence_2026-10-17/j3_*_20261019_160236.log`）
- **工具口径修正（R2 适配，已归档补丁版）**：`out/j3_fourchains.ps1` 原前置要求 `wmwr==wmrd` 且"不发 'd'"——这是 R1 口径；R2 桥①读出仅 DMA（硬件读引擎退役）且 u_wr/u_rd 不再 1:1（mode-0/超时丢弃也计入 wr）。
  - 补丁：① 前置改为 `bit25=0 且 wmwr/wmrd 连续两拍不变`（槽表静默）；② 前置自检 `U.mode`，`mode=0` 时发一次 `'d'` 切 DMA（toggle 语义，不重复发）。
  - 变更记录：原版 `tools/j3_fourchains_original.ps1`（`.bak_20261019_r2`），补丁版 `tools/j3_fourchains_r2_patched.ps1`；PS5.1 ParseFile 0 错、BOM EF BB BF。
- 未打补丁时同一干净板卡上 J3 报"前置失败: 槽表不干净(wmwr!=wmrd) ⇒ 判据未取得"（`R3C_j3_fourchains_run1.log`）——属**工具口径**问题，不是数据面故障 [L2：同一板卡/同一固件，补丁后立即全 PASS]。

## 8. 当前未完成项（round3d 验收位流）

1. S0–S5/S6/S10/S11：需 **round3d**（ILA3 恢复 152b 全量）——正在构建；出流后按 `r2_board.ps1 -Run` 全跑（S0 用 `tools/r3d_s0_buildlog_adapter.py` 适配 `V5_SWEEP1_OK` 标记；不改判据脚本）。
2. S6 桥级 ILA、S10 双桥对账（mem/mem2 各自 wm=wr_frm=rd_frm、ost=0、fault=0）与写槽规则/规则号1 逐字等价证据。
3. 旧件"楔死"机制 [L2 强推断]：module-ref IP cache 陈旧（fix1/fix2 从未进位流；BD regen 后新 cache 才真综合当前 RTL）——详见 `audit/R3C_fw_s2mm_reset_review.md` Q3 / 记录 §19.6。

