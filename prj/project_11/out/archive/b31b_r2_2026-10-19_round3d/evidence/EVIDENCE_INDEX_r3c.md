# R2 round3c 证据索引（`out/evidence_2026-10-19/` 目录）

> 生成：2026-10-19 16:0x（Agent Team `script-tools`，离线整理）｜复核：Lead
> 范围：本轮（round3b→round3c-diag→round3d 构建）在 `out/evidence_2026-10-19/` 落盘的全部文件 + 相关 `out/` 根日志 + `out/archive/` 归档；
> 方法：`sha8` = `Get-FileHash -Algorithm SHA256` 前 8 位；`行` = 文本文件行数（CSV 含表头/Radix 行）；**只读取、未改动任何证据文件**。
> 等级说明沿用 AGENTS §6a：`[L3]` 板端直证 / `[L2]` 对照成立 / `[L1]` 相容假说 / `[INFO]` 仅记录。本索引本身不产生结论。

**一句话现状**：round3c-diag 位流 `9852016C` 上板后 **数据面首次全通**（ping 20/20、S7 四档 PASS、S8 10MB 100%+SHA PASS [L2]）；50% 丢帧根因=固件 MM2S Reset 连带复位 S2MM（[L3]，PG021+事件环）；**S6/S10 待 round3d**（ILA3 恢复 152b）。

---

## 1. 数据面判据（S7/S8，[L2] 板端实测）

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3C_fourtier.log` | 1,456 | `31DA0DA0` | 24 | S7 四档首轮全 PASS（链路 20/20、基础 12/12、档深 12/12、稳定 300/300，18.9s）；修复前/对照场次 |
| `R3C_fourtier_perf1.log` | 1,456 | `8F848B07` | 24 | **S7 四档验收固件（perf1 BA3C0220）全 PASS**（15.4s，0 超时 0 损坏）→ 主证据 |
| `R2_mb10_20261019_155011.log` | 4,872 | `7D514491` | 57 | S8 10MB 首轮（15:50） |
| `R2_mb10_20261019_155136.log` | 4,890 | `83F1CD5E` | 57 | **S8 10MB PASS**：chunks=7022 recv=7022 lost=0 corrupt=0 sha_match=true；源=重组 SHA256 `4F38AF2C…A3BF5`（独立复算）→ 主证据 |
| `R2_mb10_20261019_155136.recomposed.jsonl` | 10,293,111 | `4F38AF2C` | — | 10MB 重组文件（SHA 与源一致）；可清理 |

## 2. ILA 采集（cap）—— 彩排（round3b ltx）与 round3c-diag（3 核）

> 工具：`tools/r3c_cap.tcl`（round3c 实做）；`R3C_RESULT/`CORE_TOTAL/PROBE_MAP/TRIG_STATUS 均在各 vivado 日志内。

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3C_cap_rehearsal_vivado.log` | 8,948 | `0A4754A9` | 158 | 彩排（round3b ltx，3 核）：ILA0 110b/13、ILA3 152b/14、ILA5 75b/5；`R3C_RESULT: PASS`（PRE/POST 各 3 份）。**注意这是 round3b 布局** |
| `R3C_cap_rehearsal_console.log` | 8,467 | `5F1510CE` | 155 | 同上控制台版 |
| `R3C_cap_rehearsal_vivado.jou` | 1,064 | `A6121EED` | — | vivado journal |
| `R3C_r3breh_ILA0_pre/post.csv` | 116,919 ×2 | `62BB80C7`/`F80BFC62` | 2050 | 彩排 ILA0 快照（round3b） |
| `R3C_r3breh_ILA3_pre/post.csv` | 68,835 ×2 | `CFA72526`（pre=post 全同） | 1026 | 彩排 ILA3（round3b 152b） |
| `R3C_r3breh_ILA5_pre/post.csv` | 37,908 ×2 | `3F4C9258` | 1026 | 彩排 ILA5（round3b 75b） |
| `R3C_cap_r3cA_vivado.log` | 8,766 | `30F22695` | 149 | round3c-diag ltx 首次触发抓取：ILA5 47b/9、ILA3 63b/8、ILA0 110b/13；**ILA5 ARM_FAILED**（`eq4'b1001` 位宽错：probe5 是 4 个 1-bit probe，不能按 4b 总线比较）→ `R3C_RESULT: FAIL`；教训已写入 r3c_pin.md §3.3 |
| `R3C_cap_r3cA_console.log` | 8,296 | `DABD7D04` | 146 | 同上控制台版 |
| `R3C_r3cA_ILA0_pre/post.csv` | 116,919 ×2 | `62BB80C7`/`A5730DD9` | 2050 | round3c-diag ILA0（pre=烧后基态，post=ping 后） |
| `R3C_r3cA_ILA3_pre/post.csv` | 38,993 ×2 | `1FEB8456`/`F6A5923E` | 1026 | round3c-diag ILA3 **63b 裁剪版**（缺 mem2/stall/len_err）⇒ **不可用于 S10 对账** |
| `R3C_r3cA_ILA5_pre/post.csv` | 38,066 ×2 | `5D69202F`/`141DE680` | 1026 | round3c-diag ILA5 **47b**（tdata32+tkeep8+3+probe5 4b） |
| `R3C_cap_snap1_vivado.log` | 6,636 | `84978CC4` | 122 | 楔死/静默后全核**快照**兜底（R2_SNAPSHOT_ONLY=1）：ILA0/ILA3/ILA5 各 pre 一份，`R3C_RESULT: PASS snapshot` |
| `R3C_cap_snap1_console.log` | 6,135 | `0969BC90` | 119 | 同上控制台版 |
| `R3C_r3cS1_ILA0_pre.csv` / `ILA3_pre.csv` / `ILA5_pre.csv` | 116,919 / 38,993 / 38,066 | `62322A77` / `37E00F11` / `8BB7DFC2` | 2050/1026/1026 | 快照三核（round3c-diag 47b/63b 布局）；ILA3 计数 `wm=wr_frm=rd_frm=0x0d` 见会话记录 §2 |
| `R3C_cap_snap1_vivado.jou` | 1,048 | `FA9E2573` | — | vivado journal |

