# R2 板验 S4（86B 尾拍 22 lane）判读卡 + DMASR 位表（待命用）

> 用途：Lead 跑 S0–S11 时，rtl-auditor 侧的证据准备（判读口径/三分类），**不是结论**。
> 依据：R2 冻结 RTL `f43267db…`（§13）、独立 TB `r2_wr_tb`（T2 len=70 尾拍 6 lane PASS；T8 16 个边界长度含 1537/1538 PASS）、厂商 PG021/axi_dma 元数据（A8/A9，[L1]）。
> 板验产物：bit `28921C6B…` / ltx `4AC25546…` / ELF `1bc8088d`；UART **9600**（Lead 已纠正）。

---

## 1. S4 期望值（ping 回显帧 86B）

| 项 | 期望 | 说明 |
|---|---|---|
| `len_tab[slot]` | **86** | 8B 前导+SFD + 完整 ETH/IP/UDP|ICMP 帧（含 4B FCS）= 86B；与 R1 口径一致 |
| S2MM LENGTH（软核编程） | **86** | 软核 `S2MM_LENGTH = len`（写即启动） |
| S2MM SA | `0x00100000 + slot*4096` | 规则号 1 |
| AXIS 拍数 | **2** 拍 | beat0=64B 全 lane；beat1=**22 lane** |
| beat0 TKEEP | `0xFFFF_FFFF_FFFF_FFFF` | 64 个 1 |
| beat1 TKEEP | **`0x003F_FFFF`**（bit21:0=1，bit63:22=0） | 86-64=22 |
| TLAST | beat1=1、beat0=0 | 帧边界 |
| 槽内字节 | PC 侧按帧内容逐字节一致（S4 判据） | ping 载荷已知 |
| 槽内 86..127 字节 | **不得被写**（保持原值/0） | 尾拍外不得写（TB 同判据 `FAIL-TAIL-WRITE`） |
| `dbg_wr_fault` | **0** | 全程硬判 |
| `dbg_s2mm_state` | IDLE→WAITGO→**ARM(7,1 拍)**→STREAM→PUSH→WAITDONE→IDLE | 7=瞬态正常；**6=HALT 才是 fail-stop** |
| `dbg_s2mm_tvalid/tready` | S4 期应见 2 拍握手（连续或间隔均可） | 结合 state 判"写流在跑" |

---

## 2. S2MM DMASR 位表（'U' s2sr 行；PG021 direct-register，[L1 厂商文档]）

> 'U' 里 `s2sr:` 打印 2 个值（`s2 s1`，双读后取第二个更可靠）；判读用最新一笔 `s1`（=最后读）。

| bit | 名称 | 期望 | 判读 |
|---|---|---|---|
| 0 | Halted | 0（已 arm/运行）；空闲未 arm 时可 1 | 1 且一直 1 ⇒ 通道未启动（软核 arm 失败/GO 未翻） |
| 1 | Idle | 传输完成后 1；流式中可为 0 | 完成+清 IOC 后应回到 1 |
| 4 | DMAIntErr | **0** | 内部错误 ⇒ 记 FAIL（IP/数据面） |
| 5 | DMASlvErr | **0** | AXI 从机错误（MIG/地址非法）⇒ FAIL |
| 6 | DMADecErr | **0** | 译码错误 ⇒ FAIL |
| 9 | DMAInterErr | **0** | 中断/内部错误 ⇒ 记 INFO→FAIL 需复核 |
| 12 | IOC_Irq | 完成时 1（软核 W1C 清） | 抓取时机决定；1=已完成 |
| 14 | Err_Irq | **0** | 任何错误汇总位 |

**判读规则**：只要 4/5/6/9/14 任一为 1 ⇒ S4 记 FAIL（先归类"厂商 IP/数据面"侧）；bit0/1 需结合 arm 时刻解释。

---

## 3. S4 失败时的三分类矩阵（证据优先，不猜）

| 分类 | 观测签名（按优先级取） | 下一步 |
|---|---|---|
| **RTL 侧** | `dbg_s2mm_state==6(HALT)` 且 `dbg_wr_fault=1`；`WM_WR` 不增；`wreq.pending` 卡 1 或反复；ILA3 停在 WAITGO/STREAM，tvalid 发但 tready 长低 | 查 `stat_wr_timeout`（不可观测）→ 用 HALT/fault+state 链；对照 §13 TB（T6/T9 覆盖的两条超时路径） |
| **厂商 IP 侧** | state 流完到 WAITDONE 但 `s2mm_introut` 迟到/不来 ⇒ 超时 HALT；或 DMASR 4/5/6/14；尾 22 lane 字节错且前 64B 正确（A9 TKEEP→WSTRB 形态差异） | 记录 DMASR + 尾拍字节 diff 形态；必要时 ILA 抓 AXIS（tkept/tlast）与槽读回对比；按 A9 [L1] 研判 |
| **判据脚本/操作侧** | 字节"错"但槽内容其实是 PC 期望的移位（86 vs 70/80 口径）；UART 波特率/命令时序；bresp 项被当 FAIL（已裁不可观测）；ARP 老化 | 先核口令/口径：9600、`'U'` 三行、`wmwr` 基线、S2/S3 identity；不用旧 115200 日志 |

**必备取证（S4 FAIL 时请一并留）**：① `'U'` 的 `wreq/wdbg/s2sr` 三行原始文本；② `'I'` 行（wr/rd/drop）；③ ILA3 S4 快照 CSV（state/tvalid/tready + mem wm/wr_frm/rd_frm/ost/stall/len_err）；④ NIC 侧字节 diff（首差偏移）；⑤ 同帧重测一次判定可复现性。

---

## 4. 关联已知判据口径（避免误判）
1. `dbg_mem_bresp` 本轮已裁 ⇒ S10 的 bresp 项为 **INFO/NOT_OBTAINED**，不得据此判 FAIL（A18）。
2. `stat_wr_timeout` 板上不可观测（A17）⇒ 只能以 `fault`+`state==6`+`WM_WR` 停滞推断；**不得写"timeout=0"**。
3. WAITGO 超时（GO 缺失）是良性丢帧：state 停在 1 然后 5(DRAIN)→0，**不出现 6/fault=1**。
4. `WR_DBG.last_alloc_slot`=最近**分配**槽、`last_commit_len`=最近**提交**帧长（A12），解读勿混。
5. `dbg_mem_rden` 在 ILA0 probe0 CSV 名可能为 **`dbg_mem_rden_1`**（Vivado 重命名，§5.1）。
6. ILA ltx 无时钟网名：ILA0@user/ILA3@ui 关联靠 build 脚本+RTL 域（已核）；板端可用 hw_manager 确认一次。

---
*本卡由 rtl-auditor 在板验期间准备；S4/S5/S10 原始日志到位后按上表三分类出证据链，结论以 Lead 复核为准。*
