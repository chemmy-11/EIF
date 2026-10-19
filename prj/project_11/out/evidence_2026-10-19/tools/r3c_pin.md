# R2 round3c/round3d 板验工具链 · 产物身份（S0 钉 hash）+ `r2_board.ps1` 运行模板

> **状态（2026-10-19 16:3x）**：
> - **round3c-diag 位流 `9852016C` 已在板上跑通数据面**（ping 20/20、S7 四档 PASS、S8 10MB 100%+SHA PASS；根因=固件 MM2S 复位连带复位 S2MM，已固件级修复）。身份表见 §1；会话记录 `out/evidence_2026-10-19/R3C_board_session_20261019.md`。
> - **round3d 验收位流已出流并归档（16:2x，构建 PASS：`V5_SWEEP1_OK wns=0.002 whs=0.004` + DRC 0E/22W）**，身份表见 §2。**S0–S11 已跑三轮**：run1（16:29–16:33）= 12 PASS + S10 wrapper 缺口；run2（工具补丁后，16:37–16:41）= S10 PASS 但 S9 NOT_OBTAINED（J3 flake）；**run3（重烧后，16:42–16:46）= 13/13 全 PASS（`R2_RESULT: PASS`）** —— 最终验收口径见 §2.4。
> - 交付者：Agent Team 成员 `script-tools`（离线侧）；**烧录/串口/JTAG/ILA 由 Lead 执行**。工具链：`r3c_cap.tcl` / `r3c_diag.tcl` / `r3c_seq.ps1` / `r3c_ila_analyze.py` / `r3d_s0_buildlog_adapter.py`（同目录）。

**纪律**：判据只认**归档绝对路径 + 实算 SHA256**（坑 #15/R15）；S0 只做离线校验，不碰板。

---

## 1. round3c-diag（已通过，3 核）身份表