## 2b. round3d 板验运行（S0–S11，三轮：**run1** 16:29–16:33 / **run2** 16:37–16:41 / **run3** 16:42–16:46）

**最终验收：run3 = 13/13 全 PASS（`R2_RESULT: PASS`，重烧后）**。过程证据保留：run1 = 12 PASS + S10 wrapper NOT_OBTAINED（补丁前）；run2 = S10 PASS（补丁生效）但 S9 NOT_OBTAINED（J3 flake，重烧后 run3 复验 PASS）。

### 2b.1 run1（历史；S10 为 wrapper 缺口）

**结果：12/13 步 PASS；S10 判据本体 PASS 但 wrapper 记 NOT_OBTAINED（工具标记缺口，非数据失败）** — `R2_RESULT: NOT_OBTAINED S10`。逐项：

| 步 | 判定 | 关键证据行（`R3D_S0-S11_run1.log`） |
|---|---|---|
| S0 | PASS | `[JUDGE] S0 PASS: WNS=0.002 WHS=0.004 DRC=0; bit8=f6012ba0 elf8=ba3c0220 okMarker=有`（方案 B adapter 生效） |
| S1 | PASS | 在位记录（mode=1 / req=0x00000076 / 'L'=True / 邻居=True / ping 1/1） |
| S2 | PASS | 未发 'd'：ping 0/1 + NIC Δ=0 + `last_commit_len=0`（R2 身份成立） |
| S3 | PASS | `'d'` 后 mode=1 & req.bit24=1 |
| S3b | PASS | pending==0 & fault==0 连续两拍 |
| S4 | PASS | 单帧：ping 1/1、NIC +74B、WM_WR+1/WM_RD+1 |
| S5 | PASS | ping 4/4、NIC +296B、WM_WR+4/WM_RD+4 |
| **S6** | **PASS** | `mem wm/wr_frm/rd_frm 各 +4, mem ost=0; mem2 rd_frm +4, mem2 ost 前后 0` ⇒ **round3d ILA3=152b 恢复生效、双桥前后差分闭合** |
| S7 | PASS | 四档 `DDR_VERIFY: PASS`（20/20·12/12·12/12·300/300） |
| S8 | PASS | 10MB：chunks=7022 recv=7022 lost=0 corrupt=0 sha_match=true |
| S9 | PASS | J3 fourchains（`--dma`）M/A/B 全 PASS |
| **S10** | **NOT_OBTAINED（wrapper，历史）** | recon 本体 `R2_COUNTER_RECON: PASS`（mem/mem2 wm==wr_frm==rd_frm=9/9/9、ost=0、mem stall/len_err=0、wr_fault=0），但 r2_board `Invoke-ReconJudge` 只认 `R2_RECON_RESULT:` 标记，而当时 `r2_counter_recon.py --mode recon` 分支未打印该标记 ⇒ 默认 NOT_OBTAINED。**已由 run2 复验 PASS（见 2b.2）**；run1 保留为“补丁前 NOT_OBTAINED”历史证据。 |
| S11 | PASS | 收尾引擎确认 mode=1 & req.bit24=1 |

