# R2 证据索引（prj11 路线 B / B3-2 桥①写侧换层 S2MM）— **round2c 位流已出/S0 PASS；round2d 板验初场：S1/S3 PASS、端到端未建立（未收口）**

- **状态（2026-10-18 14:5x，以磁盘为准）**：**round2c 成功位流已产出并钉 S0**。`ExtraTimingOpt` 过门限：**`V5_SWEEP2_OK` WNS=0.004 / WHS=0.004；DRC 0 Errors/22 Warnings；write_bitstream completed**。归档 `out\archive\b31b_r2_2026-10-18\`（**27 项清单 + `SHA256.txt`（28 文件）**，2026-10-18 14:53 升级版）：bit `aurora_mem_bridge_r2_28921C6B.bit`（10,266,180 B、`28921C6B…`）、ltx `probes_r2_28921C6B.ltx`（64,593 B、`4AC25546…`）、xsa `16A4F01F…`、ELF `1bc8088d`、RTL bridge blob `f43267db…`。**S0 离线 PASS**（`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`；xsa hash8 一致；日志 `evidence_2026-10-18\R2_20261018_144715.log`）。**板验 S1–S11 进行中（Lead 执行），本文件仍无板上结论。**
- **round2b/round2c ILA 裁剪判据边界**：ILA1@eth_rxc / ILA2@user_clk_b 整核移除；ILA0 probe0 374→92 bit（+probe1 9b 发射字节流不变）、ILA3 probe0 184→152 bit；裁掉 `dbg_mem_bresp/wslot/rslot` ⇒ **不可观测 = INFO/NOT_OBTAINED（判据未取得≠失败）**；S6/S10 不因缺 ILA1/2 报错；S8c 用 ILA0 probe1（9b）不变。详见 `R2_tools_README.md` §4.4。
- **round2d 板验初场（2026-10-18 16:3x–16:5x，未收口）**：board 实测 **S0/S1/S3 PASS**；S2/S3b 旧口径 FAIL 已定位为**判据建模错误**（`'U' wmwr`(+0x08)=`u_wr_frame` 收帧接受计数、非提交；良性丢帧使 `wmwr==wmrd` 在 R2 不可达）→ 工具已修正（新 S2=commit_len/fault；新 S3b=pending/fault 两拍）。**固件 `dread` 2读→3读修复**（候选 ELF `1e3a42db` 50,944 B）；修后 `'I'`=wr6/rd3、ILA `dbg_mem_wm=5/rd_frm=5/commit_len=86` ⇒ 写引擎可被服务 [L3]。**未收口 A[L1]**：高频 serve_any(~143kHz Lite 读)后 MB 挂死 `dread` lwi（`g_dbg_addr=0x44A00034`=lite_regs DMA_REQ 读），UART 静默/`rst -processor` 不恢复/只能重配 FPGA，1ms 限速非确定性 ⇒ 疑 SET_WRGO 写后紧接读竞争。**未收口 B**：`rd_frm` 增长但 ping 0/4、NIC `ReceivedBytes` delta=0（eth ILA 已裁，需补探针）。S4–S11 仍 PENDING；S6/S10 本轮 CSV 仅格式验证不入判据。触发式 ILA + 最小探针清单见 `R2_tools_README.md` §4.5/§4.6；会话记录 `evidence_2026-10-18\R2_board_session_20261018.md`。
- **等级边界**：S0 PASS 为**离线判据（`[L2]`）**；板验结论待 S1–S11（`[L3]/[L4]` 未取得）。归因性描述按 §6a 标等级。
- **用途**：R2 判决序列（S0–S11）的**唯一证据台账**——每条结论/判据指向哪个原始文件、SHA256 指纹、依据等级。模板仿 `evidence_2026-10-17\R1_evidence_index.md`。
- **写权限边界**：本文件只登记证据与状态，不产生结论；结论只在对应判据取得板上实测日志后填入并把等级从 `[待测]` 升到 `[L3]/[L4]`。本目录（`out\evidence_2026-10-17\`）为证据落盘区；**当轮日志目录按日期动态（`out\evidence_<yyyy-MM-dd>\`，round2c = `evidence_2026-10-18\`）**。
- **Hash 口径**：`Get-FileHash -LiteralPath <file> -Algorithm SHA256`；表中列**前 8 位**，关键产物给全量 64 位。**round2c 归档产物 hash 以 `out\archive\b31b_r2_2026-10-18\SHA256.txt` 为准**（round1 历史以 10-17 目录为准）；复算命令见 §8。
- **配套**：`out\evidence_2026-10-17\R2_tools_README.md`（工具链说明/判据分层/风险，v1.7）、`out\R2_S2MM_DESIGN.md`（v1.3）、`out\S0S8_DESIGN.md`（R1 判据口径）、`evidence_2026-10-17\R1_evidence_index.md`（R1 台账）、round2c 归档 `out\archive\b31b_r2_2026-10-18\{SHA256.txt, rpt2_ExtraTimingOpt.timing_summary.rpt}`、round1 历史 `out\archive\b31b_r2_2026-10-17\BUILD_STATUS.md`、**记录正文** `C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`（docs 镜像由 Lead 负责）。
- **证据产物命名约定**（工具已实现）：
  - 总控日志：`R2_<yyyyMMdd_HHmmss>.log`（UTF-8 BOM）
  - 四档：`R2_4tier_<ts>.log`；10MB：`R2_mb10_<ts>.log` + `R2_mb10_<ts>.recomposed.jsonl`
  - ILA：`R2_ila_<tag>_{ui,user}_{pre,post}.csv` + `R2_ilacap_vivado_<ts>.log`
  - J3：`j3_fourchains_<ts>.log` + `j3_{m,a,b}_<ts>.log`（`j3_fourchains.ps1` 产出）
  - 判定行：`[JUDGE] <step> PASS|FAIL|NOT_OBTAINED|SKIP` / `R2_RESULT:` / `R2_MB10_RESULT:` / `R2CAP_RESULT:` / `FOURCHAINS_RESULT:` / `R2_COUNTER_RECON:`

---

## 0. 使用规则（上板前必读）

1. **先跑 `out\r2_dryrun.ps1`** 确认工具链自证 7/7 PASS；再按 `R2_tools_README.md` §2.2 的 `-Run` 命令上板。**round2c 位流已就绪**（bit8 `28921c6b`），可直接按 §2.2 钉 S0 后由 Lead `-Run`；S0 已 dry-run PASS。
2. 只有拿到 **板上原始日志/CSV** 的条目才能从 PENDING 改为「已取值」；`NOT_OBTAINED` 必须写“判据未取得（实验无效）”，不得写成“通过/正常”。
3. 每条结论标注等级（AGENTS.md §6a）：`[L4]` 定案 / `[L3]` 板证实 / `[L2]` 对照成立 / `[L1]` 相容假说（**只允许出现在“假设”栏**）/ `[L0]` 猜测（禁止写入）。
4. 时间一律 Asia/Shanghai（UTC+8）；文件 hash 取登记时刻实测值（同名文件被覆盖时须重算并留轮次说明）。

---

## 0.1 场次结果（round1 失败 / round2b 裁剪 / **round2c 成功+S0 PASS**；离线证据 `[L2]`，板验进行中）

| 项 | 事实（证据落点） | 等级 |
|---|---|---|
| **构建结局** | **NO_BITSTREAM**：5 掷均被时序门限（WNS≥0 & WHS≥0）拒收，失败轮不写位流、不覆盖在库产物。轮次：`ExtraTimingOpt` 后布 −0.198→最终 **−0.098 / +0.004**；`Default`=`Opt 31-306` MIG 缝合瞬态（已知坑，不判设计）；`AggressiveExplore`=`[Common 17-69] Placer could not place all instances`（拥塞）；`WLDrivenBlockPlacement` 后布 −0.251→最终 **−0.225 / +0.004**；`ExtraPostPlacementOpt` 后布 −0.200→最终 **−0.175 / +0.004**。**权威落点**：`archive\b31b_r2_2026-10-17\BUILD_STATUS.md` §1；原始：`out\r2_sweep_console.log`（尾 `SWEEP_WLDrivenBlockPlacement: WNS=-0.225 WHS=0.004` + `V5_SWEEP_ALL_FAIL`）、`out\r2_sweep2_console.log`（尾 `SWEEP2_ExtraPostPlacementOpt: WNS=-0.175 WHS=0.004`） | **[L2]** |
| **综合** | **PASS**：`out\r2_synth.log` `Synthesis finished with 0 errors, 0 critical warnings and 743 warnings`（L1972）+ `SYNTH_ONLY_DONE`（L2170）；`pre_impl_debug.dcp` + ILA 四核（含 R2 新探针）OK（BUILD_STATUS §1） | **[L2]** |
| **失败诊断（Lead 直读报告）** | 30 条最差路径中 **25/30** = `u_mem/u_wr_bytes/wr_gray_s2_reg[3]` → `u_mem/u_bridge/g_wr_dma.wd_data_r_reg[*]/CE`（3.238ns，logic 1.405 / route 1.833=**56.6%**，slack −0.175ns；8 级 gray→decode 锥带 512 CE 负载）；**5/30** = 桥② 旧写 FSM 同族（`u_mem2/.../g_wr_hw.w_data_r_reg[*]`，R2 未改动）。落点：`R2_build_worst_paths_excerpt.txt` + `rpt2_ExtraPostPlacementOpt.worst.rpt`（archive 内，hash 见 SHA256.txt） | **[L2]** |
| **失败轮不覆盖在库产物** | `out\aurora_mem_bridge.bit` 仍为 R1 在库 `c8cd3a32`（9,746,300 B，mtime 10-17 21:28）；`out\mb_ctrl.xsa` 仍为 R1 `c9b52dd7`（21:29）；`out\probes.ltx` 不存在；R2 ILA 网表见 `out\probes_v5_ExtraTimingOpt.ltx`（失败轮） | **[L2]** |
| **板验** | **未执行**（用户 10-18 00:2x 要求收尾+断电；未烧/未开串口/JTAG/未 ping）⇒ **S0 依赖项 NOT_OBTAINED、S2–S11 全部 SKIP** | **[L2]** 过程事实 |
| **归档（失败轮）** | `out\archive\b31b_r2_2026-10-17\`：磁盘共 21 个文件（`SHA256.txt` 登记 20 项，`BUILD_STATUS.md` 在清单内）；`SHA256.txt` 2,488 B `041db3f1…`、`BUILD_STATUS.md` 4,100 B `EA9E7BC4…`；**注意 `aurora_mem_bridge_r1_in_service_c8cd3a32.bit` 是 R1 参照、不是 R2 产物** | **[L2]** |
| **下次开工** | 先按 `BUILD_STATUS.md` §3 主修时序：新写引擎 `g_wr_dma` 字节捕获加 **1 级流水**（`byte_q`/`byte_valid_q`，吞吐不变；不动 `HAS_DMA=0`），备选：裁 ILA3 低价值探针重综合 / 追加 place 指令取方差 / 单掷 `build_debug.tcl` | **[L2]** 建议 |
| **round2（2026-10-18）** | 综合后 place/route **首掷 WNS 仍 −0.135**（拥塞/资源密度主因；`AggressiveExplore` 布局失败）。原始日志：`out\r2b_synth*.log`/`out\r2c_synth*.log`/`out\r2c_sweep2*`（以磁盘为准），`out\r2c_sweep2_console.log` 12:49。 | **[L2]**（Lead 通知 + 日志） |
| **round2b（2026-10-18 12:5x）** | **不改 RTL、裁 ILA 探针省资源**后重综合。裁剪（以 `build_synth_only.tcl`/`build_debug.tcl` 12:49 版为准）：ILA1@eth_rxc/ILA2@user_clk_b **整核移除**；ILA0 probe0 374→**92 bit**（probe1 9b 保留）；ILA3 probe0 184→**152 bit**；裁掉 `dbg_mem_bresp/wslot/rslot`。**判据边界=缺失探针列 INFO/NOT_OBTAINED**。 | **[L2]** |
| **round2c 构建（2026-10-18 14:4x，通过）** | **过门限**：`SWEEP2_ExtraTimingOpt: WNS=0.004 WHS=0.004`（`build_r2_sweep2.log` L2659）+ `V5_SWEEP2_OK: directive=ExtraTimingOpt wns=0.004 whs=0.004 bit=...`（L2764）；DRC `0 Errors, 22 Warnings`；`write_bitstream completed successfully`。综合 `Synthesis finished with 0 errors, 1 critical warnings and 718 warnings`（1 critical = `Synth 8-3321 create_generated_clock` aurora IP 既有族）。归档 `out\archive\b31b_r2_2026-10-18\`（**27 项清单 + SHA256.txt（28 文件）**，14:53 升级版）；时序摘要 `rpt2_ExtraTimingOpt.timing_summary.rpt` 另见 WNS 0.042/WHS 0.004（报告口径；门限行以 `V5_SWEEP2_OK` 的 0.004 为准）。 | **[L2]** |
| **round2d 板验初场（2026-10-18 16:3x，未收口）** | S0/S1/S3 PASS；固件缺陷修复（dread 3 读，候选 ELF `1e3a42db`）；修后服务证据 `'I'`=wr6/rd3 + ILA wm=5/rd_frm=5/commit_len=86；未收口 A（AXI 楔死 [L1]，高频 serve 后 MB 挂 dread lwi `g_dbg_addr=0x44A00034`）/B（TX 无帧：rd_frm 增但 ping 0/4、NIC delta=0）；证据 `evidence_2026-10-18\R2_board_session_20261018.md`、`r2_board_run2_20261018.log`、`R2_ila_r2_20261018_163530_*.csv` | **[L2]/[L3]**（含 [L1] 假说） |
| **round2c 身份（已核）** | bit `aurora_mem_bridge_r2_28921C6B.bit` 10,266,180 B / `28921C6B38BE92447950B8C81405F278945529BB007E94461EC2CEEF0D324627`（bit8 `28921c6b`）；ltx `probes_r2_28921C6B.ltx` 64,593 B / `4AC2554667F94BC3E052E0A652FF2DE322E2CE51FEE2B47399A108DF9E6B7C33`（实测仅 `u_ila_0`/`u_ila_3`；ILA0 92+9b、ILA3 152b；bresp/wslot/rslot 不存在）；xsa `mb_ctrl_r2.xsa` 2,606,995 B / `16A4F01F51AF9665B4C79686812FEAA353C3CF8C27C8BC3C47DA1EC7D28EC59E`；ELF `1bc8088d` 50,896 B；RTL bridge blob 实测 `f43267db82b84305cfeb519adcfa76f79443f6b3`（ARM 时序修复版，升级版清单头已更正）；**归档清单 14:53 升级为 27 项（3,243 B、`73fb1aae…`，新增 BUILD_STATUS/congestion_iter_3/4/diag_arm_path_probe）**。 | **[L2]** |
| **S0 离线判据（已取得）** | `r2_board.ps1` dry-run（未碰板）：`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`；xsa hash8 `16a4f01f` 与期望一致 ✓；ILA ltx exists=True；GUARD 全 0；`R2_RESULT: SKIP (dry-run)`。日志：`evidence_2026-10-18\R2_20261018_144715.log`（19,977 B、`ef05a653…`）。**关键修复**：`r2_board.ps1` okMarker 曾不识别 `V5_SWEEP2_OK`（会误判 S0 FAIL），Lead 已修；script-tools 复验 BOM+ParseFile 并补 round2c 常量（新 hash 见 §5）。 | **[L2]** |
| **板验 round2d 初场（2026-10-18 16:3x–16:5x，未收口）** | board 实测 **S0 PASS、S1 PASS、S3 PASS**；S2/S3b 旧口径 FAIL 属判据建模错误（已修）；固件 `dread` 2→3 读修复（候选 ELF `1e3a42db` 50,944 B），修后 `'I'`=wr6/rd3、ILA `dbg_mem_wm=5/rd_frm=5/commit_len=86` ⇒ 写引擎可被服务 [L3]。**A（AXI 楔死）[L1]**：高频 serve_any 后 MB 挂死 `dread` lwi（`g_dbg_addr=0x44A00034`），UART 静默/rst-processor 不恢复/只能重配 FPGA；**B（TX 无帧）**：`rd_frm` 增长但 ping 0/4、NIC delta=0（eth ILA 已裁需补探针）。S4–S11 PENDING；本轮 CSV 仅格式验证。 | **PENDING（未收口）** |

---

## 1. 结论 → 证据映射（**S0 已取得；S1–S11 板验进行中**）

> 判据定义见 `R2_tools_README.md` §3（S0–S11）。下表“支撑证据”列给出**预期落点**；本轮（round2c 位流已出、S0 已取得；S1–S11 板验进行中）实际状态见第 5 列。

| # | 判据 | 支撑证据（预期落点） | 等级 | 取值状态 |
|---|---|---|---|---|
| **C0** | S0 工件身份：R2 位流/ELF SHA256、构建日志 WNS/WHS≥0、DRC 0、xsa hash | `R2_<ts>.log` S0 段；`out\archive\b31b_r2_2026-10-17\{aurora_mem_bridge_r2_<bit8>.bit, j3_soft_r2_1bc8088d.elf, build_r2_sweep.log, build_r2_synth.log, mb_ctrl_r2.xsa, probes_r2_<bit8>.ltx, SHA256.txt}` | **[L2]** | **已取得 [L2]（S0 离线 PASS）**：`WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`；xsa hash8 `16a4f01f` 一致；日志 `evidence_2026-10-18\R2_20261018_144715.log`（详见 §0.1） |
| **C1** | S1 在位配置记录（R1 修复版在位对 + 只读快照） | `R2_<ts>.log` S1 段（在位记录、`'U'`/`'L'`/邻居/ping1 只读快照） | **[L3]** | **已取得（S1 PASS）**：run2 只读记录完成（mode=0/req=0/wmwr=7，邻居 Permanent，ping 0/1 仅记录） |
| **C2** | S2 位流身份原位判据（round2d 新口径）：未发 `'d'` 时 ping 0/1 + NIC `ReceivedBytes` delta=0 + **`WR_DBG.last_commit_len==0`** + fault=0（wmwr delta 仅 INFO） | `R2_<ts>.log` S2 段（`[JUDGE] S2 PASS`、`[B2] U req/wreq/wdbg/s2sr` 原始行、NIC 前后读数） | **[待测]** | **PENDING**：旧口径作废（判据建模错误已修正）；待候选 ELF+新口径复跑 |
| **C3** | S3 DMA 服务+写路径启动：mode=1 & `req.bit24=1`、`WR_DBG.fault=0`、s2sr 现场值；S3b 静默窗（round2d 新口径：pending==0 & fault==0 两拍） | `R2_<ts>.log` S3/S3b 段 | **[L3]/[待测]** | **S3 已取得 [L3]**（run2 PASS：mode=1 & bit24=1）；**S3b 待新口径复跑** |
| **C4** | S4 单帧端到端：ping 1/1 + `ReceivedBytes`≥74 + `WM_WR+1` & `WM_RD+1`；s2sr/emit(len_tab=86) 现场 | `R2_<ts>.log` S4 段（`[JUDGE] S4`、s2sr、emit 解码、NIC 读数） | **[待测]** | **PENDING**：板验进行中（S4 待执行） |
| **C5** | S5 ping×4：4/4 + `ReceivedBytes`≥296 + `WM_WR/WM_RD` 各 +4 | `R2_<ts>.log` S5 段 | **[待测]** | **PENDING**：板验进行中（S5 待执行） |
| **C6** | S6 桥级 ILA：桥② `dbg_mem2_rd_frm` +4 且 `ost` 前后 0；桥① `wm/wr_frm/rd_frm` 各 +4 且 `ost` 前后 0 | `R2_ila_<tag>_{ui,user}_{pre,post}.csv` + `R2_ilacap_vivado_<ts>.log` + `r2_counter_recon.py --mode delta` 输出（`R2_ILA_DELTA:` 行） | **[待测]** | **PENDING**：板验进行中（S6 待执行；round2c ltx 已归档、裁剪后口径） |
| **C7** | S7 四档零回归：`DDR_VERIFY: PASS`（20/20·12/12·12/12·300/300） | `R2_4tier_<ts>.log`；`R2_<ts>.log` S7 段 | **[待测]** | **PENDING**：板验进行中（S7 待执行） |
| **C8** | S8 10MB 100%+SHA：`lost==0 & corrupt==0 & sha_match==true & recv==chunks`；独立 SHA 复算一致 | `R2_mb10_<ts>.log` + `R2_mb10_<ts>.recomposed.jsonl`；`R2_<ts>.log` S8 段 | **[待测]** | **PENDING**：板验进行中（S8 待执行） |
| **C9** | S9 J3 四链（带 `--dma`）：`FOURCHAINS_RESULT: PASS`（M/A/B）；规则号 1 等价性数据（逆序对/缺失字节） | `j3_fourchains_<ts>.log` + `j3_{m,a,b}_<ts>.log`；`R2_<ts>.log` S9 段 | **[待测]** | **PENDING**：板验进行中（S9 待执行） |
| **C10** | S10 双桥计数对账闭合（J4 口径）：mem/mem2 各自 `wm==wr_frm==rd_frm`、`ost=0`；错误计数按可观测项（mem `len_err/stall`、`dbg_wr_fault`；mem2 无探针记 INFO） | `r2_counter_recon.py --mode recon` 输出（`R2_COUNTER_RECON:` 行）；post CSV 同上 | **[待测]** | **PENDING**：板验进行中（S10 待执行） |
| **C11** | S11 收尾恢复：`Set-EngineMode` 后 mode/`bit24` 符合目标 | `R2_<ts>.log` S11 段 | **[待测]** | **PENDING**：板验进行中（S11 待执行） |
| **C12** | 风险假设（**只允许写“假设”栏**）：S2MM 尾拍 TKEEP→WSTRB 与旧 AXI WSTRB 逐位等价（`[L1]`）；IOC 退休时刻与旧 BRESP 等价（`[L1]`） | S4（len_tab=86 覆盖尾拍）+ S6 ILA（`dbg_s2mm_state/tvalid/tready`、`dbg_wr_fault`）+ S7/S8/S9 字节级判据；若 byte-level FAIL 而 ping 通 ⇒ 判据日志 `TKEEP_SUSPECT` | **假设 [L1]** | PENDING（未板验；需 S4/S6/S7/S8/S9 联合取值后按 §6a 重标） |

> **PASS 的前提**：S0 通过 + 各步判定行齐；任一 `FAIL/NOT_OBTAINED` 都要在此表标“未取得/未通过”并写清原因，不得合并成“总体通过”。**目前仅 S0 取得（离线），不得写成“总体通过”。**

---

## 2. 板级原始证据（**round2c 板验进行中**；下列为模板，取得后逐文件登记）

> round2c 板验（S1–S11）进行中，本文件尚未登记板上原始证据；**S0 离线 PASS 日志不算板证**。口径同 R1：按“时间 / 大小 / SHA256前8 / 支撑什么 / 等级 / 备注”登记；无效实验单独成表并标“无效留痕”。

### 2.1 有效轮（可直接作判据）— 待填

| 文件 | 时间/大小 | SHA256前8 | 支撑什么 | 等级 | 备注 |
|---|---|---|---|---|---|
| （PENDING）`R2_<ts>.log` | — | — | S0–S11 总控 | [待测] | — |
| （PENDING）`R2_4tier_<ts>.log` | — | — | C7 | [待测] | — |
| （PENDING）`R2_mb10_<ts>.log` + `.recomposed.jsonl` | — | — | C8 | [待测] | — |
| （PENDING）`R2_ila_*_{ui,user}_{pre,post}.csv` + `R2_ilacap_vivado_<ts>.log` | — | — | C6/C10 | [待测] | — |
| （PENDING）`j3_fourchains_<ts>.log` + `j3_{m,a,b}_<ts>.log` | — | — | C9 | [待测] | — |

### 2.2 无效/失效实验（**不得作为结论证据**）— 待填

| 文件 | 时间/大小 | SHA256前8 | 为什么无效 | 留痕价值 |
|---|---|---|---|---|
| （PENDING） | — | — | — | — |

### 2.3 离线分析/审计（非板上证据）— 待填

| 文件 | 时间/大小 | SHA256前8 | 内容与使用边界 |
|---|---|---|---|
| （PENDING） | — | — | — |

---

## 3. 构建产物 hash（**round2c 成功位流已产出；归档 hash 以 `archive\b31b_r2_2026-10-18\SHA256.txt` 为准**）

> round2c 归档（成功轮）：`out\archive\b31b_r2_2026-10-18\`（**27 项清单 + `SHA256.txt`（28 文件）**，清单 2026-10-18 14:53 升级版）。**默认名产物 `out\aurora_mem_bridge.bit` 会被下次构建覆盖（round2c 后它= `28921c6b`，10-18 14:43），判据只认归档绝对路径 + 实算 hash。**

| 产物 | 文件名/路径 | 大小 | SHA256 前 8 | SHA256 全量 | 状态 |
|---|---|---|---|---|---|
| **R2 位流（成功）** | `archive\b31b_r2_2026-10-18\aurora_mem_bridge_r2_28921C6B.bit` | **10,266,180 B** | **`28921c6b`** | `28921c6b38be92447950b8c81405f278945529bb007e94461ec2ceef0d324627` | **PASS（过门限）**：`V5_SWEEP2_OK wns=0.004 whs=0.004`；DRC 0E/22W；write_bitstream 成功；`-ExpectBitHash8 28921C6B` |
| **R2 探针 ltx** | `archive\b31b_r2_2026-10-18\probes_r2_28921C6B.ltx` | **64,593 B** | **`4ac25546`** | `4ac2554667f94bc3e052e0a652ff2de322e2ce51fee2b47399a108df9e6b7c33` | round2b 裁剪版；实测仅 `u_ila_0`/`u_ila_3`；ILA0 probe0 92b + probe1 9b；ILA3 152b；`-IlaLtx` 用此文件 |
| **R2 xsa** | `archive\b31b_r2_2026-10-18\mb_ctrl_r2.xsa` | **2,606,995 B** | **`16a4f01f`** | `16a4f01f51af9665b4c79686812feaa353c3cf8c27c8bc3c47da1ec7d28ec59e` | `-ExpectXsaHash8 16A4F01F`；S0 dry-run 已核对一致 |
| ELF（最终冻结） | `archive\b31b_r2_2026-10-18\j3_soft_r2_1bc8088d.elf` | **50,896 B** | **`1bc8088d`** | `1bc8088dc48d42bbf40aec76fdfb69b96ce9b187cfaf6dbd022e285b921bd42a` | **最终冻结**；blob `ee256c05`；`-ExpectElfHash8 1BC8088D`；round2c 未变 | **round2d 候选 ELF `1e3a42db`（50,944 B，修 dread 3 读）尚未归档；旧 `1bc8088d` 有 Lite 读滞后缺陷，仅历史。** |
| RTL blob（round2c） | `archive\...\rtl_axi4_master_bridge.v` | **68,296 B** | `b64300b4`（文件 SHA256） | `b64300b416c8f50c88a8726fc80953377a9c9c9375abfcd4632ec19976be6897` | **git blob 实测 `f43267db82b84305cfeb519adcfa76f79443f6b3`**（ARM 时序修复版；**升级版清单头已更正为 `f43267db`**，笔误已修） |
| 综合日志（round2c） | `archive\...\build_r2_synth.log` / `_console.log` | 181,651 B / 182,976 B | `14f1dd74` / `142fef6c` | `14f1dd74d0a9a2fab12f3e545b46f6d4d16af1146277269b525d72aeae357020` / `142fef6c9c7cdE6D688645A5403843E6494B819F661B6108B0E2FE5CE694CB78` | `0 errors, 1 critical warnings, 718 warnings` + `SYNTH_ONLY_DONE`（1 critical = `Synth 8-3321` aurora IP 既有族） |
| 实现扫描（round2c，PASS） | `archive\...\build_r2_sweep2.log` / `_console.log` | 318,807 B / 321,242 B | `062d9091` / `5d141a67` | `062d9091eb11408fe1dbbd7b55aaca406492163babf8906728427417e7540422` / `5d141a678b57f60e108b47d870185c164985b872a17b9dfe15060663c1ebcb9c` | `SWEEP2_ExtraTimingOpt: WNS=0.004 WHS=0.004`（L2659）+ `V5_SWEEP2_OK ...`（L2764）+ DRC 0E/22W + write_bitstream 成功 |
| 时序报告（round2c） | `archive\...\rpt2_ExtraTimingOpt.timing_summary.rpt` | 8,142,267 B | `cb10118f` | `cb10118ff2522ca985456e11cd11b16da00ce7bda44c64f8b58b2c38aee54aa6` | 报告口径 WNS 0.042 / WHS 0.004（均 ≥0；门限行以 `V5_SWEEP2_OK` 的 0.004 为准） |
| 其它 round2c 报告 | `rpt2_ExtraTimingOpt.worst.rpt` / `.util.rpt` | 235,040 / 15,755 B | `9690380a` / `5570bae6` | 见 `SHA256.txt` | 已归档 |
| 归档清单（round2c，27 项） | `archive\...\SHA256.txt` | **3,243 B** | **`73fb1aae`** | `73fb1aaebd81879f9c1e80c9ecbcef36d0ca9c604669f56ccac1201259ebe9b5` | **27 项逐文件 hash 权威清单（+ 清单自身）**；清单自身 hash 以磁盘复算为准（Lead 稍后发最终值） |
| 归档新增证据（14:53 升级版） | `BUILD_STATUS.md` / `congestion_iter_3.txt` / `congestion_iter_4.txt` / `diag_arm_path_probe.tcl` | 3,656 / 16,497 / 12,603 / 675 B | `3e038904` / `6a1d9459` / `871a9638` / `a3151b6b` | 见 `SHA256.txt` 对应行 | round2c 构建/修复状态 + 拥塞证据 + ARM 关键路径逐级探针脚本 |

**round1 历史（失败轮，`archive\b31b_r2_2026-10-17\`，保留）**：位流 NO_BITSTREAM；`SHA256.txt` `041db3f1…`；`BUILD_STATUS.md` `ea9e7bc4…`；`build_r2_sweep2.log` 尾 `SWEEP2_ExtraPostPlacementOpt: WNS=-0.175 WHS=0.004`；诊断 worst rpt `ea05cc30…`（25/30 新写引擎 CE 锥 + 5/30 桥② 旧 FSM）。R1 在库参照 `c8cd3a32…` 仅存于该历史归档。

> RTL blob 指纹：round2c 以实测 `git hash-object rtl_axi4_master_bridge.v = f43267db…` 为准；其余三文件与 round1 相同（`0CB4B68E…`/`2084AA11…`/`11CB53AD…`）。

---

## 4. 离线回归 / 构建验证（本轮 `[L2]` 事实，非板上回归）

| 项 | 判据 | 落点 | 状态 |
|---|---|---|---|
| **dry-run 工具链自证** | `r2_dryrun.ps1` 7/7 PASS（BOM+ParseFile/py_compile/正负自检/Tcl 结构+ASCII/两脚本 dry-run/只读纪律） | `out\r2_dryrun.log` | **已取值 [L2]（2026-10-18 12:52，v1.6 round2b 重跑）** |
| **综合** | 0 errors / 0 critical warnings；`SYNTH_ONLY_DONE`；pre_impl_debug.dcp + ILA 四核 OK | `out\r2_synth.log`（`ef7025a1…`） | **PASS [L2]** |
| **实现扫描（时序门限）** | WNS≥0 & WHS≥0 才写位流 | `out\r2_sweep_console.log` / `out\r2_sweep2_console.log` | **FAIL [L2]：NO_BITSTREAM（5 掷全败；最好 −0.098，sweep2 −0.175）** |
| **失败诊断** | 最差路径族定位 | `rpt2_ExtraPostPlacementOpt.worst.rpt` / `R2_build_worst_paths_excerpt.txt` | **已取值 [L2]**（25/30 新写引擎 CE；5/30 桥② 旧 FSM） |
| **round2 / round2b 时序攻坚** | round2 place/route 首掷 WNS −0.135（`AggressiveExplore` 布局失败）⇒ 裁 ILA 后重综合 | `out\r2b_synth*.log`/`out\r2c_synth*.log`/`out\r2c_sweep2*.log`/`out\r2d_synth*.log`（以磁盘为准） | **[L2] 完成（round2c 通过）** |
| **round2c 构建（PASS）** | `V5_SWEEP2_OK` WNS=0.004/WHS=0.004；DRC 0E/22W；write_bitstream 成功；综合 0 errors/1 critical（aurora IP 既有 `Synth 8-3321`）/718 warnings | `archive\b31b_r2_2026-10-18\{build_r2_sweep2.log,build_r2_synth.log,rpt2_ExtraTimingOpt.timing_summary.rpt}` | **已取值 [L2]** |
| R2 WR TB（S2MM 流模型 + 规则号 1 golden model） | TB PASS + 字节逐字节 | 见 `evidence_2026-10-17\R2_rtl_audit.md`（rtl-auditor 台账；本索引**只引用不自判**） | PENDING（引用审计报告，待其定稿落行） |
| 负向对照（游标不推进 / 尾拍 TKEEP 满 lane 缺陷副本） | 必须 FAIL 且指认具体判据行（坑 #43） | 同上 | PENDING（引用审计报告） |
| `mem_bridge_tb`（HAS_DMA=0）/ `w4_joint_tb`（HAS_DMA=0）回归 | PASS 且计数与 R1 基线逐字一致（坑 #55） | `sim\` 日志（D5：这两项纯 tie 即可） | PENDING（引用审计报告） |
| `bridge_dma_tb`（HAS_DMA=1） | D5：写路径契约已变，审计补"最小 S2MM 服务模型"后复跑 | 同上 | PENDING（引用审计报告） |
| 单模块 OOC 综合（axi4_master_bridge / frame_mem_if） | 通过（坑 #27 纪律） | 综合日志 | PENDING |
| 既有 CI | 本地 `scripts\ci_check.py` 退出码 0；提交后远端 CI 为准 | `out\evidence_2026-10-17\` 日志 | 本地 PASS（未提交，待远端） |

---

## 5. 工具清单（**只登记，不产生结论**）

| 工具 | 作用 | SHA256 前 8 | 状态/边界 |
|---|---|---|---|
| `out\r2_board.ps1` | S0–S11 总控（dry-run 默认；round2d S2/S3b 口径修正+触发 ILA 支持） | `f92666f5` | 已交付（v1.9/round2d）；S0 已 PASS，板验待候选 ELF 复跑 |
| `out\r2_ilacap.tcl` | ILA PRE/POST 快照（纯 ASCII、env 参数化；新增 `R2_TRIGGER_*`） | `9fda27ba` | 已交付（round2d 触发式抓取） |
| `out\r2_counter_recon.py` | 双桥对账/差分/正负自检/Tcl 结构+ASCII 检查/s2mm_state 解码/round2b 裁列 INFO | `c4aa2c3a` | 已交付；自检 5/5（含 round2b 裁列合成用例） |
| `out\r2_mb10_sha.ps1` | 10MB 质量档 + SHA 独立复算 | `8836a046` | 已交付（证据目录动态） |
| `out\r2_dryrun.ps1` | dry-run 自证一键复现 | `b65f047a` | 已交付 |
| `out\evidence_2026-10-17\R2_tools_README.md` | 工具链/判据分层/风险说明（v1.9） | `cb8ec5f2` | 已交付（round2d 已同步） |
| R1 只读复用 | `retire_s0_s8.ps1` / `j3_fourchains.ps1` / `uart_probe.py` / `manual_round.py` / `jb31b_burn_pair.tcl` / `jb31b_rdcap2_cmp.py` 等 | 见 R1 台账 | **只读，未改动**（`r2_dryrun.log` §7 hash 前后一致） |
| 数据面脚本（只读） | `prj\project_9\scripts\json_storm.py`（10MB 默认参数）、`prj\project_10\prj_loop\scripts\udp_verify_ddr.py`（四档） | 见各自仓库 | 只读引用 |

> 完整 SHA256 全量、7/7 自证明细见 `R2_tools_README.md` §1/§7。

---

## 6. 口径留痕 / 需更正项（上板前已定口径，非结论）

1. **NIC 主判据 = `ReceivedBytes`**：静态 ARP 下板自发帧 dst=广播 ⇒ `ReceivedUnicast` 恒 0（R1 `[L3]`）。S4≥74B / S5≥296B。
2. **`'d'` 是翻转命令**：一律 `Set-EngineMode` 双重回读确认；S2 身份判据前提是**不发 `'d'`**。
3. **J3 = 带 `--dma`、nslots=256、失败不重试**；`wr+255`/收帧停摆/`WAITWR-FAIL` ⇒ 判据未取得 + 板卡需重烧；失败现场先查 `WR_DBG.fault`（fault=1 = fail-stop 进 `WD_HALT(6)`；唯一出口 = 软核恢复序列 `S2MM_DMACR=0x4(reset)→等 Halted=1→0x1001(RS+IOC)→清 IOC→写 +0x4C(opcode 0x06) 翻 ACK`，PC 只读不写；否则重烧）。
4. **桥② 不加错误计数 ILA 探针**（R2 未动桥②；省 300MHz ILA 余量）：S10 对桥② 只硬判三计数 + `ost=0`；桥① 错误硬判 `len_err/stall` + `dbg_wr_fault`；桥① `bresp` **恒 0 仅 INFO**（S2MM 写路径 IP 内部 BRESP 不可见）；桥② `stall/len_err/bresp` 无 ILA 探针 ⇒ INFO（不可观测）。
5. **s2sr**：默认只 WARN 看原始值；`-StrictS2sr` 复跑时硬判；**Halted 期望=0**（Halted=1 ⇒ S2MM 通道没起来，现场重要线索）。
6. **timeout 计数上板不可观测**：`dbg_wr_timeout` 未挂 ILA（有意省 300MHz ILA3 余量；R1/W6：300MHz 加 96b 曾 WNS -1.142）+ `stat_wr_timeout` 无 Lite 读回路径（不在 `+0x40/+0x44`）⇒ recon 记 INFO，不硬判。**可观测替代物（INFO）**：ILA3 `dbg_s2mm_state` 编码 **0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT** + ILA0 `dbg_wr_fault` + `'U'` 的 `wreq/wdbg/s2sr` + `ro_wm` 是否推进。
6b. **异常/超时口径（DESIGN v1.2 §13/§14，审计 A3–A6）**：四类看门狗统一 **24b `0xFFFFFF`≈56ms@300MHz**（旧 WAITDONE `2^25`≈112ms **作废**）。**WAITGO 超时=良性丢帧**（pending=0/`stat_wr_timeout++`/不置 fault/不停泊；S2b 身份判据依赖该行为；陈旧 GO 窗口由固件“写 LENGTH/翻 GO 前二次确认 pending&&toggle”兜底）⇒ S2 的 `pending` 只有 ~56ms 窗口内可能为 1，隔久读到 0 属预期（仅 INFO）。**STREAM/PUSH/WAITDONE 超时=fail-stop**（fault=1→WD_HALT(6)，不 commit）。
6c. **D8/A11：桥① `ro_lat_w` 恒 0**（写口退役；B3-0 口径只对桥②/HAS_DMA=0 有意义）⇒ **禁止**用 GET_LATENCY 的桥① 值做判据。**A12**：`WR_DBG.last_alloc_slot`=最近**分配**槽号、`last_commit_len`=最近**提交**帧长（分配≠提交）。**D4/A9**：离线 TB 只证 DUT 输出流，不证厂商 IP 的 TKEEP→WSTRB/IOC（归板验 S4 后升 L3）。**A3/G2**：STREAM/PUSH 看门狗分支离线未触发（结构 `[L1]`，板验靠 state=6/HALT+fault 承接）。
7. **10MB 质量档 = json_storm 源码默认**（chunk=1466B、gap-ms=1.0ms；**不传 `--pace-us`**）；判据字段 + PowerShell 独立 SHA 复算。
8. **S10 默认复用 S6 post CSV**（cumulative 静默后口径）；J3 后不复跑 ping。
9. **round1 构建 NO_BITSTREAM（历史 `[L2]`）**：无 R2 位流 ⇒ 当时 S0 依赖项 NOT_OBTAINED、S2–S11 SKIP；失败轮不写位流、不覆盖在库产物；失败轮 ILA 网表 `out\probes_v5_ExtraTimingOpt.ltx` 仅核对探针名；诊断/修复建议见 `archive\b31b_r2_2026-10-17\BUILD_STATUS.md`（round2c 已通过，见 §0.1）。
10. **round2b/round2c ILA 探针集裁剪（`[L2]`，判据边界，已进入 round2c 位流）**：ILA1@eth_rxc / ILA2@user_clk_b **整核移除**；ILA0 probe0 374→92 bit（probe1 9b 保留）；ILA3 probe0 184→152 bit；裁掉 `dbg_mem_bresp`/`dbg_mem_wslot`/`dbg_mem_rslot` ⇒ **不可观测 = INFO/NOT_OBTAINED（判据未取得≠失败）**；**S6/S10 不因缺 ILA1/2 报错**；S10 仍硬判桥① ui `wm/wr_frm/rd_frm/stall/len_err/ost` + 桥② ui 四计数（`ost=0`）+ `dbg_wr_fault`；S8c 用 ILA0 probe1（9b）不变。round2c ltx 实测仅 `u_ila_0`/`u_ila_3`。recon 对裁列缺失不判 FAIL（selftest 覆盖）。
11. **S0 PASS（离线）≠ 板验通过**：S0 只核对工件身份/SHA256/WNS/WHS/DRC/okMarker（`[L2]`）；S1–S11 板验进行中，结论未取得前不得写“总体通过”。RTL blob 实测 `f43267db…`（ARM 时序修复版）；**升级版 `SHA256.txt`（14:53，27 项）头部已更正为 `f43267db`**（旧笔误 `06e6bd72` 已修，R19 关闭）；清单自身 3,243 B、`73fb1aae…`（以磁盘复算为准）。
12. **round2c 门限行口径**：构建门限以 `build_r2_sweep2.log` 的 `V5_SWEEP2_OK: ... wns=0.004 whs=0.004` 为准；同归档 `rpt2_ExtraTimingOpt.timing_summary.rpt` 报告口径为 WNS 0.042/WHS 0.004（两者均 ≥0，差异属报告设置/阶段不同，不改变 PASS）。
13. **round2d S2/S3b 判据修正（[L2] RTL+板证）**：`'U' wmwr`(+0x08)=`u_wr_frame` 是**收帧接受计数**（`frame_mem_if.v` 在帧接受时即+1，早于 commit；`axi_lite_regs.v` L16/70/464），R2 未服务阶段每来一帧都会+1 且被 WAITGO 良性丢弃 ⇒ 旧 S2 的 `wmwr delta=0` 必假 FAIL；**新 S2 硬判**=ping 0/1 + NIC Bytes delta=0 + `WR_DBG.last_commit_len==0` + fault==0。同理良性丢帧使 `u_wr_frame` 永久多计 ⇒ **旧 S3b 的 `wmwr==wmrd` 不可达**；**新 S3b**=pending==0 && fault==0（& bit25=0）连续两拍，wmwr/wmrd/backlog 仅 INFO；S9 J3 前置同步换口径。
14. **round2d 未收口 A/B（不得写成通过）**：A=AXI 总线楔死（[L1] 假说：高频 serve_any ~143kHz Lite 读后 MB 挂死在 dread volatile load `lwi`，PC/标记定位 `g_dbg_addr=0x44A00034`=lite_regs DMA_REQ 读；UART 静默/`rst -processor` 不恢复/只能重配 FPGA；1ms 限速非确定性；疑 SET_WRGO 写后紧接读握手竞争）——待按 `R2_tools_README.md` §4.6 加探针 + §4.5 触发式 ILA 复现；B=TX 无帧（`rd_frm` 增长但 ping 0/4、NIC Bytes delta=0；eth ILA 已裁需补探针）。二者均未取得判据 ⇒ S4–S11 PENDING，本轮 S6/S10 CSV 只作格式/探针验证。

> 更正记录（上板后用）：`（PENDING：若正文/记录与原始日志矛盾，在此登记“补记/更正”，保留原数字与出处）`

---

## 7. PENDING 台账（上板执行清单；**本轮状态已置为未取得/等下一次**）

| 待产生证据 | 预期落点 | 负责人 | 状态 |
|---|---|---|---|
| R2 位流 hash（bit8） | `out\archive\b31b_r2_2026-10-18\aurora_mem_bridge_r2_28921C6B.bit` | Lead | **已取得 [L2]（round2c）：`28921c6b`，10,266,180 B；S0 dry-run PASS** |
| xsa hash | `out\archive\b31b_r2_2026-10-18\mb_ctrl_r2.xsa` | Lead | **已取得 [L2]（round2c）：`16a4f01f`，2,606,995 B** |
| 探针 ltx hash | `out\archive\b31b_r2_2026-10-18\probes_r2_28921C6B.ltx` | Lead | **已取得 [L2]（round2c）：`4ac25546`，64,593 B（实测仅 u_ila_0/u_ila_3）** |
| 构建日志（synth/sweep2） | `archive\b31b_r2_2026-10-18\build_r2_{synth,sweep2}.log` + `_console.log` | Lead | **已取得 [L2]（round2c PASS；`V5_SWEEP2_OK`；hash 见 §3）** |
| 归档 `SHA256.txt` | `out\archive\b31b_r2_2026-10-18\` | Lead | **已完成 [L2]（round2c，14:53 升级版：3,243 B，27 项，`73fb1aae…`；新增 BUILD_STATUS/congestion/diag）** |
| 构建状态/诊断 | round2c `rpt2_ExtraTimingOpt.timing_summary.rpt`/worst/util；round1 `BUILD_STATUS.md`（历史） | Lead | **已完成 [L2]** |
| S0–S11 原始日志 | `R2_<ts>.log`（UTF-8 BOM） | Lead | **S0 已取得（`evidence_2026-10-18\R2_20261018_144715.log`，dry-run PASS）；S1–S11 板验进行中** |
| S6 ILA CSV ×4 + vivado 日志 | `R2_ila_<tag>_*_{pre,post}.csv` + `R2_ilacap_vivado_<ts>.log` | Lead（`-IlaCapture` 自动） | **PENDING（板验进行中，S6 待执行）** |
| S7 四档日志 | `R2_4tier_<ts>.log` | Lead | **PENDING（板验进行中，S7 待执行）** |
| S8 10MB 日志 + 重组文件 | `R2_mb10_<ts>.log` + `.recomposed.jsonl` | Lead | **PENDING（板验进行中，S8 待执行）** |
| S9 J3 日志（M/A/B） | `j3_fourchains_<ts>.log` + `j3_{m,a,b}_<ts>.log` | Lead | **PENDING（板验进行中，S9 待执行）** |
| R2 WR TB / 负向对照日志 | `prj\project_11\sim\`（rtl-auditor 归档处） | rtl-auditor/Lead | PENDING（引用 `R2_rtl_audit.md`，不自行判定） |
| 失败现场（如有）分析 | 本轮无板级失败现场；构建失败诊断见 BUILD_STATUS.md | Lead | **已完成 [L2]（构建侧）** |
| **round2c 位流/ltx/xsa**（2026-10-18 归档） | `out\archive\b31b_r2_2026-10-18\{aurora_mem_bridge_r2_28921C6B.bit, probes_r2_28921C6B.ltx, mb_ctrl_r2.xsa, SHA256.txt}` | Lead | **已完成 [L2]（见 §3；S0 PASS）** |
| **round2d 候选 ELF**（`1e3a42db` 50,944 B） | 待 Lead 归档（live `sw\j3_soft\Debug\j3_soft.elf`） | Lead | **PENDING（候选未归档；固件修 dread 3 读）** |
| **round2d 触发式 ILA CSV**（`R2_ila_<tag>_{ui,user}_{pre,post}.csv`） | `evidence_2026-10-18\` | Lead（`R2_TRIGGER_PROBE=...` + `-IlaCapture`） | **PENDING（重建含 AXI/握手探针后抓取）** |
| **AXI 楔死根因（A）** | 触发式 ILA 波形 + PC/标记定位 | Lead/script-tools | **PENDING（[L1] 假说；需新探针重建）** |
| **TX 无帧（B）** | eth/TX 侧 ILA 探针 | Lead | **PENDING（eth ILA 已裁，需补探针）** |
| **下一次成功位流对**（round2b 之后） | archive 新目录 + `probes_r2_<bit8>.ltx` + `mb_ctrl_r2.xsa` + SHA256.txt | Lead | **PENDING（等 round2b 构建）** |
| 结论/等级定稿（§1 表回填） | 本文件 | 证据责任人 | PENDING（S0 已取得；S1–S11 待板验） |
| 提交（commit）/ 远端 CI | git | Lead（统一提交） | PENDING（本工具链与文档未 commit） |

---

## 8. 复算命令（只读，可原地复跑）

```powershell
$ev = 'D:\FPGA\prj\project_11\out\evidence_2026-10-18'   # 当轮日志目录动态: evidence_<yyyy-MM-dd>（round2c = evidence_2026-10-18）
# 1) 本目录全部文件 hash（前8 + 全量）
Get-ChildItem -File $ev | Sort-Object Name | ForEach-Object {
  $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  "{0}  {1}  {2}  {3}" -f $h.Substring(0,8), $h, $_.Length, $_.Name
}
# 2) round2c 归档验证：以 SHA256.txt 为准
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\SHA256.txt' -Algorithm SHA256
Get-Content 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\SHA256.txt'
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\aurora_mem_bridge_r2_28921C6B.bit' -Algorithm SHA256   # 期望 28921C6B…24627
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\probes_r2_28921C6B.ltx' -Algorithm SHA256   # 期望 4AC25546…7C33
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\mb_ctrl_r2.xsa' -Algorithm SHA256   # 期望 16A4F01F…C59E
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\j3_soft_r2_1bc8088d.elf' -Algorithm SHA256   # 期望 1BC8088D…BD42A
# 3) round2c 门限/DRC 证据（以 sweep2 日志为准）
Select-String -Path 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\build_r2_sweep2.log' -Pattern 'SWEEP2_ExtraTimingOpt: WNS=|V5_SWEEP2_OK|DRC finished with|write_bitstream completed' | Select-Object -Last 6
# 4) 工具链自证复跑（不碰板）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_dryrun.ps1
# 4b) round2c S0 钉身份复跑（dry-run, 不碰板；期望 [JUDGE] S0 PASS 与 R2_RESULT: SKIP）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 `
  -Bit 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\aurora_mem_bridge_r2_28921C6B.bit' `
  -Elf 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\j3_soft_r2_1bc8088d.elf' `
  -BuildLog 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\build_r2_sweep2.log' `
  -Xsa 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\mb_ctrl_r2.xsa' `
  -ExpectBitHash8 28921C6B -ExpectElfHash8 1BC8088D -ExpectXsaHash8 16A4F01F `
  -IlaLtx 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\probes_r2_28921C6B.ltx'
# 4c) round2d 触发式 ILA（示例：AXI 楔死，先设 env 再跑 tcl；或 -Run 前设 env 由 board 继承）
$env:R2_TRIGGER_PROBE='dbg_s2mm_reqpend'   # 或新构建 dbg_lite_hang_st / dbg_lite_arvalid
$env:R2_TRIGGER_COMPARE="eq1'b1"
$env:R2_TRIGGER_TIMEOUT_S='20'; $env:R2_TRIGGER_POSITION='1536'
$env:R2_STIM_CMD='<高频 serve/flood 命令>'; $env:R2_TAG='wedge'
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 -Run ... -IlaCapture -IlaLtx <归档 ltx>
#    或手工: vivado -mode batch -source D:\FPGA\prj\project_11\out\r2_ilacap.tcl -notrace -log <evid>\R2_ilacap_vivado_wedge.log
# 5) 判据工具自检
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode selftest
# 6) 对账/差分（**上板后**）
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode delta --ui-pre <ui_pre.csv> --ui-post <ui_post.csv> --user-pre <user_pre.csv> --user-post <user_post.csv> --expect-delta 4
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode recon --ui-post <ui_post.csv> --user-post <user_post.csv>
```