归档目录：`D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\`

| 产物 | 文件（归档内） | 大小 | SHA256 前 8 | 全量 SHA256 |
|---|---|---|---|---|
| 位流 | `aurora_mem_bridge_r2_9852016C.bit` | 10,010,456 B | **`9852016C`** | `9852016C6C06D323342C34E06EA5AA03E462A13A37FA02071B610A0CAB57DE8B` |
| 探针 LTX（3 核） | `probes_r2_9852016C.ltx` | 61,674 B | **`DE94D05F`** | `DE94D05F8AC2ACE483D87D856CD58EBA123430ECB062B404F531A1CC68CCC36C` |
| XSA | `mb_ctrl_r2.xsa` | 2,605,217 B | **`BEB97199`** | `BEB971997AB853616EB74C596C41A323C82E6C63CA5A247B87313F16C50965C` |
| 构建日志（实现） | `build_r3c3_one.log` | 309,855 B | `DDDEC27C` | 含 `V5_SWEEP1_OK: directive=ExtraTimingOpt wns=0.004 whs=0.004 bit=…`；`DRC finished with 0 Errors, 22 Warnings`；`write_bitstream completed successfully` |
| 构建日志（综合） | `build_r3c3_synth.log` | 178,793 B | `AF18EB2E` | 含 `SYNTH_ONLY_DONE` |
| 构建状态 | `BUILD_STATUS.md` | 5,336 B | `739103ED` | 本轮状态/改动集/板验结果 |
| 归档清单 | `SHA256.txt` | 6,410 B | `59C1EBE2` | 由 `out/r2_archive_round3c.py` 生成 |
| 实现报告 | `rpt3_ExtraTimingOpt.*` | — | `FA52BFA8`/`AD7E37E8`/`FBD9D95B` | timing_summary / util / worst |
| RTL 快照 | `rtl_axi_lite_regs.v` | 31,879 B | `FECCEC0F` | dbg_o[35:0] 观测总线 |
| | `rtl_aurora_mem_bridge.v` / `rtl_axi4_master_bridge.v` / `rtl_frame_mem_if.v` | — | `1AB8953A` / `ED8D7F59` / `7D1DE3A6` | 顶层/桥/FMI 快照 |

**本轮固件清单（归档内，全部 3 核位流可用）**

| 用途 | ELF | 大小 | SHA256 前 8 |
|---|---|---|---|
| 诊断基版（g_step + WA 快照） | `j3_soft_r2_F5E0F1F3.elf` | 54,224 B | `F5E0F1F3` |
| 楔死复现/实验命令 P/G/C/J/K | `j3_soft_r2_7DAEA8C4_pgc.elf` / `j3_soft_r2_DB88C9D0_jk.elf` | 56,728 / 59,112 B | `7DAEA8C4` / `DB88C9D0` |
| 事件环（g_evt[512] + 'X'） | `j3_soft_r2_3251406F_evt2.elf`（另 `21E13038_evt`） | 61,292 B | `3251406F` |
| **50% 修复（s2mm_rearm，诊断读 20ms）** | `j3_soft_r2_69D61B9B_fix1.elf` | 61,788 B | **`69D61B9B`** |
| **验收固件（s2mm_rearm + 全速，当前板上验证 S7/S8）** | `j3_soft_r2_BA3C0220_perf1.elf` | 61,296 B | **`BA3C0220`** |
| 固件源码 | `main_fix1.c` / `main_perf1.c` / `main_evt2.c` / `main.c` | — | `34E4399C` / `0C60631E` / `A56DAF13` / `B17D1568` |

> 当前 live `sw\j3_soft\Debug\j3_soft.elf` = perf1（`BA3C0220`，61,296 B，15:50）；`sw\j3_soft\src\main.c` = `main_perf1.c`（`0C60631E`，50,622 B）。
> **S0 注意**：`r2_board.ps1` 内置的 `KnownR2ElfHash8=f8cf4022` 是 round2d 旧值；给 `-ExpectElfHash8 BA3C0220` 时 S0 只打印 WARN（不判 FAIL），可接受。

---

## 2. round3d（验收位流，**已出流并归档 2026-10-19 16:2x**）身份表 + LTX 期望

归档目录：`D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\`
构建结果（Lead 2026-10-19 16:29）：**PASS — `V5_SWEEP1_OK: directive=ExtraTimingOpt wns=0.002 whs=0.004`**（单掷）；`DRC finished with 0 Errors, 22 Warnings`；`write_bitstream completed successfully`。

| 产物 | 归档文件名 | 大小 | SHA256（全量） | sha8 | 状态 |
|---|---|---|---|---|---|
| 位流 | `aurora_mem_bridge_r2_F6012BA0.bit` | **9,288,496 B** | `F6012BA0FF8F9D7F3BCD9AC848A97F1C5E1B6DD7016DAD5BEBE93755E73C54C4` | **`F6012BA0`** | ✅ 已归档 |
| 探针 LTX（3 核） | `probes_r2_F6012BA0.ltx` | **82,040 B** | `2F8AF49895396EBD33D08389EDE1BC2158DBA83D2398B1B8A4AE350B34BAF686` | **`2F8AF498`** | ✅ 已归档；LTX 解析实测 ILA0 110b/13、ILA3 152b/14、ILA5 47b/9（ILA4 跳过） |
| XSA | `mb_ctrl_r2.xsa` | **2,579,584 B** | `216839F4B6070621706D635CD9B76A9DAAED43EDADFB4AFC5B7DC66D9BB816F6` | **`216839F4`** | ✅ 已归档 |
| ELF（验收固件） | `j3_soft_r2_BA3C0220.elf`（= perf1，归档名无 `_perf1` 后缀） | 61,296 B | `BA3C02209720B59D9F0FBC4083C2AB80B16EFC9A148448B9DCFBCDA001BB3559` | `BA3C0220` | ✅ 已归档 |
| 构建日志（实现） | `build_r3d_one.log`（= `out/r3d_one.log` 归档） | 319,534 B | `4EB258C575204B661A83A084C73F9BE75554F800DDF101FD2F7D1BA5B4F5208B` | `4EB258C5` | ✅ 含 `SWEEP1_ExtraTimingOpt: WNS=0.002 WHS=0.004` / `V5_SWEEP1_OK` / DRC 0E/22W / `write_bitstream completed successfully` |
| 构建日志（综合） | `build_r3d_synth.log` | 178,672 B | `A0E0BCC4CB6644464973B7B2741275B8563322724F58922B58FDD476081C6D12` | `A0E0BCC4` | ✅ 含 `SYNTH_ONLY_DONE`；`R3C_LITE_ILA: 0 / R3C_LITE_ILA5: 1`、`ILA5_PROBES: tdata64=32 … probe5=4`、`ILA4_SKIPPED` |
| S0 适配日志 | `R3D_s0_buildlog_adapter.log` | 959 B | `7E705B7C378439B0503F9450ED2ADA13A7E1B83B1EA1A51F576E7CB21DD5E3F6` | `7E705B7C` | ✅ `S0_ADAPTER_RESULT: PASS`（7/7 selfcheck）；注意其 `bit=` 行写的是 `out/aurora_mem_bridge.bit`（生成时 `--bit` 指向 out 默认名）⇒ S0 对 `-Bit` 归档名只打**文件名 WARN**（不是 FAIL），hash 仍按 `-Bit` 实算硬判 |
| 归档清单 | `SHA256.txt` | 4,711 B | `4901579B0B50CBDC9FBC7703902AB7933CD6FFFFA4ECDC4647ADE0FC7587D211` | `4901579B` | ✅ 47 行（含头注释）；Lead 称 39 项 |
| 实现/综合报告 | `rpt3_ExtraTimingOpt.*` | — | `803AE6D6`/`BF4C4896`/`DAA10741` | — | ✅ timing_summary / util / worst |
| RTL 快照 | `rtl_*.v`（lite/bridge/top/fmi） | — | `FECCEC0F`/`ED8D7F59`/`1AB8953A`/`7D1DE3A6` | — | ✅ 与 round3c-diag 相同（功能 RTL 未变） |
| 归档 evidence 子目录 | `evidence/`（session md、evt2 dump、fourtier、j3 run2 日志） | — | — | — | ✅ 见 `EVIDENCE_INDEX_r3c.md` |

> 本轮 S0–S11 运行日志：`D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3D_S0-S11_run1.log`（16:29:14–16:33:06，已完成；结果见 §2.2）。

### 2.2 本轮 S0–S11 实测结果（2026-10-19 16:29:14–16:33:06）

**12 步 PASS；S10 判据本体 PASS（等价取证）但 wrapper 记 NOT_OBTAINED** —— `R2_RESULT: NOT_OBTAINED S10`。

| 步 | 判定 | 关键行 |
|---|---|---|
| S0 | PASS | `[JUDGE] S0 PASS: WNS=0.002 WHS=0.004 DRC=0; bit8=f6012ba0 elf8=ba3c0220 okMarker=有`（**方案 B adapter 生效**） |
| S1/S2/S3/S3b | PASS | 在位记录 / 未发 'd' 身份 / `'d'` 后 engine=1 / pending&fault 静默窗 |
| S4/S5 | PASS | 单帧（ping1/1、NIC+74B、WM±1）/ ping4/4、NIC+296B、WM+4 |
| **S6** | **PASS** | `mem wm/wr_frm/rd_frm 各 +4, mem ost=0; mem2 rd_frm +4, mem2 ost 前后 0` ⇒ ILA3 152b 恢复 + 双桥差分闭合 |
| S7/S8 | PASS | 四档 `DDR_VERIFY: PASS`（20/20·12/12·12/12·300/300）/ 10MB 7022/7022、lost=0、sha_match=true |
| S9 | PASS | J3 fourchains `--dma` M/A/B 全 PASS |
| **S10** | **run1：NOT_OBTAINED（wrapper 缺口，历史）** / **run2：PASS（工具补丁后）** | run1：recon 本体 `R2_COUNTER_RECON: PASS` 但 wrapper 缺 `R2_RECON_RESULT:` → NOT_OBTAINED；run2（补丁后）L846-847 `R2_COUNTER_RECON: PASS` + `R2_RECON_RESULT: PASS` → L1322 `[JUDGE] S10 PASS`。详见 §2.3。 |
| S11 | PASS | 收尾引擎确认 mode=1 & req.bit24=1 |

> 证据落点：`out/evidence_2026-10-19/{R3D_S0-S11_run1.log, R2_20261019_162914.log, R2_ilacap_vivado_20261019_162914.log, R2_ila_r2_20261019_162914_{ui,user}_{pre,post}.csv, R2_4tier_20261019_162914.log, R2_mb10_20261019_163149.log, R3D_S10_recon_manual.log/.json}`；归档 S0 适配日志 `round3d\R3D_s0_buildlog_adapter.log`。S6 抓取 CSV 为 **round3d 152b ILA3 / 110b ILA0**（`R2_ila_*_ui_post.csv` 68,835 B、14 probes；user 116,919 B、13 probes）。

### 2.3 run2（工具补丁后重跑，2026-10-19 16:37–16:41）

日志：`D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3D_S0-S11_run2.log`（70,856 B / sha256 `B9018AE0D2EBC083624357618294A5B02F826ABF14E3A1C8DA5C2624FFA83335` / sha8 `B9018AE0`；16:37:14–16:41:24）。

**结果：S10 已 PASS（工具补丁生效）；S9 本轮 NOT_OBTAINED（J3 flake，需重烧重跑）** ⇒ `R2_RESULT: NOT_OBTAINED S9`（12 PASS + 1 NOT_OBTAINED，**不是 13/13**）：

| 步 | run2 判定 | 关键行 |
|---|---|---|
| S0–S8 | PASS | 与 run1 同（S6 仍 `mem/mem2 各 +4、ost=0`；S7 四档 PASS；S8 10MB PASS） |
| **S9** | **NOT_OBTAINED** | J3 M 轮 `收帧停摆 @47/256` → `wr+256 rd+47 inv=1081 miss=209`；重试段亦 FAIL（@1/256）；`j3_fourchains_20261019_164008.log`（8,720 B / `D145375E`）+ `j3_m_20261019_164008.log`（2,040 B）；`FOURCHAINS_RESULT: FAIL M (判据未取得; 板卡需重烧)`；现场 `mode=1 engine=0 sticky=1 wmwr=7682 wmrd=7450`（232 帧 backlog） |
| **S10** | **PASS** | L846-847 `R2_COUNTER_RECON: PASS` + `R2_RECON_RESULT: PASS` → L1322 `[JUDGE] S10 PASS`（mem/mem2 wm==wr_frm==rd_frm、ost=0、mem stall/len_err=0、wr_fault=0） |
| S11 | PASS | 收尾引擎确认（但 S9 后板卡残留 sticky=1，建议重烧后再验） |

**S10 工具补丁说明（只加 marker print，判据逻辑零改动）**：
- 文件：`out\r2_counter_recon.py`；**旧** sha256 `C4AA2C3AAFB050F51161D773E468A12F8A58B7C63955FF0F8F3C3C9939AF695D`（45,947 B）→ **新** sha256 `26172AAF507D183F141D924E46C6D98DD7D4F7FB25BCB238DDC6C957672F59F4`（46,313 B）。
- 备份：`out\r2_counter_recon.py.bak_20261019_recon_marker`（45,947 B / `C4AA2C3A…AF695D`，与旧全量一致）。
- diff 仅 2 处：① recon 无 CSV 的 NOT_OBTAINED 分支补 `print("R2_RECON_RESULT: NOT_OBTAINED")`；② 正常分支 `print("R2_COUNTER_RECON: …")` 后补 `print("R2_RECON_RESULT: %s" % v)` + 3 行注释；**无判据逻辑改动**。
- 复验：run2 S10 PASS（见上）；另离线复跑（run2 CSV）`--mode recon` → exit 0 + `R2_RECON_RESULT: PASS`。

**S9 处置建议（按既有 J3 纪律，不自动重试）**：`wr+255/收帧停摆` ⇒ 判据未取得 + **板卡需重烧**；当前板卡残留 `sticky=1`/`wmrd-wmwr` 落后 232 帧，**不得在当前残留态重试 J3**。建议：重烧 round3d pair（`aurora_mem_bridge_r2_F6012BA0.bit` + `j3_soft_r2_BA3C0220.elf`）后重跑（完整 S0–S11，或至少 S2→S11 并保持 `-IlaCapture`；S9 必须在新烧录后跑），S10 可复验 PASS。

### 2.4 run3（重烧后最终验收，2026-10-19 16:42–16:46）——**13/13 全 PASS**

日志：`D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3D_S0-S11_run3.log`（69,821 B / sha256 `EC927EC68F8C121DCED02E4124A2BD6D098F34C89F86BD667E56E576A9A46646` / sha8 `EC927EC6`；16:42:45–16:46:35）。

**结果：`R2_RESULT: PASS`（S0–S11 全 13 步 PASS）** —— 与 Lead 预期一致；run2 的 S9 失败确认为**可重烧恢复的板卡起始态问题**（J3 纪律成立：残留态不重试、重烧后 PASS）。

| 步 | run3 | 关键行 |
|---|---|---|
| S0–S8 | PASS | S0 `WNS=0.002 WHS=0.004 DRC=0; bit8=f6012ba0 elf8=ba3c0220 okMarker=有`；S6 `mem/mem2 各 +4、ost=0`；S7 四档 PASS；S8 10MB PASS |
| **S9** | **PASS** | J3 fourchains `--dma`：`J3_ROUND M/A/B: PASS exit=0`、`FOURCHAINS_RESULT: PASS`（日志 `out/evidence_2026-10-17/j3_fourchains_20261019_164540.log` 9,384 B / `20FCABCC`） |
| **S10** | **PASS** | recon `R2_RECON_RESULT: PASS` → `[JUDGE] S10 PASS`（补丁生效） |
| S11 | PASS | 收尾 `mode=1 req.bit24=1 sticky=0 wmwr=8145 wmrd=8143` |

> 最终验收结论：**round3d（bit `F6012BA0` + ELF `BA3C0220`）S0–S11 全 PASS**；run3 证据另含 `R2_20261019_164245.log`（71,294 B / `49CB7DB2`）、`R2_ilacap_vivado_20261019_164245.log`（6,670 B / `E07E3063`）、ILA CSV 164245（ui 68,835×2 `4B65FEC1`/`4B3F5C0C`；user 116,919×2 `E752B674`/`9A1961ED`）、`R2_4tier_20261019_164245.log`（1,459 B / `9B4175C1`）、`R2_mb10_20261019_164518.log`（4,892 B / `8971CEB3`）；run1/run2 保留为过程证据（S10 wrapper 缺口 → 补丁；S9 J3 flake → 重烧恢复）。

### 2.1 round3d LTX 期望（3 核；来源：`scripts/build_synth_only.tcl` 2026-10-19 15:52 版 + `out/r3d_synth_retry.ps1`）

| ILA | 时钟域 | 深度 | 总位宽 | probe 数（Vivado batch `get_hw_probes` 口径） | 说明 |
|---|---|---|---|---|---|
| ILA0 `u_ila_0` | user_clk | 2048 | **110** | **13** | probe0=101b（+pfwd 9b）+ probe1=9b；同 round3c |
| ILA3 `u_ila_3` | ui_clk | 1024 | **152** | **14** | **恢复全量**：calib + mem wm/wr_frm/rd_frm/stall/len_err/ost + mem2 wm/wr_frm/rd_frm/ost + state/tvalid/tready |
| ILA5 `u_ila_5` | ui_clk | 1024 | **47** | **9** | `R3C_LITE_ILA5=1`：tdata**32** + tkeep8 + tvalid/tready/tlast + probe5 4b（go/ack/intr/go_ok） |
| ILA4 | — | — | — | — | **跳过**（`R3C_SKIP_ILA4=1`，ltx 3 核） |

> ⚠️ 你提到的 “probe 数 13/14/12” 中 ILA5=12 对应**含 state[2:0] 的 82b 全版**；本构建 `R3C_LITE_ILA5=1` 下 ILA5 为 **47b / 9 probes**（round3c-diag LTX `DE94D05F` 实测 9 probes/47b 可作对照）。以出流后 `R3C_PROBE_MAP` / LTX 解析实测为准。
> 核数 = **3**（无 ILA4）。`r3c_cap.tcl` 跑 round3d 时请设 `R3C_EXPECT_ILA_COUNT=3`、`R2C_EXPECT_WIDTH_ILA5=47`（默认 82 会 WARN）、`R2C_EXPECT_WIDTH_ILA3=152`（默认已 152）。

---

## 3. `r2_board.ps1 -Run` 完整命令行（round3d 验收跑 S0–S11）

> **CWD 必须 ASCII**（中文 CWD 下 `implement_debug_core`/子进程会失败）：先 `Set-Location D:\FPGA`。
> 参数名以 `out\r2_board.ps1`（2026-10-18 17:15 版，sha8 `3769F5C2`）实际 `param()` 为准。

### 3.1 主命令（**已用真实 hash 固化；2026-10-19 16:29 Lead 已按此启动 S0–S11**）

```powershell
Set-Location D:\FPGA
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 -Run `
  -Bit      "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\aurora_mem_bridge_r2_F6012BA0.bit" `
  -Elf      "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\j3_soft_r2_BA3C0220.elf" `
  -BuildLog "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\R3D_s0_buildlog_adapter.log" `
  -ExpectBitHash8 F6012BA0 -ExpectElfHash8 BA3C0220 `
  -Xsa      "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\mb_ctrl_r2.xsa" `
  -ExpectXsaHash8 216839F4 `
  -Port COM5 `
  -IlaCapture `
  -IlaLtx   "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\probes_r2_F6012BA0.ltx" `
  -IlaOutDir "D:\FPGA\prj\project_11\out\evidence_2026-10-19" `
  -IlaExpectPing 4
```

