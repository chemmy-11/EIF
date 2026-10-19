# R3C 固件实验原始串口记录（2026-10-19，round3b 位流 02F7153A 上复演）

> 本文件是**会话内实测串口/日志原文的转录**（不是事后重跑；原始工具调用输出见会话记录）。
> 等级：所有结论行标 [L1]/[L2]；本文件只提供原始证据，归因见 audit/R3C_wedge_hypotheses.md。

## 0. 环境与工件

| 项 | 值 |
|---|---|
| 位流（A/B 实验均用） | `out/archive/b31b_r2_2026-10-19_round3b/aurora_mem_bridge_r2_02F7153A.bit`（SHA256 前 8 `02F7153A`） |
| 位流（round2f 对照） | `out/archive/b31b_r2_2026-10-18_round2f/aurora_mem_bridge_r2_8A8FE378.bit`（`8A8FE378`） |
| 诊断固件 F5E0F1F3 | `out/archive/b31b_r2_2026-10-19_round3c/j3_soft_r2_F5E0F1F3.elf`（g_step + WA 快照 + GO-first 服务） |
| 实验固件 P/G/C + J/K | `out/archive/b31b_r2_2026-10-19_round3c/j3_soft_r2_7DAEA8C4_pgc.elf`、`j3_soft_r2_DB88C9D0_jk.elf`（源码 `main_pgc.c` / `main_jk.c`） |
| round2f 原配固件 | `out/archive/b31b_r2_2026-10-18_round3/j3_soft_r2_b614a2dc.elf`（f8cf4022 + GO 后 1ms） |
| 烧录 | `xsct jb31b_burn_pair.tcl <bit> <elf>` → `PAIR_BURNED`（每次断电/重配后重烧） |
| 串口 | COM5 9600 N2? = 8N1；工具 `out/uart_probe.py --cmd <c> --wait <s> --drain 0.1 --raw` |
| JTAG/LMB | `out/evidence_2026-10-19/tools/r3c_diag.tcl`（mb-nm 符号校验 mismatch=0） |
| ILA 复演 | `out/evidence_2026-10-19/tools/r3c_cap.tcl`，round3b ltx（3 核） |

## 1. 复现：round3b + F5E0F1F3，ping 后串口全静默（[L2]）

序列（12:39–12:43）：烧 pair → 'U' → 'd' → 'W' → `ping -n 1 -w 900 192.168.1.10`（0/1 超时）→ 2s 后 'W'/'U'。

```
U: [B2] U id: 50314231 50314231 50314231 50314231 50314231 50314231
   [B2] U mode=0
d: [B2] DMAMODE now=DMA
W: [B2] W s2cr=00011003 s2sr=00000000 s2len=00000000 m2sr=00000001 m2len=00000000
   [B2] W wreq=01000048 wdbg=00000000 dreq=01000000
PING: Sent=1 Received=0 Lost=1 (100%)
W-post: （无输出）  U-post: （无输出）
```

## 2. 楔死后 JTAG/LMB 现场（r3c_diag.tcl，[L2]）

F5E0F1F3 共 **3 次独立复现**（12:39 / 12:44 / 12:52），读数一致：
`G_STEP=0000000b` · `GDMA_MODE=00000001` · `WA_CNT=00000001` · `WA_DONE=00000000`
`WA_S2CR=WA_S2SR=WA_S2LEN=WA_WREQ=WA_WDBG=0x80010056`（5 个不同变量同值；同址 3 读 stable=1）
`PC_RUNNING=0x730 / PC_STOPPED=0x738`（反汇编：0x72c–0x73c 为 `uputc` 的 UART_ST TX_FULL 轮询；0x734=lwi, 0x738=andi）

LMB 区域 dump（0x44F0–0x4544）确认 5 个变量真为 0x80010056、相邻变量正常（非 JTAG 伪影）。

关键含义 [L2]：5 次 *不同地址* 读（含 M02 DMA 0x44A10058/34/30 与 M01 lite 0x44A00040/44）全部返回 **GO 前最后一次读到的 WRREQ 值**（`0x80010056` = pending=1,slot=1,len=86,toggle=0）⇒ **MB DP 读回数据冻结/回放**，跨两个从机、非 lite_regs 单点。

## 3. 固件单变量实验（P/G/C：无真实帧请求，[L1] 转录）

新固件（7DAEA8C4）命令 'P'：写 DMA SA → 写 DMA DMASR(IOC) → 写 LENGTH(启动 S2MM，但无流数据) → 每步后读 R_ID。