> run1 S10 历史处置（保留）：当时 wrapper 缺 `R2_RECON_RESULT:`，以离线等价复跑取证——`R2_counter_recon.py --mode recon --ui-post R2_ila_r2_20261019_162914_ui_post.csv --user-post …_user_post.csv` → **exit 0 + `R2_COUNTER_RECON: PASS`**；证据 `R3D_S10_recon_manual.log/.json`。Lead 随后在工具维护窗口按**一行 marker 补丁**修复 `r2_counter_recon.py`（判据逻辑零改动），run2 复验 S10 PASS（见 2b.2）。**不要**用 `--ui-pre` 强行进 delta+recon 复合分支（S10 时计数已变化、delta 非 +4 会判 FAIL）。

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3D_S0-S11_run1.log` | 70,144 | `E18BBDF0` | — | **round3d 完整 S0–S11 运行日志**（16:29:14–16:33:06；12 PASS + S10 wrapper NOT_OBTAINED；末尾有汇总重放） |
| `R2_20261019_162914.log` | 71,617 | `BA0757A5` | — | r2_board.ps1 自身日志（同一次运行，UTF-8 BOM） |
| `R2_ilacap_vivado_20261019_162914.log` | 6,670 | `2754A420` | — | S6 自动 ILA 抓取（vivado batch；`R2CAP_RESULT: PASS`，3 核） |
| `R2_ilacap_vivado_20261019_162914.jou` | 1,048 | `10BC9179` | — | 同上 journal |
| `R2_ila_r2_20261019_162914_ui_pre.csv` / `_ui_post.csv` | 68,835 ×2 | `4B65FEC1`/`4B3F5C0C` | 1026 | **round3d ILA3 152b（14 probes）PRE/POST** ⇒ S6 delta / S10 recon 主证据 |
| `R2_ila_r2_20261019_162914_user_pre.csv` / `_user_post.csv` | 116,919 ×2 | `EC8C97E2`/`134CC380` | 2050 | **round3d ILA0 110b（13 probes）PRE/POST**（含 `dbg_wr_fault=0`/`reqpend=0`） |
| `R2_4tier_20261019_162914.log` | 1,459 | `9B4175C1` | — | S7 四档运行日志 |
| `R2_mb10_20261019_163149.log` | 4,891 | `720C3A38` | — | S8 10MB 日志（`R2_MB10_RESULT: PASS`） |
| `R2_mb10_20261019_163149.recomposed.jsonl` | 10,293,111 | `4F38AF2C` | — | S8 重组文件（SHA=源，可清理） |
| `R3D_S10_recon_manual.log` / `.json` | 3,795 / 1,186 | `3114AAD9`/`F1DDBB20` | 46/49 | **S10 判据本体离线等价取证**（PASS；见上 S10 处置） |
| S0 适配日志（归档） | 959 | `7E705B7C` | — | `round3d\R3D_s0_buildlog_adapter.log`（方案 B；S0 已用其 PASS） |

> 说明：S0 的两条预期 WARN：① `-ExpectElfHash8 BA3C0220` ≠ r2_board 内置 Known 列表（旧 round2d 值）——仅 WARN；② adapter `bit=` 行为 out 默认名（生成时 `--bit` 指向 `out/aurora_mem_bridge.bit`）与 `-Bit` 归档名不同 → 文件名 WARN（hash 仍按 `-Bit` 实算硬判）。两者均**不影响 S0 PASS**。

### 2b.2 run2（工具补丁后重跑，16:37:14–16:41:24）——**S10 PASS 复验成功；S9 NOT_OBTAINED（J3 flake）**

**结果：S10 已 PASS（补丁生效）；S9 本轮 NOT_OBTAINED（J3 `收帧停摆 @47/256`，板卡需重烧重跑，非工具问题）** — `R2_RESULT: NOT_OBTAINED S9`；S0–S8/S10/S11 PASS。

| 步 | run2 | 关键证据 |
|---|---|---|
| S0–S8 | PASS | 同 run1（S6 `mem/mem2 各 +4、ost=0`；S7 四档 PASS；S8 10MB PASS） |
| **S9** | **NOT_OBTAINED** | J3 M 轮 `收帧停摆 @47/256` → `[M] FAIL wr+256 rd+47 inv=1081 miss=209`；重试段 @1/256 亦 FAIL；`FOURCHAINS_RESULT: FAIL M (判据未取得; 板卡需重烧)`；现场 `mode=1 engine=0 sticky=1 wmwr=7682 wmrd=7450`（232 帧 backlog）。日志 `out/evidence_2026-10-17/j3_fourchains_20261019_164008.log`（8,720 B / `D145375E`）+ `j3_m_20261019_164008.log`（2,040 B / `1F452244`） |
| **S10** | **PASS** | L846-847 `R2_COUNTER_RECON: PASS` + `R2_RECON_RESULT: PASS` → L1322 `[JUDGE] S10 PASS`（mem/mem2 wm==wr_frm==rd_frm、ost=0、mem stall/len_err=0、wr_fault=0） |
| S11 | PASS | 收尾确认（但 S9 后板卡残留 sticky=1，建议重烧后再验） |

**工具补丁说明（只加 marker print，判据逻辑零改动）**：`out\r2_counter_recon.py` 旧 sha256 `C4AA2C3AAFB050F51161D773E468A12F8A58B7C63955FF0F8F3C3C9939AF695D`（45,947 B）→ 新 `26172AAF507D183F141D924E46C6D98DD7D4F7FB25BCB238DDC6C957672F59F4`（46,313 B）；备份 `r2_counter_recon.py.bak_20261019_recon_marker`（同旧全量 45,947 B）；diff 仅 2 处 marker print + 3 行注释；py_compile exit 0（Lead 验）；离线复跑 exit 0 + `R2_RECON_RESULT: PASS`。
**S9 处置（按既有 J3 纪律，不自动重试）**：`wr+255/收帧停摆` ⇒ 判据未取得 + 板卡需重烧；当前残留 `sticky=1`/`wmrd-wmwr=232`，**不得在残留态重试 J3**；建议重烧 round3d pair 后重跑（S9 必须新烧录后跑）。

| run2 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3D_S0-S11_run2.log` | 70,856 | `B9018AE0` | — | **run2 完整 S0–S11 日志**（16:37:14–16:41:24；S10 PASS、S9 NOT_OBTAINED） |
| `R2_20261019_163712.log` | 72,348 | `4FD6F2A6` | — | r2_board.ps1 自身日志（run2） |
| `R2_ilacap_vivado_20261019_163712.log` / `.jou` | 6,670 / 1,048 | `5F8C75E3`/`BF6A21CB` | — | run2 S6 自动 ILA 抓取（`R2CAP_RESULT: PASS`） |
| `R2_ila_r2_20261019_163712_ui_pre/post.csv` | 68,835 ×2 | `4B65FEC1`/`4B3F5C0C` | 1026 | run2 ILA3 152b/14 probes |
| `R2_ila_r2_20261019_163712_user_pre/post.csv` | 116,919 ×2 | `09D27A80`/`FE1FCB0D` | 2050 | run2 ILA0 110b/13 probes |
| `R2_4tier_20261019_163712.log` | 1,459 | `9B4175C1` | — | run2 S7 四档 |
| `R2_mb10_20261019_163946.log` | 4,890 | `E54BFC17` | — | run2 S8 10MB（PASS） |
| `R2_mb10_20261019_163946.recomposed.jsonl` | 10,293,111 | `4F38AF2C` | — | run2 S8 重组（可清理） |
| `j3_fourchains_20261019_164008.log` / `j3_m_20261019_164008.log`（**2026-10-17 目录**） | 8,720 / 2,040 | `D145375E`/`1F452244` | — | **run2 S9 J3 失败现场**（`FOURCHAINS_RESULT: FAIL M`） |
| `R2_counter_recon.py` 补丁前/后 | 45,947→46,313 | `C4AA2C3A`→`26172AAF` | — | 见 `tools/selfcheck.txt §10.9`；备份 `.bak_20261019_recon_marker` |