> 本轮实际运行日志：`D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3D_S0-S11_run1.log`（16:29:14 启动；16:29:21 `[JUDGE] S0 PASS: WNS=0.002 WHS=0.004 DRC=0; bit8=f6012ba0 elf8=ba3c0220 okMarker=有`；16:29:46 `[JUDGE] S1 PASS`）。

要点：
- **口径已定（Lead 2026-10-19 16:0x）：采用方案 B = §4 适配日志作 `-BuildLog`，`r2_board.ps1` 保持原样不修改**（变更面最小、证据链清楚）。
- `-IlaCapture` ⇒ S6 在 S6 步内自动调 `out\r2_ilacap.tcl`（**不是** `r3c_cap.tcl`）抓 ILA0/ILA3 的 PRE/POST → S6 差分 + S10 复用同一 post CSV；`-IlaExpectPing 4` 须与 S6 刺激 `ping -n 4` 一致（默认即 4）。
- `-BuildLog` = `...\round3d\R3D_s0_buildlog_adapter.log`（§4 方案 B 生成）；**不要**直接给 `out\r3d_one.log`（S0 不认 `V5_SWEEP1_OK/SWEEP1_`）。
- `-ExpectElfHash8 BA3C0220`：S0 会 WARN “≠ 已知 R2 固件（f8cf4022）”——**仅 WARN，不 FAIL**（§1 注）。
- `-Xsa/-ExpectXsaHash8` 可选；给了就硬判。
- 可选增强（首次全绿后建议再加）：`-RequireR2Probes`（S6/S10 探针缺失升硬判；round3d 5 个 R2 探针齐全）、`-StrictS2sr`（Halted=0&errbits=0 硬判）。
- 失败不自动重试；某步 FAIL/NOT_OBTAINED 时脚本打 `R2_RESULT: ...` 并以非 0 退出。

