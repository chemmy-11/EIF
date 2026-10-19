# -*- coding: utf-8 -*-
"""Append §二十 (R2 final acceptance: S0-S11 13/13 PASS) to the R2 record."""
import io
import os

P = r"C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md"

SECTION = r'''
## 二十、R2 收口：round3d 验收位流 + S0–S11 13/13 PASS（2026-10-19 16:2x–16:5x）

> **R2（桥①写侧换 AXI DMA S2MM）关卡收口。** 判据：位流过时序门限；板上 S0–S11 全 PASS；四档 / 10MB+SHA / J3 四链 / 双桥计数对账；写槽规则号1 逐字等价。

### 20.1 验收位流（round3d，PASS）

- 相对 round3c-diag **仅恢复 ILA 探针**：ILA3 63b→**152b 全量**（S6/S10 需要的 mem/mem2 四组计数 + stall/len_err + s2mm state + calib），ILA5 保持 47b（tdata32/tkeep8/tvalid/tready/tlast + probe5 4b，GO/ACK/intr/go_ok），ILA4 跳过；功能 RTL/BD 与 round3c-diag 一致。
- 综合 PASS；`ExtraTimingOpt` 单掷 **WNS=+0.002 / WHS=+0.004**（`V5_SWEEP1_OK`）；DRC **0 Errors / 22 Warnings**。
- 产物（归档 `out/archive/b31b_r2_2026-10-19_round3d/`，39 项 + SHA256.txt）：

| 项 | SHA256（全量） | 大小 |
|---|---|---|
| bit `aurora_mem_bridge_r2_F6012BA0.bit` | `F6012BA0FF8F9D7F3BCD9AC848A97F1C5E1B6DD7016DAD5BEBE93755E73C54C4` | 9,288,496 B |
| ltx `probes_r2_F6012BA0.ltx`（ILA0 13/110b、ILA3 14/152b、ILA5 9/47b） | `2F8AF49895396EBD33D08389EDE1BC2158DBA83D2398B1B8A4AE350B34BAF686` | 82,040 B |
| xsa `mb_ctrl_r2.xsa` | `216839F4B6070621706D635CD9B76A9DAAED43EDADFB4AFC5B7DC66D9BB816F6` | 2,579,584 B |
| ELF `j3_soft_r2_BA3C0220.elf`（验收固件 perf1） | `BA3C02209720B59D…` | 61,296 B |

### 20.2 S0–S11 全量板验（最终 run3：13/13 PASS）

- 命令：`out\r2_board.ps1 -Run -Bit <round3d bit> -Elf <perf1 ELF> -BuildLog <R3D_s0_buildlog_adapter.log> -ExpectBitHash8 F6012BA0 -ExpectElfHash8 BA3C0220 -Xsa <xsa> -ExpectXsaHash8 216839F4 -Port COM5 -IlaCapture -IlaLtx <round3d ltx> -IlaExpectPing 4`
- **`R2_RESULT: PASS`（run3，16:42:45–16:46:35，`R3D_S0-S11_run3.log`）**：S0/S1/S2/S3/S3b/S4/S5/S6/S7/S8/S9/S10/S11 全 PASS。
- 关键判据：
  - **S4/S5**：单帧 ping 1/1、NIC +74B；4 帧 ping 4/4、NIC +296B；WM_WR/WM_RD 同步 +1/+4。
  - **S6（ILA3 152b，双桥差分）**：mem `wm/wr_frm/rd_frm` 各 **+4**、mem `ost`=0；mem2 `rd_frm` **+4**、mem2 `ost` 前后 0。
  - **S7 四档**：`DDR_VERIFY: PASS`（20/20 · 12/12 · 12/12 · 300/300）。
  - **S8 10MB 质量档**：7022/7022、lost=0/corrupt=0、`sha_match=true`、源=重组 SHA256 `4F38AF2C…A3BF5`（独立复算双核对）。
  - **S9 J3 四链**：`FOURCHAINS_RESULT: PASS`（[M] wr+256 rd+256；[A] 负向 wr+256 rd+255 miss=1 属预期；[B] 重复帧 PASS）。
  - **S10 双桥对账（J4 口径，累计值）**：mem `wm=wr_frm=rd_frm=9`、ost=0、stall/len_err=0；mem2 `wm=wr_frm=rd_frm=9`、ost=0；`wr_fault=0` ⇒ `R2_COUNTER_RECON: PASS` + `R2_RECON_RESULT: PASS`。
  - **S11 收尾**：mode=1、engine=1、sticky=0、pending=0、fault=0。
- 三轮记录（完整保留）：run1（16:29–16:33，12 PASS；S10 因工具 marker 缺口 NOT_OBTAINED）/ run2（16:37–16:41，S10 PASS；S9 J3 因板卡起始态残留 `wr+255` NOT_OBTAINED）/ **run3（重烧后 13/13 PASS，最终验收）**。S9 对板卡起始态敏感（J3 纪律：残留态不重试，重烧后复验 PASS）已如实记录。

### 20.3 本轮工具维护（判据逻辑零改动）

1. `out\r2_counter_recon.py`：**recon 模式补打 `R2_RECON_RESULT:` 标记**（delta 模式本来就有；`r2_board.ps1` 只认该标记 ⇒ 真 PASS 曾被误报 NOT_OBTAINED）。旧 `C4AA2C3A…` → 新 `26172AAF…`，备份 `.bak_20261019_recon_marker`。
2. `out\j3_fourchains.ps1`：R2 口径补丁（前置由 `wmwr==wmrd` 改为“bit25=0 且计数两拍不变”；自检 mode=0 时补发一次 'd'，因 R2 桥①读出仅 DMA）。原版备份 + 补丁版归档。
3. `out\r2_ilacap.tcl`：`R2CAP_EXPECT_PROBES` 5→9（补 `dbg_wd_go_ui/ack_ui/intr_ui/go_ok`；不加 dbg_l_bus）。
4. `out\r2_board.ps1` 与其它判据脚本**未改动**；S0 的 `V5_SWEEP1_OK` 识别通过 `tools\r3d_s0_buildlog_adapter.py` 适配（真实值搬运，adapter selfcheck 7/7 PASS）。

### 20.4 两个根因（本轮定案）

1. **旧位流“读回冻结/UART 静默”楔死 = module-ref IP cache 陈旧** `[L2 强推断]`：lite_regs 的 fix1/fix2（10-18）从未进入任何位流（round2f/round3/round3b 均读 `_9` 旧 cache，mtime=10-17 22:22）；BD 全量 regen 后新实例 `_10`/新 cache 才真综合当前 RTL ⇒ 楔死消失、首次出现 commit。**新坑 AGENTS #68**。
2. **50% 隔帧丢 = 固件读服务 `MM2S_DMACR.Reset` 连带复位整个 AXI DMA** `[L3]`：S2MM 被置 Halted(RS=0) ⇒ 下一帧写 `S2MM_LENGTH` no effect ⇒ 无 introut ⇒ 桥 WAITDONE 超时 WD_HALT → 固件 fault 恢复 → 隔帧循环。官方 PG021 原文直证（“either Reset resets the entire AXI DMA engine”；Halted=1 时 LENGTH 写无效），本工程落点 = Vivado 2023.1 / axi_dma 7.1 / xcku060。**修复 = `s2mm_rearm()`（RS+IOC → 等 Halted 落 → W1C 清 IOC；不碰 `g_wr_last_toggle`），零 RTL 改动**；修复后 50%→100%。

### 20.5 证据与文档

- 构建日志：`out\r3d_synth.log`、`out\r3d_one.log`（`V5_SWEEP1_OK`）；S0 adapter `...round3d\R3D_s0_buildlog_adapter.log`。
- 板验：`out\evidence_2026-10-19\R3D_S0-S11_run{1,2,3}.log`、`R2_20261019_164245.log`、`R2_ilacap_vivado_20261019_164245.log`、ILA CSV（ui/user pre/post ×3 轮）、`R2_4tier_20261019_164245.log`、`R2_mb10_20261019_164518.log`（+recomposed）、`j3_fourchains_20261019_164540.log` 及 `j3_m/a/b_*.log`、`R3C_evt2_dump.txt`、`R3D_S10_recon_manual.*`、`R3C_board_session_20261019.md`、`EVIDENCE_INDEX_r3c.md`、`tools\r3c_pin.md`。
- 审计：`audit\R3C_fw_s2mm_reset_review.md`（Q1–Q3 复核）、`audit\R3C_wedge_hypotheses.md` §F。
- 固件源码快照：归档 round3c 目录 `main_perf1.c`（+ fix1/evt2 版本）；`sw\src_j3\main.c` 为当前源码。

### 20.6 遗留（不影响 R2 收口）

1. **ILA5 GO/ACK 触发抓取**未取得（诊断期仪器；数据面已由四档/10MB+SHA/J3 全证；按需再抓）。
2. S9 J3 对板卡起始态敏感（残留 backlog 时 `wr+255`）——已定纪律：重烧后再跑，不重试。
3. 楔死机制从 `[L2 强推断]` 升 `[L3]` 建议：离线重放旧 cache 网表做 lite 总线 TB（不动板卡），或后续补 ILA4。
'''

path = P
cur = io.open(path, "r", encoding="utf-8", newline="").read()
new = cur.rstrip("\n") + "\n" + SECTION
tmp = path + ".tmp_append20"
io.open(tmp, "w", encoding="utf-8", newline="").write(new)
assert os.path.getsize(tmp) > os.path.getsize(path)
os.replace(tmp, path)
print("APPENDED20 bytes_new=", os.path.getsize(path))