### 2b.3 run3（重烧后最终验收，16:42:45–16:46:35）——**13/13 全 PASS**

日志：`R3D_S0-S11_run3.log`（69,821 B / sha256 `EC927EC68F8C121DCED02E4124A2BD6D098F34C89F86BD667E56E576A9A46646` / sha8 `EC927EC6`）。

**结果：`R2_RESULT: PASS` —— S0–S11 全 13 步 PASS**（与 Lead 预期一致）。S9 在重烧 round3d pair 后 PASS（`J3_ROUND M/A/B: PASS exit=0`、`FOURCHAINS_RESULT: PASS`）；S10 补丁 marker 复验 PASS；S11 `sticky=0`。⇒ 确认 run2 的 S9 失败是**可重烧恢复的板卡起始态问题**（J3 纪律成立：残留态不重试、重烧后复验），与 recon 补丁无关。

| 步 | run3 | 关键行 |
|---|---|---|
| S0–S8 | PASS | S0 `WNS=0.002 WHS=0.004 DRC=0; bit8=f6012ba0 elf8=ba3c0220 okMarker=有`；S6 `mem/mem2 各 +4、ost=0`；S7 四档 PASS；S8 10MB PASS |
| **S9** | **PASS** | J3 `--dma`：`J3_ROUND M/A/B: PASS exit=0`、`FOURCHAINS_RESULT: PASS`（`out/evidence_2026-10-17/j3_fourchains_20261019_164540.log` 9,384 B / `20FCABCC`） |
| **S10** | **PASS** | recon `R2_RECON_RESULT: PASS` → `[JUDGE] S10 PASS` |
| S11 | PASS | 收尾 `mode=1 req.bit24=1 sticky=0 wmwr=8145 wmrd=8143` |

| run3 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3D_S0-S11_run3.log` | 69,821 | `EC927EC6` | — | **run3 完整 S0–S11 日志（13/13 PASS；最终验收）** |
| `R2_20261019_164245.log` | 71,294 | `49CB7DB2` | — | r2_board.ps1 自身日志（run3） |
| `R2_ilacap_vivado_20261019_164245.log` / `.jou` | 6,670 / 1,048 | `E07E3063`/`39DF5218` | — | run3 S6 自动 ILA 抓取（`R2CAP_RESULT: PASS`） |
| `R2_ila_r2_20261019_164245_ui_pre/post.csv` | 68,835 ×2 | `4B65FEC1`/`4B3F5C0C` | 1026 | run3 ILA3 152b/14 probes |
| `R2_ila_r2_20261019_164245_user_pre/post.csv` | 116,919 ×2 | `E752B674`/`9A1961ED` | 2050 | run3 ILA0 110b/13 probes |
| `R2_4tier_20261019_164245.log` | 1,459 | `9B4175C1` | — | run3 S7 四档（PASS） |
| `R2_mb10_20261019_164518.log` | 4,892 | `8971CEB3` | — | run3 S8 10MB（PASS） |
| `R2_mb10_20261019_164518.recomposed.jsonl` | 10,293,111 | `4F38AF2C` | — | run3 S8 重组（可清理） |
| `j3_fourchains_20261019_164540.log` + `j3_m/a/b_…log`（**2026-10-17 目录**） | 9,384 + 800/805/800 | `20FCABCC`/`93555889`/`93C17B24`/`FD5E6303` | — | run3 S9 J3 全 PASS 现场 |

## 3. 串口会话（原始记录/彩排）

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3C_serial_PJK_rehearsal.log.md` | 6,568 | `133383A7` | 77 | **P/G/C/J/K 固件实验串联口原文转录**（round3b+02F7153A）：LENGTH→GO 跨从机写、无真实帧请求不楔死、实帧到达+服务才复现；§2 含 r3c_diag.tcl 现场（g_step=11/0x80010056 冻结）[L2] |
| `R3C_serial_ping_rehearsal.txt` | 1,465 | `BD4CBB26` | 22 | ping/串口彩排原始片段（12:39） |