### 3.2 分步/复跑变体

```powershell
# 板已烧好、只补跑板验（S2 身份判据仍要求板在未发 'd' 的出厂态）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 -Run -SkipBurn `
  -Bit <同主命令> -Elf <同主命令> -IlaCapture -IlaLtx <同主命令> -Port COM5
```

### 3.3 替代路径：`r3c_cap.tcl` 抓 ILA + 显式 CSV 喂 S6/S10

```powershell
# 1) 抓（快照或触发；round3d 需 3 核 / ILA5=47b 期望）
$env:R2_LTX='D:\...\b31b_r2_2026-10-19_round3d\probes_r2_<R3D8>.ltx'
$env:R2_OUT_DIR='D:\FPGA\prj\project_11\out\evidence_2026-10-19'
$env:R2_TAG='r3cD'; $env:R3C_EXPECT_ILA_COUNT='3'
$env:R2C_EXPECT_WIDTH_ILA5='47'; $env:R2_SNAPSHOT_ONLY='1'
cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source `"D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_cap.tcl`" -notrace -log D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3C_cap_r3cD_vivado.log > D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3C_cap_r3cD_console.log 2>&1"
# 2) 喂 CSV（r3c_cap 命名；S6 显式 CSV 分支走 recon delta）
... r2_board.ps1 -Run -SkipIla `
  -IlacapUiPre  "...\R3C_r3cD_ILA3_pre.csv"  -IlacapUiPost "...\R3C_r3cD_ILA3_post.csv" `
  -IlacapUserPre "...\R3C_r3cD_ILA0_pre.csv" -IlacapUserPost "...\R3C_r3cD_ILA0_post.csv"