```
[P] id0=01000048        ← 首读 stale（lag-1/2；前一条事务为 W 命令的 wreq 读）
[P] id_wSA=50314231     ← 正确
[P] id_wIOC=50314231    ← 正确
[P] id_wLEN=50314231    ← 正确
[P] id2=50314231        ← 正确
[P] s2sr=00000000
[P] s2len=00000056      ← 正确（LENGTH=86 回读 0x56）
[P] wreq=50314231       ← stale（上一读值）
[P] id3=01000048        ← stale（更旧值）
[P] done                ← 未楔死，之后 U/W 正常
```
'G'（只写 R_WRGO 再读）/ 'C'（只写 R_WRACK 再读）同样**不楔死**，读值 lag-1 后自纠。

## 4. 固件单变量实验（J/K：模仿服务写序，[L1] 转录）

'J'（M02 写 DMASR/SA → 读 WRREQ → M02 写 LENGTH → **紧接 M01 写 GO** → busy20ms → 读）：
```
[J] id0=01000048
[J] wreq=50314231
[J] id_after=50314231   ← 正确（LENGTH+GO 写后）
[J] id2=50314231        ← 正确
[J] wreq2=50314231
[J] s2sr=00000000
[J] s2len=00000056      ← 正确
[J] id3=01000048
[J] done                ← 未楔死
```
=⇒ **无真实帧请求时，LENGTH→GO 跨从机写序不触发读冻结/楔死** [L1]。

## 5. 帧到达但不服务（mode=0，[L1] 转录）

'U','d'(切回 bridge), `ping 1`（0/1），2s 后 'U'/'W'：**读路完全正常**。
`W: s2cr=00011003 s2sr=0 s2len=00000056 m2sr=1 m2len=0 wreq=00010056 wdbg=00010000 dreq=0`
（wreq pending=0/len=86/slot=1 = ping 帧请求保留字段，桥 WAITGO 超时后 DRAIN ⇒ 帧到达本身不伤读路。）

## 6. ILA 复演（round3b ltx，3 核，[L2]）

配置：`R2_STIM_CMD='ping -n 1 -w 900 192.168.1.10'`；ILA5 触发 `dbg_s2mm_tvalid=eq1'b1`（单 bit）；ILA4 默认触发（本轮无 ILA4 核 → SKIPPED）；PRE 快照 3 核 + POST（ILA3/ILA0 trigger_now 快照）。

- ILA5：armed 12:43:40，`wait_on_hw_ila -timeout 1` 期满 12:44:41，**NO_TRIGGER**（"stopped by user / No data to upload"）⇒ ping 后 60s 内 **S2MM 写流从未启动**（tvalid 未出现）。
- ILA3 post 快照（12:44:41）：`dbg_mem_wm=wr_frm=rd_frm=0`、`s2mm_state=IDLE(0)`、`tvalid=0`、`tready=1` ⇒ 桥写引擎已回 IDLE（请求超时 DRAIN），零 commit。
- ILA0 pre/post：`dbg_mem_u_wr` 1→2（ping 帧已进桥写口），`u_rd=0`、`reqpend=0`、`fault=0`。
- 随后 diag：`G_STEP=11, WA_CNT=1, WA_*=0x80010056, PC=0x738`（与 §2 同态）。

## 7. round2f 同位流 A/B（[L1]，单次）

| 位流 | 固件 | 序列 | 结果 |
|---|---|---|---|
| round3b 02F7153A | F5E0F1F3（诊断） | U,d,W,ping1 | UART 全静默；g_step=11；WA_*=冻结值 |
| round3b 02F7153A | DB88C9D0（诊断+P/G/J/K） | U,d,W,ping1 | UART 全静默（同） |
| **round2f 8A8FE378** | **b614a2dc（round2f 原配）** | U,d,ping1 | **UART 全静默（同）** |
| round2f 8A8FE378 | DB88C9D0（诊断+J/K） | U,d,W,ping1 | UART 全静默（同） |

⇒ 该输出现象在 fix1/fix2 位流 × 两代固件上均可复现；**“fix2 回归”无证据**。与 10-18 round2f 记录（wm=5、UART 存活）差异的变量仍未定位（待 round3c ILA5 probe5 判 GO 链）。

## 8. 待补/未取得

1. round3c 位流（ILA4@100M + ILA5 probe5）板验：GO 是否到桥 ui、桥是否进 STREAM、introut 是否粘滞（见 audit §E.3 触发 spec）。
2. 'K' 顺序对照（GO 先 LENGTH 后）未跑；无打印/环形日志固件版本待建。
3. round2f 历史 wm=5 与本次复演差异（环境/PC 侧/流程变量）待定位；本次仅单次未做重复计数。