## 4. 固件/事件环/JTAG 调试

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3C_evt2_dump.txt` | 9,016 | `CC2C225D` | 549 | **事件环固件 `g_evt[512]` 全量 dump（48 事件）**：成功帧 `0x15→0x16(s2sr=0x1002)→commit→0xD1` vs 失败帧 `0x16(s2sr=0x0001 Halted)` ⇒ 50% 隔帧丢根因主证据 [L3 链] |
| `R3C_evt2_symtab.txt` | 2,566 | `31F73846` | 107 | evt2 固件符号表（g_evt 等地址） |
| `R3C_elf_symtab.txt` | 2,511 | `0806B1E4` | 104 | F5E0F1F3 诊断固件符号表（g_step/g_wa_* 0x45xx） |
| `R3C_elf_disasm.txt` | 150,940 | `D8037779` | 4091 | 固件反汇编（PC 0x72c–0x73c=uputc TX_FULL 轮询落点佐证） |
| `R3C_diag_rehearsal_round3b.log` | 3,548 | `45963EC0` | 99 | `tools/r3c_diag.tcl` 首次彩排：SYMTAB 14 项 OK、mismatch=0、`G_STEP=0xb stable=1`、PC 0x730/0x738 |
| `R3C_diag_rehearsal2.log` | 3,548 | `45963EC0` | 99 | 同上（重复跑，逐字节一致） |
| `R3C_diag_rehearsal3.log` | 5,212 | `46E4440E` | 99 | 新固件（0x4bXX 符号）彩排：SYMTAB_WARN×14（ELF 变、地址变，脚本自动用 ELF 值）仍 `G_STEP=0xb stable=1` → 证明符号动态解析有效 |
| `R3C_lmb_dump_rehearsal.log` | 1,405 | `EFF66801` | 58 | LMB 区域 dump 彩排（PC/邻域变量形态） |
| `R3C_jtag_axi_probe_rehearsal.log` | 1,866 | `C2A36489` | 50 | JTAG 直读 AXI Lite/DMA 寄存器彩排：**全部 `ERR(Memory read error … overrun)`** ⇒ 楔死态 AXI 不可经 JTAG 读（解释为何 LMB 全局快照是主取证通道） |

## 5. 烧录记录（`jb31b_burn_pair.tcl` → 期望 `PAIR_BURNED`）

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3C_round3c_burn.log` / `R3C_reburn_round3c.log` / `R3C_reburn2_round3c.log` | 975 ×3 | `0093FFE5` | 37 | round3c-diag 9852016C + 各固件烧录（重烧） |
| `R3C_rehearsal_burn.log` / `R3C_rehearsal2_burn.log` | 975 / 979 | `DD284E66`/`3413403B` | 37 | 彩排烧录 |
| `R3C_ab_round2f_burn.log` | 978 | `43B051F9` | 37 | A/B 对照烧 round2f 对 |
| `R3C_ctrl_round2f_pair_burn.log` / `…_burn2.log` | 2,049 / 225 | `D5FA3156`/`843E2096` | 69/4 | round2f 原配对照烧录（含第二次短日志） |
| `R3C_jk_burn.log` / `R3C_pgc_burn.log` | 941 ×2 | `8FE051EF` | 37 | J/K、P/G/C 实验固件烧录 |
| `R3C_evt_burn.log` / `R3C_evt2_burn.log` / `R3C_fix1_burn.log` / `R3C_fix1_burn2.log` / `R3C_perf1_burn.log` | 941–1,981 | `3CB7AB71`（多数）等 | 37–69 | 事件环/修复/验收固件烧录场次 |

## 6. 固件构建记录（Vitis/手编，秒级）

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `R3C_fwbuild_PGC.log` / `_JK.log` / `_evt.log` / `_evt2.log` / `_fix1.log` | 226 ×5 | `0B3B816C` | 3 | 各固件 `make` 构建记录（三行式，构建输入/hash 见归档 ELF） |

## 7. 构建证据（round3c attempt1/2；round3d 进行中）

| 文件/目录 | 大小 | sha8 | 说明 |
|---|---|---|---|
| `round3c_build_attempt1/r3c_synth_attempt1.log` | 302,060 | `CD9A6DA3` | 四核版（含 ILA4）综合成功日志 |
| `round3c_build_attempt1/r3c_synth_attempt1_console.log` | 304,596 | `E1473ECF` | 控制台版 |
| `round3c_build_attempt1/r3c_sweep2_attempt1.log` | 301,672 | `84542512` | 四核版 sweep2：`ExtraTimingOpt` 后布 WNS=-0.216→**-0.029 被门限拒**（ILA4 时序代价实证） |
| `round3c_build_attempt1/r3c_sweep2_attempt1_console.log` | 304,263 | `8AD169B6` | 控制台版 |
| `round3c_build_attempt2/r3c2_one_attempt2.log` | 307,899 | `E78CF83B` | 3 核 lite 单掷 attempt2（失败/重跑轮，留档） |
| `round3c_build_attempt2/r3c2_one_attempt2_console.log` | 310,564 | `B88413E9` | 控制台版 |
| （out 根）`r3c3_synth.log` / `r3c3_one.log` | 178,793 / 309,855 | `AF18EB2E` / `DDDEC27C` | **round3c-diag 成功构建**（V5_SWEEP1_OK wns=0.004 whs=0.004；DRC 0E/22W）；归档副本见 round3c 归档 |
| （out 根）`r3c_regen_bd.log` | 6,242 | `5F1EAD52` | BD 全量 regen（dbg_l_bus[35:0] 引出）→ 楔死消失相关 [L1] 线索 |
| （out 根）`r3c2_one*.log` / `r3c2_sweep2*` / `r3c_synth*` | — | — | round3c 中间轮日志（部分已进 attempt 目录/归档） |
| （out 根）`r3d_synth_retry.ps1` / `r3d_sweep_one_retry.ps1` / `r3d_synth.log` | 178,672 | `A0E0BCC4`（归档副本） | **round3d synth PASS（15:58）**：`Synthesis finished with 0 errors, 0 critical warnings and 600 warnings` + `SYNTH_ONLY_DONE`；`R3C_LITE_ILA: 0  R3C_LITE_ILA5: 1`；`ILA5_PROBES: tdata64=32 tkeep8=8 + tvalid/tready/tlast + probe5=4`；`ILA4_SKIPPED`；`pre_impl_debug.dcp` 已出 |
| （out 根）`r3d_one.log` / `r3d_one_console.log` | 319,534（归档 `build_r3d_one.log`）/ — | `4EB258C5` | **round3d sweep PASS（16:0x）**：`SWEEP1_ExtraTimingOpt: WNS=0.002 WHS=0.004` → `V5_SWEEP1_OK: directive=ExtraTimingOpt wns=0.002 whs=0.004 bit=…`；`DRC finished with 0 Errors, 22 Warnings`；`write_bitstream completed successfully`（Lead 报 PASS: WNS=+0.002 / WHS=+0.004） |