```

> `r2_board.ps1` 的 `-IlaCapture` 路径固定 2 核（ILA0/ILA3），**不会**抓 ILA5；需要 GO/ACK/intr 证据时用 `r3c_cap.tcl` 单独抓（`R2_TRIG_ILA5="dbg_wd_go_ui=eq1'b1"`；注意 probe5 是 4 个独立 1-bit probe，**不能**写 `eq4'b1001` 总线比较——round3c 彩排 `r3cA` 即因此 ARM_FAILED）。

---

## 4. ⚠️ S0 兼容性预警（round3d 用 `V5_SWEEP1_OK`，r2_board.ps1 只认 `V5_SWEEP2_OK`）

`r2_board.ps1` 的 S0 正则（`out\r2_board.ps1` L1037–L1045，**只读核对，未修改该文件**）：
- WNS/WHS：`SWEEP2?_[A-Za-z]+:\s*WNS=...`
- okMarker：`V5_SWEEP2_OK|V5_SWEEP_OK|W5_BUILD_OK|DBG_BUILD_DONE`
- bitInLog：`(?:V5_SWEEP2_OK|V5_SWEEP_OK|DBG_BUILD_DONE)[^\r\n]*bit=(\S+)`
- failMarker：`V5_SWEEP_ALL_FAIL|V5_SWEEP2_ALL_FAIL|W5_BUILD_TIMING_FAIL|NO_BITSTREAM`

