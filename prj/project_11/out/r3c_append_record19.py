# -*- coding: utf-8 -*-
"""Atomic append §十九 (R2 数据面首次全通 + 50% 丢帧根因修复) to the R2 record."""
import io
import os

P = r"C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md"

SECTION = r'''
## 十九、round3c-diag 位流：楔死消失 + R2 数据面首次全通（2026-10-19 15:2x–16:0x）

> 里程碑：**R2 写/读数据面首次全部打通** —— 四档、10MB+SHA 在板上 PASS。根因修复为**固件级**（不改 RTL/位流）。

### 19.1 构建（round3c-diag，PASS）

- **BD 全量 regen**（`create_bd_b.tcl` 增 BD 端口 `dbg_l_bus`，`out/r3c_regen_bd.log`）后重建；attempt1（4 核 ILA）`ExtraTimingOpt` 后路 **WNS=-0.029** 被门限拒（日志已存档 `out/evidence_2026-10-19/round3c_build_attempt1/`）⇒ 改 **round3c-diag**：`R3C_SKIP_ILA4=1`（跳过 ILA4）+ `R3C_LITE_ILA`（ILA3 裁 63b、ILA5 裁 47b）以保 300MHz 余量。
- 综合 PASS；实现 **`ExtraTimingOpt` 单掷 WNS=+0.004 / WHS=+0.004**（`V5_SWEEP1_OK`）。
- 产物（归档 `out/archive/b31b_r2_2026-10-19_round3c/`，52 项 + SHA256.txt）：bit **`9852016C`**（10,010,456 B）/ ltx **`DE94D05F`**（61,674 B，3 核：ILA0 110b / ILA3 63b / ILA5 47b）/ xsa **`BEB97199`**。

### 19.2 楔死消失（[L2] 现象级 A/B）

同诊断固件、同序列（`'U'→'d'→'W'→ping 1`）在 round3b `02F7153A` 上必现"串口全静默 + LMB 读回冻结 0x80010056"；在 round3c-diag `9852016C` 上**不再复现**，串口持续可用、ILA3 出现 `wm=wr_frm=rd_frm` 真实 commit。两者功能 RTL 等价（仅新增纯观测 dbg_o/BD 端口/GO 链 mark_debug），差异 = **BD 全量 regen + OOC 重建**。
⇒ 旧位流的楔死与 BD 工程/模块引用旧状态有关（机制级未逐级定案，`[L1]`；无证据支持"lite fix2 回归"）。**round3b/round2f 上的"读回冻结/楔死"判据全部作废，以 round3c 起位流为准。**

### 19.3 50% 丢帧根因与修复（[L3] 板端机制直证 + [L2] 官方文档）

- 现象：round3c-diag 上 ping 恰好隔帧回复（20→10），桥 commit 隔帧（`last_alloc_slot` 每次 +2）。
- 事件环固件（`g_evt[512]`，'X' 命令 LMB 打印；`out/evidence_2026-10-19/R3C_evt2_dump.txt`）逐帧证据：
  - 成功帧 `0x16` 快照 `s2sr=0x1002`（Idle+IOC）；
  - 失败帧 `0x16` 快照 `s2sr=0x0001`（**Halted**、无 error）→ 桥 WAITDONE 超时 → `wr_fault=1` WD_HALT → 固件 fault 分支 `s2mm_channel_init()` 恢复 → 下一帧又成功。
- **根因**：`serve_dma_once()`（读服务）每帧写 `DMA_DMACR = 0x4`（MM2S 软复位）；PG021 明示 “Setting either MM2S_DMACR.Reset = 1 or S2MM_DMACR.Reset = 1 **resets the entire AXI DMA engine**” ⇒ S2MM 被连带复位为 Halted；而 Halted=1 时写 `S2MM_LENGTH` “has no effect” ⇒ 下一帧写传输不启动。
  - 官方：https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_DMACR-S2MM-DMA-Control-Register-Offset-30h ；本工程落点 Vivado 2023.1 / axi_dma 7.1 / xcku060。
- **修复（固件，零 RTL）**：新增 `s2mm_rearm()`（`S2MM_DMACR=IOC_IrqEn|RS` → 等 Halted 落 → `S2MM_DMASR=IOC` W1C；不动 `g_wr_last_toggle`），在读服务末尾与每次写编程前调用；并把诊断期 `busy_ms(20)+5 读` 恢复为 `busy_ms(1)`、空闲环去掉 `busy_ms(10)`（恢复全速服务，S8 1000fps 所需）。
  - 固件 hash：`69D61B9B`（诊断读版）/ **`BA3C0220`（验收 perf1，当前板上）**，源码快照 `main_fix1.c`/`main_perf1.c` 已归档。

### 19.4 修复后判据（[L2]，本场板端实测）

| 判据 | 结果 | 证据 |
|---|---|---|
| ping（DMA 模式） | **20/20，0% loss**，RTT 0–1ms，NIC Rx delta=1480B（74×20） | 串口/`Get-NetAdapterStatistics` |
| S7 四档 `udp_verify_ddr.py` | **DDR_VERIFY: PASS**（20/20 · 12/12 · 12/12 · 300/300，100%、0 超时 0 损坏） | `out/evidence_2026-10-19/R3C_fourtier_perf1.log` |
| S8 10MB+SHA `r2_mb10_sha.ps1 -Run` | **R2_MB10_RESULT: PASS**：7022/7022、lost=0/corrupt=0、SHA256 源=重组一致（独立复算 ✓） | `R2_mb10_20261019_155136.log` |
| 计数/状态 | `'I' wr=21 rd=20 drop=0`；`'W' s2cr=00011003 s2sr=0 m2sr=00001002 m2len=0x56` | 串口 |

### 19.5 未完成（下一步）

1. **round3d 验收位流**（ILA3 恢复 152b 全量 = S6/S10 需要的 mem/mem2 计数 + stall/len_err；ILA5 保持 47b；ILA4 跳过）→ 出流归档。
2. 在 round3d 上跑完整 `r2_board.ps1 -Run`：S0–S11（含 S6 桥级 ILA、S10 双桥对账 wm=wr_frm=rd_frm/ost=0/fault=0、S9 J3 四链、S11 收尾），写槽规则号1 逐字等价对照。
3. 证据归档/记录回填/AGENTS §十 更新/docs 镜像/CI PASS/提交（提交前缀 `project_11:`）。
'''

path = P
cur = io.open(path, "r", encoding="utf-8", newline="").read()
new = cur.rstrip("\n") + "\n" + SECTION
tmp = path + ".tmp_append19"
io.open(tmp, "w", encoding="utf-8", newline="").write(new)
assert os.path.getsize(tmp) > os.path.getsize(path), "append shrink guard"
os.replace(tmp, path)
print("APPENDED bytes_old=%d bytes_new=%d" % (os.path.getsize(path) - len(SECTION.encode("utf-8")), os.path.getsize(path)))