## 8. 规划/记录/审计

| 文件 | 大小 | sha8 | 行 | 内容/用途 |
|---|---|---|---|---|
| `NEXT_ROUND_NOTES.md` | 3,696 | `8161C5EA` | 13 | 14:2x 阶段计划（ILA 抓取 Run A/B/C/D、板端已知状态、待办）——**部分已被 15:5x 进展超越，仅作历史** |
| `R3C_board_session_20261019.md` | 6,318 | `CF86309A` | 70 | **Lead 本轮板验会话记录**：工件身份、楔死消失、50% 根因 [L3]/PG021、修复后判据、未完成项 |
| `audit/R3C_probe_review.md` | 29,429 | `028D175A` | — | rtl-auditor：round3c 探针方案复核（BD 内 mark_debug 存活等） |
| `audit/R3C_wedge_hypotheses.md` | 43,505 | `AEF07A51` | — | 楔死根因候选集与波形签名（含 S2MM 零 commit 候选） |
| `audit/R3C_round3d_impact.md` | 11,682 | `0B5CCA7F` | — | round3d 改动影响面 |
| `audit/round3d_candidate.patch` | 16,778 | `1598AD5A` | — | round3d 修复候选补丁草案（不直接改 RTL） |
| `audit/sim/README.md` | 3,368 | `F71FD57A` | — | 审计侧仿真说明（本轮未跑/或按需） |

## 9. 工具（`tools/`；含交付链与 Lead 追加）

| 文件 | 大小 | sha8 | 用途 |
|---|---|---|---|
| `tools/r3c_cap.tcl` | 25,863 | `A876EEC3` | 4 核 ILA 采集（自动发现/触发/PRE-POST/快照；坑 #66 合规） |
| `tools/r3c_diag.tcl` | 12,001 | `7EE22D6D` | 楔死后 JTAG/LMB 读取（mb-nm 符号核对 + 坑 #54 复读） |
| `tools/r3c_seq.ps1` | 32,371 | `EC748C15` | 板验序列编排（Plan/Burn/Serial/Cap/Diag/All；默认 dry-run） |
| `tools/r3c_ila_analyze.py` | 58,655 | `6FFF80B8` | CSV 判读（ILA4 packed 解码 / ILA5 / legacy / R3C_ILA4/5_HYPOTHESIS） |
| `tools/r3c_pin.md` | 29,521 | `34B4536B` | **round3d 身份（真实 hash）/命令模板/S0 方案B/S6-S10 探针表/R2CAP 5→9/S10 补丁说明/三轮 S0–S11 结果（run3 13/13 PASS）** |
| `tools/r3d_s0_buildlog_adapter.py` | 9,434 | `C0ABA8CA` | 把 `V5_SWEEP1_OK` 日志转成 S0 可解析的适配日志（**本轮采用方案 B**；不改 r2_board.ps1） |
| `tools/r3c_runbook.md` | 19,251 | `FD2B1D42` | 板验 runbook（含假设签名速查） |
| `tools/r3c_board_session_template.md` | 11,520 | `8BE34D07` | 板验记录模板 |
| `tools/selfcheck.txt` | 41,267 | `C128CD83` | 工具链自检（BOM/ParseFile/py_compile/Tcl 平衡/正负自检/S0 adapter/R2CAP 改动/round3d 回填与 run1–run3 复核/§10.9 补丁与 run3 13/13 PASS） |
| `tools/tcl_selfcheck.py` | 11,308 | `DF320DD5` | Tcl 静态自检器 |
| `tools/selftest/` | — | — | 合成 CSV/干跑日志/S0 adapter 样例 |
| `tools/r3c_evt_dump.tcl` | 533 | `3BE2DF97` | Lead 追加：事件环 dump（xsct） |
| `tools/r3c_lmb_dump_oneoff.tcl` | 773 | `2F372278` | Lead 追加：LMB 一次性 dump |
| `tools/r3c_jtag_axi_probe_oneoff.tcl` | 1,429 | `718DBDC0` | Lead 追加：JTAG 直读 AXI helper |
| `tools/r3c_pingprobe.py` | 2,594 | `8196F738` | Lead 追加：ping/计数探针 |
| `tools/r3c_serial_ping_session.py` | 2,801 | `C7B513D4` | Lead 追加：串口 ping 会话记录器 |
| **（out 根）`out/r2_ilacap.tcl`** | 22,056 | `C67DE6E0` | **S6/S10 自动 ILA 抓取脚本（本轮唯一改动的 out 根脚本）**：`R2_EXPECT_PROBES` 默认 5→9（+`dbg_wd_go_ui/ack_ui/intr_ui/go_ok`；round3d 不加 `dbg_l_bus`）+ 头注释更新；旧 `B5F2FF4C`（21,443 B/520 行）→ 新 `C67DE6E0`（22,056 B/528 行）；判据逻辑未动；无 BOM/ASCII/括号平衡 0 err 已复核 |

## 10. 归档（`out/archive/`）