round3d（与 round3c 相同的单掷脚本 `out/r3c2_sweep_one.tcl`）成功时打印：`SWEEP1_<d>: WNS=… WHS=…` 与 `V5_SWEEP1_OK: directive=… wns=… whs=… bit=…`。
⇒ **不改 r2_board.ps1 时 S0 必判 FAIL**（WNS/WHS=null、okMarker=False），与位流好坏无关。

### 方案 A（备选，**本轮不采用**；仅为将来若改用双掷脚本 `V5_SWEEP2_OK` 时留档）：给 r2_board.ps1 打 5 处标记正则补丁（只加标记识别，不改阈值/流程）

| 行 | 原片段 | 改为 |
|---|---|---|
| L1037 | `"SWEEP2?_[A-Za-z]+:\s*WNS=(-?\d+…)"` | `"SWEEP[12]?_[A-Za-z]+:\s*WNS=(-?\d+…)"` |
| L1038 | `"SWEEP2?_[A-Za-z]+:\s*WNS=-?\d+…\s+WHS=…"` | 同上加 `[12]?` |
| L1039 | `"V5_SWEEP2_OK\|V5_SWEEP_OK\|W5_BUILD_OK\|DBG_BUILD_DONE"` | 追加 `\|V5_SWEEP1_OK` |
| L1040 | `"V5_SWEEP_ALL_FAIL\|V5_SWEEP2_ALL_FAIL\|…"` | 追加 `\|V5_SWEEP1_ALL_FAIL` |
| L1045 | `"(?:V5_SWEEP2_OK\|V5_SWEEP_OK\|DBG_BUILD_DONE)[^\r\n]*bit=…"` | 追加 `\|V5_SWEEP1_OK` |

> 改后纪律：`.ps1` 必须复验 UTF-8 BOM（前 3 字节 239,187,191）+ `[Parser]::ParseFile` 0 语法错（坑 #18）。

### 方案 B（**本轮采用**，不改 r2_board.ps1）：S0 适配日志（工具已交付并离线验证）

```powershell
$py='C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe'
& $py D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3d_s0_buildlog_adapter.py `
  --sweep-log "D:\FPGA\prj\project_11\out\r3d_one.log" `
  --bit "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\aurora_mem_bridge_r2_<R3D8>.bit" `
  --expect-bit-hash8 <R3D8> `
  --out "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\R3D_s0_buildlog_adapter.log"
```
- 只搬运真实值（wns/whs/directive/bit 从日志解析、DRC/bitstream 行复制），**不造数**；wns/whs<0 或找不到成功标记 → exit 2。
- 输出含 S0 所需 `SWEEP2_<d>: WNS=… WHS=…`、`V5_SWEEP2_OK: … bit=<归档位流绝对路径>`、`DRC finished with 0 Errors…`、`write_bitstream completed successfully`。
- 已用 round3c 实产日志离线验证：`S0_ADAPTER_SELFCHECK: WNS/WHS/okMarker/failMarker_absent/bitInLog/bitLeafMatch/drc0 全 PASS`（样例 `tools\selftest\R3C_diag_s0_adapter_sample.log`）。

---

## 5. S6/S10 需要的 ILA 探针（按核；round3d 期望值）

**判定链**：`out/r2_board.ps1` Step-S6 自动抓取走 `out/r2_ilacap.tcl`（UI 核按 `dbg_mem2_rd_frm`、USER 核按 `dbg_mem2_u_wr` 反查；delta 期望=ping 数 4）；S10 复用 S6 post CSV 跑 `r2_counter_recon.py --mode recon`（每桥 `wm==wr_frm==rd_frm`、`ost==0`、桥① `stall/len_err==0`、全局 `dbg_wr_fault==0`；`bresp/wslot/rslot` 缺失=INFO）。

### ILA3 @ui（round3d 152b / 14 probes）—— S6/S10 主证据

| probe（batch 名） | 宽 | 用途 |
|---|---|---|
| `dbg_calib` | 1 | 校准标志（INFO） |
| `dbg_mem_wm` / `dbg_mem_wr_frm` / `dbg_mem_rd_frm` | 16×3 | 桥①写/读计数（S6 delta=+4；S10 wm==wr_frm==rd_frm） |
| `dbg_mem_stall` / `dbg_mem_len_err` | 16×2 | 桥①错误计数（S10 硬判 0）— **round3c-diag 裁剪缺失、round3d 恢复** |
| `dbg_mem_ost` | 9 | 桥①溢出（S10 硬判 0） |
| `dbg_mem2_wm` / `dbg_mem2_wr_frm` / `dbg_mem2_rd_frm` | 16×3 | 桥②写/读计数（S6 rd_frm +4；S10 闭合）— round3d 恢复 |
| `dbg_mem2_ost` | 9 | 桥②溢出（S10 硬判 0）— round3d 恢复 |
| `dbg_s2mm_state` | 3 | S2MM 状态 0=IDLE…6=HALT（INFO） |
| `dbg_s2mm_tvalid_1` / `dbg_s2mm_tready_1` | 1×2 | 流握手（INFO；`_1` 因与 ILA5 同源 net） |