> 上板执行命令见 `R2_tools_README.md` §2.2（round2c 已可用）；`r2_board.ps1` 的末尾 `R2_RESULT:` 行是唯一总判据行（`PASS`/`FAIL <step>`/`NOT_OBTAINED <step> (判据未取得)`/`SKIP`）。**S0 PASS 已由 dry-run 复现（`evidence_2026-10-18\R2_20261018_144715.log`）。**

---

## 9. 依据等级与引用

- **`[L4]` 定案**：唯一相容解释 + 对照实验闭环 + 修复后复验通过 ⇒ 可写入本索引 §1 并作为后续设计输入。
- **`[L3]` 板证实**：板上实测直接观测到机制本身（非推论）且排除全部已知替代解释；**未修复复验**要标注。
- **`[L2]` 对照成立**：≥2 方向对照实验（正交变量 ±）；写入时标“待复验/待穷尽”。
- **`[L1]` 相容假说**：只允许出现在“假设”栏；禁止写成“判定/根因/定位”。
- **`[L0]` 猜测**：禁止写入记录。
- 依据文件：`AGENTS.md` §6a/§七/§八/§九（#17/#18/#40/#43/#45/#46/#53/#55/#56）/§十二；`out\S0S8_DESIGN.md`；`out\R2_S2MM_DESIGN.md`；`evidence_2026-10-17\R1_evidence_index.md`；`evidence_2026-10-17\R2_tools_README.md`。
- Lead 裁决：2026-10-17 22:0x 口径确认 + 22:2x–22:3x **v1.1/v1.2 冻结**（`'U'` 三行 wreq/wdbg/s2sr；`+0x4C` ACK（opcode 0x06）；fault 硬判；S4 s2sr/TKEEP_SUSPECT；桥② 不加错误探针；Halted 期望 0；归档命名最终版）+ 22:4x **最终 ELF `1bc8088d`（50,896 B，blob `ee256c05`；fa38a8cd/67c0b73a 作废）** + `R2_S2MM_DESIGN.md` v1.2 文档对齐（超时 56ms 统一/WAITGO 良性丢帧 vs fail-stop/恢复序列/lat_w 禁判据/alloc≠commit/D4/A3G2 等级边界）。
- **本轮收尾事实（2026-10-18 00:5x–01:0x）**：构建 **NO_BITSTREAM**（5 掷时序门限全败；综合 PASS；诊断 25/30 新写引擎 gray→CE 锥 + route 56.6%）+ **板验未执行**（用户要求收尾+断电）⇒ 本索引 §1 全部未取得、§2 无板级证据、§3 R2 位流/ltx/xsa 未产出（在库为 R1 参照）；记录正文=开发文档名 `阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`（vault `调试记录/`，docs 镜像由 Lead 负责）。
- **round2b 事实（2026-10-18 12:5x，`[L2]` Lead 通知 + 磁盘 build 脚本）**：round2 place/route 首掷 **WNS −0.135**（拥塞/资源密度；`AggressiveExplore` 布局失败）⇒ **不改 RTL、裁 ILA 探针省资源**后重综合（进行中；`out\r2d_synth*` 12:49 启动、当前 0 B）。裁剪以 `build_synth_only.tcl`/`build_debug.tcl` 12:49 版为准：ILA1@eth_rxc/ILA2@user_clk_b 整核移除；ILA0 probe0 374→92b；ILA3 probe0 184→152b；裁 `dbg_mem_bresp/wslot/rslot` ⇒ **判据边界=缺失探针列 INFO/NOT_OBTAINED，不判 FAIL**。RTL/固件/ELF 不变（bridge blob `06e6bd72…`、ELF `1bc8088d`）。
- **round2c 事实（2026-10-18 14:4x，`[L2]` Lead 通知 + 磁盘归档实测）**：**构建通过**——`SWEEP2_ExtraTimingOpt: WNS=0.004 WHS=0.004`（`build_r2_sweep2.log` L2659）+ `V5_SWEEP2_OK: directive=ExtraTimingOpt wns=0.004 whs=0.004`（L2764）；DRC 0 Errors/22 Warnings；write_bitstream 成功。归档 `out\archive\b31b_r2_2026-10-18\`：bit `28921C6B…`（10,266,180 B）、ltx `4AC25546…`（64,593 B，实测仅 u_ila_0/u_ila_3；ILA0 92+9b、ILA3 152b）、xsa `16A4F01F…`、ELF `1BC8088D…`、RTL bridge blob 实测 `f43267db…`。**S0 离线 PASS**：`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`（日志 `evidence_2026-10-18\R2_20261018_144715.log`）。Lead 修复 `r2_board.ps1` okMarker 不识别 `V5_SWEEP2_OK` 的 S0 误判；script-tools 复验 BOM+ParseFile 并补 round2c 常量。**归档清单 14:53 升级**：27 项（新增 `BUILD_STATUS.md`、`congestion_iter_3/4.txt`、`diag_arm_path_probe.tcl`），清单 3,243 B、自身 SHA256 `73fb1aae…`（以磁盘复算为准），头部 RTL blob 已更正 `f43267db`。**板验 S1–S11 进行中。**

---

## 10. 本骨架的变更记录

| 版本 | 内容 |
|---|---|
| v0.1（2026-10-17 22:3x） | 上板前骨架：章节按 R1 台账同构（结论→证据映射 / 板级原始证据 / 构建产物 hash / 离线回归 / 工具清单 / PENDING / 复算命令 / 依据等级）；**§1 全部 [待测]、无任何板上结论**；已填可先行项：ELF `67c0b73a`（50,576 B）与 dry-run 7/7 PASS（[L2]）；PENDING 行留待上板补录 |
| v0.2（2026-10-17 22:3x 待命期） | 回填 Lead 最终裁决到 §6：`dbg_wr_timeout` 不挂 ILA 为**有意**（省 300MHz ILA3 余量）+ `stat_wr_timeout` **无 Lite 读回路径** ⇒ 上板不可观测仅 INFO；补 `dbg_s2mm_state` 编码（0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT）与可观测替代物（`dbg_wr_fault`/`'U'` wreq,wdbg,s2sr/`ro_wm` 推进）；桥① bresp 恒 0 INFO、桥② 无错误探针 INFO；§5 工具 hash 更新到 v1.3 |
| v0.3（2026-10-17 22:4x 待命期） | **ELF 最终冻结 `1bc8088d`（50,896 B，blob `ee256c05`；fa38a8cd/67c0b73a 作废）** 同步 §1 C0/§3/§8；按 `R2_S2MM_DESIGN.md` v1.2 回填 §6 新口径（超时统一 24b≈56ms、WAITGO 良性丢帧 vs STREAM/PUSH/WAITDONE fail-stop、fault 恢复序列、lat_w 禁作判据 D8、alloc≠commit A12、D4/A3G2 等级边界）；§4 离线回归按审计报告引用（R2_rtl_audit.md，只引用不自判）；§5 工具 hash 更新到 v1.4 |
| v0.4（2026-10-18 01:0x 收尾） | **按构建收口结果更新**：新增 §0.1「本轮场次结果」（NO_BITSTREAM 5 掷明细/综合 PASS/失败诊断 25/30 CE 锥+route 56.6%/板验未执行/失败轮不覆盖在库产物/归档与 SHA256.txt/下次开工主修建议，全部 `[L2]`）；§1 全部状态改为 **NOT_OBTAINED/SKIP** 并明确"本轮不写通过"；§2 标注本轮无板级证据；§3 改为"本轮实际状态"（R2 位流/ltx/xsa 未产出；在库 R1 参照 c8cd3a32/c9b52dd7；失败轮 ltx 仅核对探针名；综合 PASS；扫描 FAIL；诊断/BUILD_STATUS/SHA256.txt 实 hash）；§4 增加综合 PASS/扫描 FAIL/诊断 `[L2]` 行；§5 工具 hash 更新到 v1.5；§6 增加本轮构建未收口口径；§7 PENDING 台账逐行置为 NOT_OBTAINED/PENDING（等下一次成功位流对）；§8 复算命令改为失败轮归档/构建证据/S0 NOT_OBTAINED 复现；§9 补本轮收尾事实 |
| v0.5（2026-10-18 12:5x round2b） | **同步 round2b ILA 探针集裁剪**：头部状态/§0.1 增加 round2（WNS −0.135）与 round2b（裁 ILA 重综合中）行；§3 增加 round2 扫描/round2b 综合行、R2 探针行改为裁剪后（ILA1/2 移除、ILA0 92b/ILA3 152b、裁 bresp/wslot/rslot）；§4 增加 round2/2b 时序攻坚行、dry-run 改 v1.6；§5 工具 hash 更新；§6 新增第 10 条 round2b 裁列判据边界；§7 增加 round2b 位流/ltx/xsa PENDING 行；§8 标注证据目录按日期动态；§9 补 round2b 事实；工具 `r2_counter_recon.py` 裁列缺失改 INFO（selftest 5/5 + 合成用例 PASS）、`r2_ilacap.tcl` round2b 布局/运行时检查、`r2_board.ps1` S6/S10 文案；dry-run 7/7 PASS |
| v0.6（2026-10-18 14:5x round2c） | **round2c 成功位流 + S0 PASS 回填**：头部状态改为位流已出/S0 PASS/板验进行中；§0.1 增加 round2c 构建（V5_SWEEP2_OK WNS+0.004/DRC 0E、22W）、round2c 身份（bit/ltx/xsa/ELF/blob 实测）、S0 离线 PASS、板验进行中四行；§1 C0 改 **已取得 [L2]（S0 PASS）**、C1–C11 改 **PENDING（板验进行中）**；§2 改"板验进行中"；§3 重写为 round2c 权威表（bit `28921c6b`/ltx `4ac25546`/xsa `16a4f01f`/ELF `1bc8088d`/综合覆盖/扫描 PASS/timing 摘要）+ round1 历史段；§4 增加 round2c PASS 行、dry-run 改 v1.7；§5 工具 hash 更新（board `afe58e31`）；§6 补 S0≠板验/blobl 笔误/门限口径三条；§7 PENDING 台账置为已取得/板验进行中；§8 复算命令改 round2c 归档 + S0 钉身份命令；§9 补 round2c 事实；工具 `r2_board.ps1` round2c 常量/归档目录/日志候选（Lead 修复 okMarker `V5_SWEEP2_OK` 后复验 BOM+ParseFile） |
| v0.7（2026-10-18 14:5x 归档清单升级同步） | **同步 Lead round2c 归档清单升级**：27 项（新增 `BUILD_STATUS.md`/`congestion_iter_3/4.txt`/`diag_arm_path_probe.tcl`），清单 3,243 B、`73fb1aae…`（磁盘复算，Lead 最终值待发）；头部 RTL blob 已更正 `f43267db`（R19 关闭）；§0.1/§3/§6/§7 引用同步为“27 项清单 + SHA256.txt（28 文件）”；S0 PASS/位流身份未变，未重跑 dry-run（工具与位流未变） |
| v0.8（2026-10-18 16:5x round2d） | **round2d 板验初场回填 + S2/S3b 判据修正**：头部改"round2c 位流已出/S0 PASS；round2d 初场 S1/S3 PASS、端到端未建立（未收口）"；§0.1 增加板验 round2d 行（S0/S1/S3 PASS、固件 dread 3 读修复候选 ELF `1e3a42db`、修后 'I'=wr6/rd3/ILA wm=5/rd_frm=5/commit_len=86、A=AXI 楔死 [L1]/B=TX 无帧）；§1 C1→[L3] 已取得（S1 PASS）、C2 新口径 PENDING、C3 S3 已取得/S3b 待复跑；§3 ELF 行加候选；§4 增 round2d 行；§5 工具 hash（board `f92666f5`、tcl `9fda27ba`）；§6 新增第 13/14 条（判据修正 RTL 依据 + A/B 未收口不得写通过）；§7 增候选 ELF/触发 CSV/A/B 台账；§8 增触发式 ILA 命令块；§9 补 round2d 事实。 |