| 归档目录 | 关键产物 | 身份 |
|---|---|---|
| `b31b_r2_2026-10-19_round3c/`（**本轮成功，3 核 diag**） | `aurora_mem_bridge_r2_9852016C.bit` | 10,010,456 B / `9852016C` |
| | `probes_r2_9852016C.ltx`（3 核 110/63/47b） | 61,674 B / `DE94D05F` |
| | `mb_ctrl_r2.xsa` | 2,605,217 B / `BEB97199` |
| | ELF 快照：`F5E0F1F3`(诊断)、`7DAEA8C4_pgc`、`DB88C9D0_jk`、`21E13038_evt`、`3251406F_evt2`、`69D61B9B_fix1`、`BA3C0220_perf1`（**当前板上验收固件**） | 见 `r3c_pin.md` §1 |
| | `BUILD_STATUS.md` / `SHA256.txt` / `build_r3c3_*.log` / `rpt3_*` | 见 `r3c_pin.md` §1 |
| `b31b_r2_2026-10-19_round3b/`（前一轮，3 核） | bit `02F7153A` / ltx `0B2CC2F5` | 历史对照 |
| **`b31b_r2_2026-10-19_round3d/`（验收位流，已归档 16:2x）** | `aurora_mem_bridge_r2_F6012BA0.bit` | **9,288,496 B / `F6012BA0`**（全量 `F6012BA0FF8F9D7F3BCD9AC848A97F1C5E1B6DD7016DAD5BEBE93755E73C54C4`）；构建 PASS `V5_SWEEP1_OK wns=0.002 whs=0.004` |
| | `probes_r2_F6012BA0.ltx`（3 核，LTX 解析实测 **ILA0 110b/13、ILA3 152b/14、ILA5 47b/9**） | 82,040 B / `2F8AF498`（全量 `2F8AF49895396EBD33D08389EDE1BC2158DBA83D2398B1B8A4AE350B34BAF686`） |
| | `mb_ctrl_r2.xsa` | 2,579,584 B / `216839F4`（全量 `216839F4B6070621706D635CD9B76A9DAAED43EDADFB4AFC5B7DC66D9BB816F6`） |
| | ELF `j3_soft_r2_BA3C0220.elf`（验收固件 perf1） | 61,296 B / `BA3C0220` |
| | `R3D_s0_buildlog_adapter.log`（S0 适配日志） | 959 B / `7E705B7C`（内容见 §2b） |
| | `build_r3d_one.log`（159 KB→319,534 B）/ `build_r3d_synth.log` | `4EB258C5` / `A0E0BCC4` |
| | `SHA256.txt`（47 行，含头注释） | 4,711 B / `4901579B` |
| | `rpt3_ExtraTimingOpt.*` / `rtl_*.v` 快照 / `j3_fourchains.ps1`(+original) / `evidence/` 子目录 | 见 `r3c_pin.md` §2 |

## 11. 缺口 / 判据未取得 / 注意（§6a：判据未取得 ≠ 通过）

1. **S6 已取得（PASS，run1/run2/run3 三轮一致）**：ILA3 恢复 152b 后双桥前后差分闭合（`mem wm/wr_frm/rd_frm 各 +4, ost=0; mem2 rd_frm +4, ost 前后 0`）→ 本索引 §2b。
2. **S10 已取得（PASS，run2/run3 复验）**：工具维护窗口按 Lead 决策修 `r2_counter_recon.py` recon 模式漏打 `R2_RECON_RESULT:`（**只加 marker print + 注释，判据逻辑零改动**；旧 `C4AA2C3A…` → 新 `26172AAF…`，备份 `.bak_20261019_recon_marker`）；run2 L846-847 `R2_COUNTER_RECON: PASS` + `R2_RECON_RESULT: PASS` → L1322 `[JUDGE] S10 PASS`，run3 同样 PASS。run1 的 NOT_OBTAINED 保留为“补丁前”历史证据。
3. **S9 已取得（PASS，run1 + run3；run2 曾 NOT_OBTAINED）**：run2 J3 M 轮 `收帧停摆 @47/256`（`wr+256 rd+47`，`FOURCHAINS_RESULT: FAIL M`，现场 `engine=0 sticky=1 wmwr=7682 wmrd=7450`）；按既有 J3 纪律**不重试残留态**，重烧 round3d pair 后 **run3 `J3_ROUND M/A/B: PASS exit=0`、`FOURCHAINS_RESULT: PASS`** ⇒ S9 对板卡起始态敏感（已知纪律），非工具/位流缺陷 [L2]。
4. **S11/S2–S5 逐步记录：已取得（PASS，run1/run3）** → 本索引 §2b；run3 收尾 `sticky=0`。
5. **最终验收（run3）：`R2_RESULT: PASS`，S0–S11 全 13 步 PASS**（位流 `F6012BA0` + ELF `BA3C0220`，重烧后）。
6. **ILA5 GO/ACK/intr 触发证据仍未取得**（S6 只抓 ILA0/ILA3）：如需该证据，用 `r3c_cap.tcl` + `R2_TRIG_ILA5="dbg_wd_go_ui=eq1'b1"` 单独抓（不要用 `eq4'b1001` 总线比较——probe5 是 4 个 1-bit probe）。
7. **楔死消失的机制解释未定案**：BD 全量 regen 后 round3b 序列不再楔死（[L2] 现象级）；机制级解释可对照 round3c regen 日志（[L1]）。
8. **`r2_board.ps1` S0 与 `V5_SWEEP1_OK` 不兼容**：**已用方案 B（adapter）解决并在三轮 S0 实证 PASS**（本索引 §2b；工具 `tools/r3d_s0_buildlog_adapter.py`）。
9. `R2_mb10_20261019_{155136,163149,163946,164518}.recomposed.jsonl` 各 10,293,111 B 重组中间文件，可清理（SHA 已在日志中）。