### ILA0 @user（110b / 13 probes）—— S6 全局错误/用户侧

| probe | 宽 | 用途 |
|---|---|---|
| `dbg_s2mm_reqpend` / `dbg_wr_fault` | 1×2 | S2 写入引擎挂起/故障（`dbg_wr_fault==0` 硬判） |
| `dbg_mem_u_wr` / `dbg_mem_u_rd` / `dbg_mem_u_drop` | 16×3 | 桥① user 侧收/发/丢帧 |
| `dbg_mem_rden_1` / `dbg_mem_ost_s` | 1 / 9 | 读使能 / 槽同步状态 |
| `dbg_mem2_u_wr` / `dbg_mem2_u_rd` | 16×2 | 桥② user 侧收/发帧 |
| `dbg_pfwd_data` / `dbg_pfwd_en` | 8 / 1 | 泵A→桥写入口（round3 起） |
| `dbg_mem_rden` / `mem_rd_data` | 1 / 8 | probe1 发射字节流（S8c；`dbg_mem_rden_1` 为重复 net 后缀） |

### ILA5 @ui（round3d 47b / 9 probes）—— 诊断，不进 S0–S11 硬判

| probe（batch/LTX 名） | 宽 | 用途 |
|---|---|---|
| `dbg_s2mm_tdata64` | **32**（lite 裁半） | S2MM 写流 beat0（低 32b 期望 `0x55555555`） |
| `dbg_s2mm_tkeep8` | 8 | TKEEP（首拍期望 `0xFF`） |
| `dbg_s2mm_tvalid` / `dbg_s2mm_tready` / `dbg_s2mm_tlast_w` | 1×3 | 流握手/尾拍 |
| `u_mem/gen_wr_dma_obs.dbg_wd_go_ui` | 1 | GO 是否到 ui/bridge（LTX 层次名；batch 可能显示叶名） |
| `u_mem/gen_wr_dma_obs.dbg_wd_ack_ui` | 1 | 桥 ACK |
| `u_mem/gen_wr_dma_obs.dbg_wd_intr_ui` | 1 | S2MM introut（粘滞判定） |
| `u_mem/u_bridge/g_wr_dma.dbg_wd_go_ok` | 1 | 桥 WAITGO 是否看到 GO |

> batch 名来源：`probes_r2_9852016C.ltx`（round3c-diag）实测解析；round3d 的 ILA0/ILA5 与之一致、ILA3 为全量版。若 batch 报 `_1`/层次名差异，以 `R2CAP_PROBE_UI`/`R3C_PROBE` 打印实测为准（工具均子串匹配）。

---

## 6. `R2CAP_EXPECT_PROBES` 5 → 9（**已落地**，2026-10-19 16:1x）与 S6/S10 宽度问题核对

### 6.1 已落地变更（`out\r2_ilacap.tcl`，仅默认串 + 注释；判据逻辑未动）
- 旧：`sha256 B5F2FF4CCADB53ED…B16FB72`（21,443 B，520 行）→ **新：`sha256 C67DE6E096A325F97A8DA662DC088A3352E79580350FA9B1C01EDAE7C31A7829`（`C67DE6E0`，22,056 B，528 行）**
- L125 默认列表（5 → 9）：
```tcl
set expect_probes [split [envval R2_EXPECT_PROBES "dbg_s2mm_reqpend,dbg_wr_fault,dbg_s2mm_state,dbg_s2mm_tvalid,dbg_s2mm_tready,dbg_wd_go_ui,dbg_wd_ack_ui,dbg_wd_intr_ui,dbg_wd_go_ok"] ","]
```
  ⇒ `R2CAP_EXPECT_PROBE_TOTAL` 自动为 **9**；round3d **不加 `dbg_l_bus`**（ILA4 跳过）。
- 头注释（L65-77）同步记录 4 个新探针（均 1-bit、ILA5）与“本脚本无宽度期望常量”的说明。
- 复核：`first3=35,32,61`（无 BOM）、ASCII-only（0 非 ASCII 字节）、`tcl_selfcheck.balance_scan` **0 error / 0 warning**、默认串 `llength=9`。

### 6.2 S6/S10 用 `-IlaCapture` 是否需要因 ILA3 63b→152b 改期望宽度/探针数？——**不需要**
- `r2_ilacap.tcl` **没有任何宽度期望常量**（无 `R2C_EXPECT_WIDTH_ILA*` 之类；只把实测宽度打印成 `R2CAP_PROBE(label): <probe> width=<w>`，见 L175-176）。ILA3 从 63b 恢复 152b 只增加列/探针，不影响其发现逻辑（按 `dbg_mem2_rd_frm` 子串反查核）。
- `R2CAP_EXPECT_PROBES` 只做**存在性**核对（WARN-only）且跨全部核收集；默认串改为 9 项后 round3d 全存在 ⇒ `R2CAP_EXPECT_PROBE_OK`。
- **注意**：`r2_board.ps1` S6 的 `-IlaCapture` 分支会**显式设置** `$env:R2_EXPECT_PROBES` 为旧 5 项（L1678），覆盖本脚本默认值 ⇒ 走 S0–S11 时 presence 检查仍是 5 项（WARN-only，round3d 全存在，不报错、不影响 S6/S10 判据）；新增 4 个 `dbg_wd_*` 的 presence 核对只在**直接运行** `r2_ilacap.tcl` 时生效。若要 `-IlaCapture` 路径也查 9 项，才需改 r2_board.ps1——**本轮口径不修改 r2_board.ps1**，故不做。
- 宽度核对建议（不改脚本即可）：S6 日志里用 `Select-String -Pattern 'R2CAP_PROBE\(UI\)'` 看 ILA3 各 probe `width=`（恢复后应见 `dbg_mem2_*`/`dbg_mem_stall`/`dbg_mem_len_err` 等列）；更强核对用 `tools/r3c_cap.tcl` 的 `R2C_EXPECT_WIDTH_ILA3=152`（WARN-only）或直接解析 LTX。
- `r2_counter_recon.py` 的 S6 delta / S10 recon 列（`dbg_mem_*`、`dbg_mem2_*`、`dbg_s2mm_*`）在 152b 后全部可观测 ⇒ S10 不再有 “stall/len_err 不可观测” 的 INFO 缺口。

---

## 7. 归档/回填清单（round3d 出流后 5 步）——**2026-10-19 16:29–16:33 已全部执行**

1. **归档**：✅ 已归档 `out/archive/b31b_r2_2026-10-19_round3d/`（bit/ltx/xsa/ELF/build 日志/adapter/报告/RTL 快照/`SHA256.txt`/`evidence/`）；身份见 §2。
2. **回填 §2 表**：✅ 已回填（bit `F6012BA0` / ltx `2F8AF498` / xsa `216839F4`，全量 SHA256 见上）。
3. **S0 适配**：✅ §4 方案 B——`R3D_s0_buildlog_adapter.log`（959 B / `7E705B7C`）作 `-BuildLog`；r2_board.ps1 未改。
4. **S0 预检**：✅（直接 -Run 跑，S0 16:29:21 PASS：`WNS=0.002 WHS=0.004 DRC=0; bit8=f6012ba0 elf8=ba3c0220 okMarker=有`）。
5. **S0–S11 全跑**：✅ 16:29:14–16:33:06（12 PASS + S10 wrapper NOT_OBTAINED，见 §2.2）；日志 `out/evidence_2026-10-19/R3D_S0-S11_run1.log`；记录模板按 `tools/r3c_board_session_template.md` 填写。

---

## 8. 风险 / 边界

| # | 风险 | 处置 |
|---|---|---|
| R1 | round3d 若改用 `V5_SWEEP2_OK` 的双掷脚本，则 §4 不需要 | 跑前 `Select-String -Path out\r3d_one.log -Pattern 'V5_SWEEP'` 确认（本轮实际为 `V5_SWEEP1_OK`，已由 adapter 处理） |
| R2 | `-IlaCapture` 只抓 ILA0/ILA3，不含 ILA5 GO/ACK/intr | 需要时另跑 `r3c_cap.tcl`（§3.3）；**本轮 S6 抓取已确认 ILA3=152b/14 probes、ILA0=110b/13 probes** |
| R3 | S6 delta 依赖 ping 数 = `-IlaExpectPing`（默认 4），改刺激须同步 | 保持默认 `ping -n 4`（本轮 S6 各 +4 实证） |
| R4 | ELF `BA3C0220` 不在 r2_board 内置 Known 列表 → S0 WARN | 预期行为；硬判以 `-ExpectElfHash8` 为准（本轮 S0 PASS 实证） |
| R5 | ILA3 152b 恢复可能吃 300MHz 余量（round3c attempt1 四核版 WNS=-0.029 被拒） | round3d `V5_SWEEP1_OK wns=0.002 whs=0.004` + DRC 0E 实测通过（余量比 round3c-diag 的 +0.004 更小但仍 ≥0） |
| R6 | 判据等级：S0 是离线身份判据；S6/S10 才是板端功能判据 | 结论按 AGENTS §6a 标 [L2]/[L3]；S10 为 [L2] 离线等价取证 |
| **R7** | **S10 wrapper 标记缺口（run1）**：recon 本体 PASS 但 `r2_board.ps1 Invoke-ReconJudge` 只认 `R2_RECON_RESULT:`，recon-only 分支不打印 → S10 记 NOT_OBTAINED | **已按 Lead 决策在工具维护窗口修复** `r2_counter_recon.py`（只补 marker print，判据逻辑零改动；旧 `C4AA2C3A…AF695D` → 新 `26172AAF…2F59F4`，备份 `.bak_20261019_recon_marker`）；run2 已复验 S10 PASS（§2.3） |
| **R8** | **J3/S9 flake（run2）**：J3 M 轮 `收帧停摆 @47/256` ⇒ S9 NOT_OBTAINED，板卡残留 sticky=1/backlog | **run3 已按 J3 纪律重烧后复验 PASS**（13/13 全 PASS）；未重试残留态 ✓。不要把 run2 S9 归因到 recon 补丁（补丁仅 S10 marker，与 S9 无关） |