## 12. `R2CAP_EXPECT_PROBES` 覆盖核对（round3d）

- `out/r2_ilacap.tcl` 默认 5 项（`dbg_s2mm_reqpend,dbg_wr_fault,dbg_s2mm_state,dbg_s2mm_tvalid,dbg_s2mm_tready`）在 round3d LTX 中**全部存在**（ILA0/ILA3）→ 现有检查即通过。
- round3d 新增的 ILA5 probe5 4 项（`dbg_wd_go_ui/ack_ui/intr_ui/go_ok`）**已并入** `out/r2_ilacap.tcl` 默认列表（5→9，2026-10-19 16:1x 落地，`R2CAP_EXPECT_PROBE_TOTAL`=9；改动记录 `tools/r3c_pin.md` §6 + `tools/selfcheck.txt` §10.5）。`dbg_l_bus`（ILA4）round3d 不需要（已跳过）。
- `r2_ilacap.tcl` **无宽度期望常量**（ILA3 63b→152b 无需改脚本；宽度仅打印）。`r2_board.ps1` S6 在 `-IlaCapture` 分支显式覆盖 `R2_EXPECT_PROBES` 为旧 5 项（L1678，WARN-only，round3d 全存在 ⇒ 不影响判据；本轮不改 r2_board.ps1）。ILA3 152b 后 `r2_counter_recon.py` 的 S6 delta / S10 recon 所需列全部可观测（见 `tools/r3c_pin.md` §5/§6.2）。
- **round3d 实测**：S6 抓取 `R2_ilacap_vivado_20261019_162914/163712/164245.log` 均 `R2CAP_RESULT: PASS`；三个 run 的 `_ui_post.csv` 均为 **ILA3 152b/14 probes** 全量布局；S6 PASS（各 +4）。**S10 本体 PASS**（`R2_COUNTER_RECON: PASS`，mem/mem2 9/9/9、ost=0、stall/len_err=0、wr_fault=0）；run1 wrapper NOT_OBTAINED 系标记缺口、run2/run3 已 PASS（见 §2b/§11-2）。

---

### 索引统计

- 本索引覆盖：`out/evidence_2026-10-19/` 顶层 **108 个文件**（本索引自身为第 109 个；其中 round3d S0–S11 三轮运行新增文件见 §2b）+ `audit/` 5 + `round3c_build_attempt1/` 4 + `round3c_build_attempt2/` 2 + `tools/` 15（另含 selftest/ 子项）+ `out/` 根日志（r3c3/r3d/r3c2 等）+ `out/archive/` 3 轮（round3b / round3c / **round3d**）+ 跨目录 J3 日志（`evidence_2026-10-17/j3_*_20261019_{164008,164540}.log`）；另收录本轮改动的 out 根脚本 `out/r2_ilacap.tcl` 与 `out/r2_counter_recon.py`（见 §9 表末行）。
- 索引行数：更新后 **242 行**（`Get-Content EVIDENCE_INDEX_r3c.md | Measure-Object -Line`；初版 148 → 149（R2CAP）→ 192（round3d 回填）→ 218（run2）→ 242（run3 最终验收 + 缺口/结论链更新））。
- 复算命令：`Get-ChildItem -LiteralPath <dir> -File | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.Substring(0,8) }`

### 本轮结论链（供记录引用）

| 结论 | 等级 | 主证据 |
|---|---|---|
| 数据面全通（ping/四档/10MB） | [L2] | `R3C_fourtier_perf1.log`、`R2_mb10_20261019_155136.log`、`R3C_board_session_20261019.md` §4 |
| 50% 隔帧丢根因 = MM2S Reset 连带复位 S2MM | [L3]（机制直证+PG021） | `R3C_evt2_dump.txt`（失败帧 `s2sr=0x0001 Halted`）、`R3C_serial_PJK_rehearsal.log`、会话记录 §3 |
| round3b 楔死（读回冻结）在本轮位流+固件下不复现 | [L2] | 会话记录 §2、`R3C_diag_rehearsal*.log` |
| **round3d 最终验收：S0–S11 全 13 步 PASS**（`R2_RESULT: PASS`，run3，重烧后；S0 方案 B adapter 生效、S6 ILA3 152b 双桥差分闭合、S9 J3 M/A/B 全 PASS、S10 recon PASS、S11 收尾 sticky=0） | [L2]（板端判据） | `R3D_S0-S11_run3.log`（`EC927EC6`）、`R2_20261019_164245.log`、ILA CSV 164245、`R2_4tier_20261019_164245.log`、`R2_mb10_20261019_164518.log`、`j3_fourchains_20261019_164540.log` |
| **S10 双桥对账：PASS**（mem/mem2 各 wm==wr_frm==rd_frm、ost=0、stall/len_err=0、wr_fault=0） | [L2]（板端判据；run2/run3） | `R2_COUNTER_RECON: PASS` + `R2_RECON_RESULT: PASS`（run2 L846-847、run3）；工具补丁记录 `tools/selfcheck.txt §10.9` |
| S9 对板卡起始态敏感：run2 残留态 NOT_OBTAINED、重烧后 run3 PASS（J3 纪律：残留态不重试） | [L2] | `j3_fourchains_20261019_164008.log`（FAIL M）vs `…164540.log`（PASS） |
