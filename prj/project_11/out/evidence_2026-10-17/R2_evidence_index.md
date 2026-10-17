# R2 证据索引（prj11 路线 B / B3-2 桥①写侧换层 S2MM）— **本轮 PENDING：构建 NO_BITSTREAM + 板验未执行**

- **状态（2026-10-18 01:0x 收尾，以磁盘为准）**：本轮场次 **构建结局 = NO_BITSTREAM（时序门限 WNS≥0 & WHS≥0 拒收，5 掷全败 ⇒ 无 R2 位流）**，且 **板验未执行**（用户要求收尾+断电；板卡未被本次 R2 工作触碰：未烧/未开串口/JTAG/未 ping）⇒ **本文件不含任何板上结论**：§1 全部 `[待测]/未取得`；**S0 依赖项判 `NOT_OBTAINED`，S2–S11 全部 `SKIP`**。等下一次成功位流对后按模板补录。**§6a 硬规则 3：判据未触发/未取得 ≠ 判据通过。**
- **等级边界**：本轮仅有 `[L2]` 离线事实（综合 PASS / 时序门限失败 / 失败诊断）；**无 `[L3]/[L4]`**。归因性描述按 §6a 标等级。
- **用途**：R2 判决序列（S0–S11）的**唯一证据台账**——每条结论/判据指向哪个原始文件、SHA256 指纹、依据等级。模板仿 `evidence_2026-10-17\R1_evidence_index.md`。
- **写权限边界**：本文件只登记证据与状态，不产生结论；结论只在对应判据取得板上实测日志后填入并把等级从 `[待测]` 升到 `[L3]/[L4]`。本目录（`out\evidence_2026-10-17\`）为证据落盘区。
- **Hash 口径**：`Get-FileHash -LiteralPath <file> -Algorithm SHA256`；表中列**前 8 位**，关键产物给全量 64 位。**归档产物 hash 以 `out\archive\b31b_r2_2026-10-17\SHA256.txt` 为准**；复算命令见 §8。
- **配套**：`out\evidence_2026-10-17\R2_tools_README.md`（工具链说明/判据分层/风险）、`out\R2_S2MM_DESIGN.md`（v1.2）、`out\S0S8_DESIGN.md`（R1 判据口径）、`evidence_2026-10-17\R1_evidence_index.md`（R1 台账）、`out\archive\b31b_r2_2026-10-17\BUILD_STATUS.md`（构建轮次/诊断/修复建议）、**记录正文** `C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`（§六 构建+诊断、§九 下次开工；docs 镜像由 Lead 负责）。
- **证据产物命名约定**（工具已实现）：
  - 总控日志：`R2_<yyyyMMdd_HHmmss>.log`（UTF-8 BOM）
  - 四档：`R2_4tier_<ts>.log`；10MB：`R2_mb10_<ts>.log` + `R2_mb10_<ts>.recomposed.jsonl`
  - ILA：`R2_ila_<tag>_{ui,user}_{pre,post}.csv` + `R2_ilacap_vivado_<ts>.log`
  - J3：`j3_fourchains_<ts>.log` + `j3_{m,a,b}_<ts>.log`（`j3_fourchains.ps1` 产出）
  - 判定行：`[JUDGE] <step> PASS|FAIL|NOT_OBTAINED|SKIP` / `R2_RESULT:` / `R2_MB10_RESULT:` / `R2CAP_RESULT:` / `FOURCHAINS_RESULT:` / `R2_COUNTER_RECON:`

---

## 0. 使用规则（上板前必读）

1. **先跑 `out\r2_dryrun.ps1`** 确认工具链自证 7/7 PASS；再按 `R2_tools_README.md` §2.2 的 `-Run` 命令上板。**本轮无 R2 位流 ⇒ `-Run` 不可用**（缺 `-Bit` 时脚本判 `NOT_OBTAINED ARG` 并提示等下一次成功位流）。
2. 只有拿到 **板上原始日志/CSV** 的条目才能从 PENDING 改为「已取值」；`NOT_OBTAINED` 必须写“判据未取得（实验无效）”，不得写成“通过/正常”。
3. 每条结论标注等级（AGENTS.md §6a）：`[L4]` 定案 / `[L3]` 板证实 / `[L2]` 对照成立 / `[L1]` 相容假说（**只允许出现在“假设”栏**）/ `[L0]` 猜测（禁止写入）。
4. 时间一律 Asia/Shanghai（UTC+8）；文件 hash 取登记时刻实测值（同名文件被覆盖时须重算并留轮次说明）。

---

## 0.1 本轮场次结果（2026-10-17 构建 / 10-18 收尾；**全部 `[L2]` 离线事实，无板上结论**）

| 项 | 事实（证据落点） | 等级 |
|---|---|---|
| **构建结局** | **NO_BITSTREAM**：5 掷均被时序门限（WNS≥0 & WHS≥0）拒收，失败轮不写位流、不覆盖在库产物。轮次：`ExtraTimingOpt` 后布 −0.198→最终 **−0.098 / +0.004**；`Default`=`Opt 31-306` MIG 缝合瞬态（已知坑，不判设计）；`AggressiveExplore`=`[Common 17-69] Placer could not place all instances`（拥塞）；`WLDrivenBlockPlacement` 后布 −0.251→最终 **−0.225 / +0.004**；`ExtraPostPlacementOpt` 后布 −0.200→最终 **−0.175 / +0.004**。**权威落点**：`archive\b31b_r2_2026-10-17\BUILD_STATUS.md` §1；原始：`out\r2_sweep_console.log`（尾 `SWEEP_WLDrivenBlockPlacement: WNS=-0.225 WHS=0.004` + `V5_SWEEP_ALL_FAIL`）、`out\r2_sweep2_console.log`（尾 `SWEEP2_ExtraPostPlacementOpt: WNS=-0.175 WHS=0.004`） | **[L2]** |
| **综合** | **PASS**：`out\r2_synth.log` `Synthesis finished with 0 errors, 0 critical warnings and 743 warnings`（L1972）+ `SYNTH_ONLY_DONE`（L2170）；`pre_impl_debug.dcp` + ILA 四核（含 R2 新探针）OK（BUILD_STATUS §1） | **[L2]** |
| **失败诊断（Lead 直读报告）** | 30 条最差路径中 **25/30** = `u_mem/u_wr_bytes/wr_gray_s2_reg[3]` → `u_mem/u_bridge/g_wr_dma.wd_data_r_reg[*]/CE`（3.238ns，logic 1.405 / route 1.833=**56.6%**，slack −0.175ns；8 级 gray→decode 锥带 512 CE 负载）；**5/30** = 桥② 旧写 FSM 同族（`u_mem2/.../g_wr_hw.w_data_r_reg[*]`，R2 未改动）。落点：`R2_build_worst_paths_excerpt.txt` + `rpt2_ExtraPostPlacementOpt.worst.rpt`（archive 内，hash 见 SHA256.txt） | **[L2]** |
| **失败轮不覆盖在库产物** | `out\aurora_mem_bridge.bit` 仍为 R1 在库 `c8cd3a32`（9,746,300 B，mtime 10-17 21:28）；`out\mb_ctrl.xsa` 仍为 R1 `c9b52dd7`（21:29）；`out\probes.ltx` 不存在；R2 ILA 网表见 `out\probes_v5_ExtraTimingOpt.ltx`（失败轮） | **[L2]** |
| **板验** | **未执行**（用户 10-18 00:2x 要求收尾+断电；未烧/未开串口/JTAG/未 ping）⇒ **S0 依赖项 NOT_OBTAINED、S2–S11 全部 SKIP** | **[L2]** 过程事实 |
| **归档（失败轮）** | `out\archive\b31b_r2_2026-10-17\`：磁盘共 21 个文件（`SHA256.txt` 登记 20 项，`BUILD_STATUS.md` 在清单内）；`SHA256.txt` 2,488 B `041db3f1…`、`BUILD_STATUS.md` 4,100 B `EA9E7BC4…`；**注意 `aurora_mem_bridge_r1_in_service_c8cd3a32.bit` 是 R1 参照、不是 R2 产物** | **[L2]** |
| **下次开工** | 先按 `BUILD_STATUS.md` §3 主修时序：新写引擎 `g_wr_dma` 字节捕获加 **1 级流水**（`byte_q`/`byte_valid_q`，吞吐不变；不动 `HAS_DMA=0`），备选：裁 ILA3 低价值探针重综合 / 追加 place 指令取方差 / 单掷 `build_debug.tcl` | **[L2]** 建议 |

---

## 1. 结论 → 证据映射（**本轮全部未取得；上板后逐行填**）

> 判据定义见 `R2_tools_README.md` §3（S0–S11）。下表“支撑证据”列给出**预期落点**；本轮（NO_BITSTREAM + 板验未执行）实际状态见第 5 列。

| # | 判据 | 支撑证据（预期落点） | 等级 | 取值状态 |
|---|---|---|---|---|
| **C0** | S0 工件身份：R2 位流/ELF SHA256、构建日志 WNS/WHS≥0、DRC 0、xsa hash | `R2_<ts>.log` S0 段；`out\archive\b31b_r2_2026-10-17\{aurora_mem_bridge_r2_<bit8>.bit, j3_soft_r2_1bc8088d.elf, build_r2_sweep.log, build_r2_synth.log, mb_ctrl_r2.xsa, probes_r2_<bit8>.ltx, SHA256.txt}` | **[待测]** | **NOT_OBTAINED**：本轮 NO_BITSTREAM 无 R2 位流可钉身份（在库为 R1 参照）；**等下一次成功位流对** |
| **C1** | S1 在位配置记录（R1 修复版在位对 + 只读快照） | `R2_<ts>.log` S1 段（`c8cd3a32`+`2961b585` 在位记录、`'U'/'L'`/邻居/ping1 只读快照） | **[待测]** | **NOT_OBTAINED**：板验未执行（S1 SKIP） |
| **C2** | S2 位流身份原位判据：未发 `'d'` 时 ping 0/1 + NIC `ReceivedBytes` delta=0 + `wmwr` delta=0（+`WR_REQ.pending` INFO） | `R2_<ts>.log` S2 段（`[JUDGE] S2 PASS`、`[B2] U req/wreq/mode` 原始行、NIC 前后读数） | **[待测]** | **NOT_OBTAINED**：板验未执行（S2 SKIP） |
| **C3** | S3 DMA 服务+写路径启动：mode=1 & `req.bit24=1`、`WR_DBG.fault=0`、s2sr 现场值；S3b 静默窗建立 | `R2_<ts>.log` S3/S3b 段（`[JUDGE]`、`'U'` 整段原始行含 wreq/wdbg/s2sr） | **[待测]** | **NOT_OBTAINED**：板验未执行（S3/S3b SKIP） |
| **C4** | S4 单帧端到端：ping 1/1 + `ReceivedBytes`≥74 + `WM_WR+1` & `WM_RD+1`；s2sr/emit(len_tab=86) 现场 | `R2_<ts>.log` S4 段（`[JUDGE] S4`、s2sr、emit 解码、NIC 读数） | **[待测]** | **NOT_OBTAINED**：板验未执行（S4 SKIP） |
| **C5** | S5 ping×4：4/4 + `ReceivedBytes`≥296 + `WM_WR/WM_RD` 各 +4 | `R2_<ts>.log` S5 段 | **[待测]** | **NOT_OBTAINED**：板验未执行（S5 SKIP） |
| **C6** | S6 桥级 ILA：桥② `dbg_mem2_rd_frm` +4 且 `ost` 前后 0；桥① `wm/wr_frm/rd_frm` 各 +4 且 `ost` 前后 0 | `R2_ila_<tag>_{ui,user}_{pre,post}.csv` + `R2_ilacap_vivado_<ts>.log` + `r2_counter_recon.py --mode delta` 输出（`R2_ILA_DELTA:` 行） | **[待测]** | **NOT_OBTAINED**：板验未执行（S6 SKIP；失败轮 ltx 不可作 R2 判据配套） |
| **C7** | S7 四档零回归：`DDR_VERIFY: PASS`（20/20·12/12·12/12·300/300） | `R2_4tier_<ts>.log`；`R2_<ts>.log` S7 段 | **[待测]** | **NOT_OBTAINED**：板验未执行（S7 SKIP） |
| **C8** | S8 10MB 100%+SHA：`lost==0 & corrupt==0 & sha_match==true & recv==chunks`；独立 SHA 复算一致 | `R2_mb10_<ts>.log` + `R2_mb10_<ts>.recomposed.jsonl`；`R2_<ts>.log` S8 段 | **[待测]** | **NOT_OBTAINED**：板验未执行（S8 SKIP） |
| **C9** | S9 J3 四链（带 `--dma`）：`FOURCHAINS_RESULT: PASS`（M/A/B）；规则号 1 等价性数据（逆序对/缺失字节） | `j3_fourchains_<ts>.log` + `j3_{m,a,b}_<ts>.log`；`R2_<ts>.log` S9 段 | **[待测]** | **NOT_OBTAINED**：板验未执行（S9 SKIP） |
| **C10** | S10 双桥计数对账闭合（J4 口径）：mem/mem2 各自 `wm==wr_frm==rd_frm`、`ost=0`；错误计数按可观测项（mem `len_err/stall`、`dbg_wr_fault`；mem2 无探针记 INFO） | `r2_counter_recon.py --mode recon` 输出（`R2_COUNTER_RECON:` 行）；post CSV 同上 | **[待测]** | **NOT_OBTAINED**：板验未执行（S10 SKIP） |
| **C11** | S11 收尾恢复：`Set-EngineMode` 后 mode/`bit24` 符合目标 | `R2_<ts>.log` S11 段 | **[待测]** | **NOT_OBTAINED**：板验未执行（S11 SKIP） |
| **C12** | 风险假设（**只允许写“假设”栏**）：S2MM 尾拍 TKEEP→WSTRB 与旧 AXI WSTRB 逐位等价（`[L1]`）；IOC 退休时刻与旧 BRESP 等价（`[L1]`） | S4（len_tab=86 覆盖尾拍）+ S6 ILA（`dbg_s2mm_state/tvalid/tready`、`dbg_wr_fault`）+ S7/S8/S9 字节级判据；若 byte-level FAIL 而 ping 通 ⇒ 判据日志 `TKEEP_SUSPECT` | **假设 [L1]** | PENDING（未板验；需 S4/S6/S7/S8/S9 联合取值后按 §6a 重标） |

> **PASS 的前提**：S0 通过 + 各步判定行齐；任一 `FAIL/NOT_OBTAINED` 都要在此表标“未取得/未通过”并写清原因，不得合并成“总体通过”。**本轮不写“通过”。**

---

## 2. 板级原始证据（**本轮无**；下列为模板，待下一次成功位流对补录）

> 本轮**无板级原始证据**（板卡未被触碰：未烧/未开串口/JTAG/未 ping）。口径同 R1：按“时间 / 大小 / SHA256前8 / 支撑什么 / 等级 / 备注”登记；无效实验单独成表并标“无效留痕”。

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

## 3. 构建产物 hash（**本轮：NO_BITSTREAM；归档 hash 以 `SHA256.txt` 为准**）

> 归档（失败轮）：`out\archive\b31b_r2_2026-10-17\`（磁盘共 21 个文件：`SHA256.txt` 登记其中 20 项）。**默认名产物 `out\aurora_mem_bridge.bit` 会被下次构建覆盖，判据只认归档绝对路径 + 实算 hash。**
> ⚠️ `aurora_mem_bridge_r1_in_service_c8cd3a32.bit` 是 **R1 在库位流参照**（非 R2 产物）；**R2 位流本轮未产出**。

| 产物 | 文件名/路径 | 大小 | SHA256 前 8 | SHA256 全量 | 状态 |
|---|---|---|---|---|---|
| **R2 位流** | `aurora_mem_bridge_r2_<bit8>.bit` | — | — | — | **NO_BITSTREAM（未产出）**：5 掷均被时序门限拒收，失败轮不写位流；等下一次成功构建 |
| R1 在库参照（非 R2） | `archive\b31b_r2_2026-10-17\aurora_mem_bridge_r1_in_service_c8cd3a32.bit`（=`out\aurora_mem_bridge.bit`） | 9,746,300 B | `c8cd3a32` | `c8cd3a32e6aa965f26e9429ad75204c78953366de31571dddb379dda8976ba80` | **R1 在库（10-17 21:28）；禁止当 R2 烧/钉身份** |
| R2 探针 ltx | 最终配对 `probes_r2_<bit8>.ltx` **未产出**；失败轮 ILA 网表 `out\probes_v5_ExtraTimingOpt.ltx` | 198,882 B | `453d9173` | `453d917348be6dea908cf2aecef2615596c9cd5b63dd5fe3eb7f96aa9c34efdb` | **仅用于核对探针名，不可作 R2 上板判据配套**（新探针名已确认：`dbg_s2mm_state[2:0]`/`tvalid`/`tready` + `dbg_s2mm_reqpend`/`dbg_wr_fault`） |
| R2 xsa | `mb_ctrl_r2.xsa` **未产出**；`out\mb_ctrl.xsa` 为 R1 版 | 2,526,101 B | `c9b52dd7` | `c9b52dd79e2097250e130a592b3da2f5ddfb698a8a072f18948b7871ac459350` | R1 在库（10-17 21:29）；禁止当 R2 钉 hash |
| ELF（最终冻结） | `archive\b31b_r2_2026-10-17\j3_soft_r2_1bc8088d.elf` | **50,896 B** | **`1bc8088d`** | `1bc8088dc48d42bbf40aec76fdfb69b96ce9b187cfaf6dbd022e285b921bd42a` | **最终冻结（fa38a8cd/67c0b73a 作废）**；blob `ee256c05`；`-ExpectElfHash8 1bc8088d` |
| 综合日志 | `out\r2_synth.log`（archive `build_r2_synth.log`） | 232,023 B | `ef7025a1` | `ef7025a1c17ee544d048d1d97b6a1ac8416d61acb9e1065e26f2a79f89f6d394` | **PASS**：0 errors / 0 critical warnings / 743 warnings（L1972）+ `SYNTH_ONLY_DONE`（L2170） |
| 实现扫描（2） | `out\r2_sweep.log` / `out\r2_sweep_console.log` | 614,090 B / 620,156 B | `e12fbdbd` / `5c8cc0b8` | `e12fbdbd32c7885922b08685120f8ac8c1bdb83b88f3323d2d8a12283ec59ac3` / `5c8cc0b80797bbf949f55454ffc1a4c0024627994b775a14be69d2526068f8cc` | **FAIL（门限拒收）**：尾 `SWEEP_WLDrivenBlockPlacement: WNS=-0.225 WHS=0.004` + `V5_SWEEP_ALL_FAIL` |
| 实现扫描（sweep2） | `out\r2_sweep2.log` / `out\r2_sweep2_console.log` | 280,772 B / 283,357 B | `6bffb869` / `a84d2ed9` | `6bffb869b10b767244811ef681dbc99c2192a87d59a2728d5947b2091d076f5a` / `a84d2ed909b4a0e0ecd4d98c4e9a191ee9f007ca5c3f589451ac53dbfd1b3ac9` | **FAIL（门限拒收）**：尾 `SWEEP2_ExtraPostPlacementOpt: WNS=-0.175 WHS=0.004` |
| 失败诊断 | `archive\...\rpt2_ExtraPostPlacementOpt.worst.rpt` + `R2_build_worst_paths_excerpt.txt` | 250,207 B / 2,783 B | `ea05cc30` / `d8b49c4f` | `ea05cc30964b4189bb6424d1364003b3226cd7467d7b07102dc229cd0784b741` / `d8b49c4f72e5dfb4d10a99467690516f7de40cd08f41e4b2b6ed8ac626487d83` | 25/30 新写引擎 CE 锥（route 56.6%）+ 5/30 桥② 旧 FSM 同族 |
| 构建状态 | `archive\...\BUILD_STATUS.md` | 4,100 B | `ea9e7bc4` | `ea9e7bc4549da360d81fa9a4657e05e85b5cc31c0735a2382811739688f4ba69` | 轮次表/诊断/修复建议/复现命令 |
| 归档清单 | `archive\...\SHA256.txt` | 2,488 B | `041db3f1` | `041db3f16157322a9d8c8f4b3680960da18f5abbb7a69e05a15b6002eb37b095` | **逐文件 hash 权威清单（本表归档项以它为准）** |

> RTL blob 指纹：失败轮 RTL 快照 hash 见 `SHA256.txt`（`rtl_axi4_master_bridge.v` `39A037E2…`、`rtl_frame_mem_if.v` `0CB4B68E…`、`rtl_axi_lite_regs.v` `2084AA11…`、`rtl_aurora_mem_bridge.v` `11CB53AD…`）；成功位流后的 blob 以 Lead 通知/构建日志为准。

---

## 4. 离线回归 / 构建验证（本轮 `[L2]` 事实，非板上回归）

| 项 | 判据 | 落点 | 状态 |
|---|---|---|---|
| **dry-run 工具链自证** | `r2_dryrun.ps1` 7/7 PASS（BOM+ParseFile/py_compile/正负自检/Tcl 结构+ASCII/两脚本 dry-run/只读纪律） | `out\r2_dryrun.log` | **已取值 [L2]（2026-10-18 01:03，v1.5 重跑）** |
| **综合** | 0 errors / 0 critical warnings；`SYNTH_ONLY_DONE`；pre_impl_debug.dcp + ILA 四核 OK | `out\r2_synth.log`（`ef7025a1…`） | **PASS [L2]** |
| **实现扫描（时序门限）** | WNS≥0 & WHS≥0 才写位流 | `out\r2_sweep_console.log` / `out\r2_sweep2_console.log` | **FAIL [L2]：NO_BITSTREAM（5 掷全败；最好 −0.098，sweep2 −0.175）** |
| **失败诊断** | 最差路径族定位 | `rpt2_ExtraPostPlacementOpt.worst.rpt` / `R2_build_worst_paths_excerpt.txt` | **已取值 [L2]**（25/30 新写引擎 CE；5/30 桥② 旧 FSM） |
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
| `out\r2_board.ps1` | S0–S11 总控（dry-run 默认） | `ec3ea5ba` | 已交付（v1.5）；本轮无位流，`-Run` 判 NOT_OBTAINED |
| `out\r2_ilacap.tcl` | ILA PRE/POST 快照（纯 ASCII、env 参数化） | `fcc262e6` | 已交付 |
| `out\r2_counter_recon.py` | 双桥对账/差分/正负自检/Tcl 结构+ASCII 检查/s2mm_state 解码 | `a425ad75` | 已交付；自检 5/5 |
| `out\r2_mb10_sha.ps1` | 10MB 质量档 + SHA 独立复算 | `edb2e32b` | 已交付 |
| `out\r2_dryrun.ps1` | dry-run 自证一键复现 | `b65f047a` | 已交付 |
| `out\evidence_2026-10-17\R2_tools_README.md` | 工具链/判据分层/风险说明 | `60e0cd5b` | 已交付（v1.5） |
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
9. **本轮构建 NO_BITSTREAM（`[L2]` 离线事实，非结论/非通过）**：无 R2 位流 ⇒ **S0 依赖项 NOT_OBTAINED、S2–S11 全部 SKIP**；失败轮不写位流、不覆盖在库 R1 产物（`out\aurora_mem_bridge.bit`=`c8cd3a32`、`out\mb_ctrl.xsa`=`c9b52dd7`）；失败轮 ILA 网表 `out\probes_v5_ExtraTimingOpt.ltx` 仅用于核对探针名、不可作 R2 判据配套；诊断/修复建议见 `archive\b31b_r2_2026-10-17\BUILD_STATUS.md`（下次开工=先主修 1 级流水）。

> 更正记录（上板后用）：`（PENDING：若正文/记录与原始日志矛盾，在此登记“补记/更正”，保留原数字与出处）`

---

## 7. PENDING 台账（上板执行清单；**本轮状态已置为未取得/等下一次**）

| 待产生证据 | 预期落点 | 负责人 | 状态 |
|---|---|---|---|
| R2 位流 hash（bit8） | `out\archive\b31b_r2_2026-10-17\aurora_mem_bridge_r2_<bit8>.bit` | Lead | **NOT_OBTAINED：本轮 NO_BITSTREAM（5 掷时序门限全败）；等下一次成功构建** |
| xsa hash | `out\archive\b31b_r2_2026-10-17\mb_ctrl_r2.xsa` | Lead | **NOT_OBTAINED（本轮未产出；`out\mb_ctrl.xsa` 仍 R1 `c9b52dd7`）** |
| 探针 ltx hash | `out\archive\b31b_r2_2026-10-17\probes_r2_<bit8>.ltx` | Lead | **NOT_OBTAINED（本轮未产出；失败轮 ltx 仅核对探针名）** |
| 构建日志（synth/sweep/sweep2） | `out\r2_synth.log`、`out\r2_sweep*.log` + archive `build_r2_*.log` | Lead | **已产生并归档 [L2]（hash 见 §3）** |
| 归档 `SHA256.txt` | 同上目录 | Lead | **已完成 [L2]（2,488 B，`041db3f1…`）** |
| 构建状态/失败诊断 | `BUILD_STATUS.md` / `R2_build_worst_paths_excerpt.txt` / `rpt2_*.worst.rpt` | Lead | **已完成 [L2]（下次开工先按 §3 主修）** |
| S0–S11 原始日志 | `R2_<ts>.log`（UTF-8 BOM） | Lead | **NOT_OBTAINED：板验未执行（未烧/未开串口/JTAG/未 ping）** |
| S6 ILA CSV ×4 + vivado 日志 | `R2_ila_<tag>_*_{pre,post}.csv` + `R2_ilacap_vivado_<ts>.log` | Lead（`-IlaCapture` 自动） | **NOT_OBTAINED（S6 SKIP）** |
| S7 四档日志 | `R2_4tier_<ts>.log` | Lead | **NOT_OBTAINED（S7 SKIP）** |
| S8 10MB 日志 + 重组文件 | `R2_mb10_<ts>.log` + `.recomposed.jsonl` | Lead | **NOT_OBTAINED（S8 SKIP）** |
| S9 J3 日志（M/A/B） | `j3_fourchains_<ts>.log` + `j3_{m,a,b}_<ts>.log` | Lead | **NOT_OBTAINED（S9 SKIP）** |
| R2 WR TB / 负向对照日志 | `prj\project_11\sim\`（rtl-auditor 归档处） | rtl-auditor/Lead | PENDING（引用 `R2_rtl_audit.md`，不自行判定） |
| 失败现场（如有）分析 | 本轮无板级失败现场；构建失败诊断见 BUILD_STATUS.md | Lead | **已完成 [L2]（构建侧）** |
| **下一次成功位流对**（重做时序主修后） | archive 新目录 + `probes_r2_<bit8>.ltx` + `mb_ctrl_r2.xsa` + SHA256.txt | Lead | **PENDING（等下一次构建）** |
| 结论/等级定稿（§1 表回填） | 本文件 | 证据责任人 | PENDING（本轮无板上结论） |
| 提交（commit）/ 远端 CI | git | Lead（统一提交） | PENDING（本工具链与文档未 commit） |

---

## 8. 复算命令（只读，可原地复跑）

```powershell
$ev = 'D:\FPGA\prj\project_11\out\evidence_2026-10-17'
# 1) 本目录全部文件 hash（前8 + 全量）
Get-ChildItem -File $ev | Sort-Object Name | ForEach-Object {
  $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  "{0}  {1}  {2}  {3}" -f $h.Substring(0,8), $h, $_.Length, $_.Name
}
# 2) 本轮（失败轮）归档验证：以 SHA256.txt 为准 + 状态/诊断留痕
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\SHA256.txt' -Algorithm SHA256
Get-Content 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\SHA256.txt'
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\j3_soft_r2_1bc8088d.elf' -Algorithm SHA256   # 期望 1BC8088D…BD42A
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\aurora_mem_bridge_r1_in_service_c8cd3a32.bit' -Algorithm SHA256  # R1 参照, 非 R2
# 3) 本轮构建结局/门限证据（失败轮不写位流）
Select-String -Path 'D:\FPGA\prj\project_11\out\r2_sweep_console.log'  -Pattern 'SWEEP_|V5_SWEEP_ALL_FAIL' | Select-Object -Last 6
Select-String -Path 'D:\FPGA\prj\project_11\out\r2_sweep2_console.log' -Pattern 'SWEEP2_' | Select-Object -Last 4
Select-String -Path 'D:\FPGA\prj\project_11\out\r2_synth.log' -Pattern 'Synthesis finished|SYNTH_ONLY_DONE' | Select-Object -Last 4
Get-FileHash 'D:\FPGA\prj\project_11\out\aurora_mem_bridge.bit' -Algorithm SHA256   # 仍应为 R1 c8cd3a32…
# 4) 工具链自证复跑（不碰板）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_dryrun.ps1
# 4b) 本轮 S0 依赖项口径复现（无位流 ⇒ S0 NOT_OBTAINED；dry-run, 不碰板）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 -BuildLog D:\FPGA\prj\project_11\out\r2_sweep2.log
# 5) 判据工具自检
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode selftest
# 6) 对账/差分（**下一次成功位流对 + 上板后**）
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode delta --ui-pre <ui_pre.csv> --ui-post <ui_post.csv> --user-pre <user_pre.csv> --user-post <user_post.csv> --expect-delta 4
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode recon --ui-post <ui_post.csv> --user-post <user_post.csv>
```

> 上板执行命令见 `R2_tools_README.md` §2.2（**本轮无位流不可用**）；`r2_board.ps1` 的末尾 `R2_RESULT:` 行是唯一总判据行（`PASS`/`FAIL <step>`/`NOT_OBTAINED <step> (判据未取得)`/`SKIP`）。

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

---

## 10. 本骨架的变更记录

| 版本 | 内容 |
|---|---|
| v0.1（2026-10-17 22:3x） | 上板前骨架：章节按 R1 台账同构（结论→证据映射 / 板级原始证据 / 构建产物 hash / 离线回归 / 工具清单 / PENDING / 复算命令 / 依据等级）；**§1 全部 [待测]、无任何板上结论**；已填可先行项：ELF `67c0b73a`（50,576 B）与 dry-run 7/7 PASS（[L2]）；PENDING 行留待上板补录 |
| v0.2（2026-10-17 22:3x 待命期） | 回填 Lead 最终裁决到 §6：`dbg_wr_timeout` 不挂 ILA 为**有意**（省 300MHz ILA3 余量）+ `stat_wr_timeout` **无 Lite 读回路径** ⇒ 上板不可观测仅 INFO；补 `dbg_s2mm_state` 编码（0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT）与可观测替代物（`dbg_wr_fault`/`'U'` wreq,wdbg,s2sr/`ro_wm` 推进）；桥① bresp 恒 0 INFO、桥② 无错误探针 INFO；§5 工具 hash 更新到 v1.3 |
| v0.3（2026-10-17 22:4x 待命期） | **ELF 最终冻结 `1bc8088d`（50,896 B，blob `ee256c05`；fa38a8cd/67c0b73a 作废）** 同步 §1 C0/§3/§8；按 `R2_S2MM_DESIGN.md` v1.2 回填 §6 新口径（超时统一 24b≈56ms、WAITGO 良性丢帧 vs STREAM/PUSH/WAITDONE fail-stop、fault 恢复序列、lat_w 禁作判据 D8、alloc≠commit A12、D4/A3G2 等级边界）；§4 离线回归按审计报告引用（R2_rtl_audit.md，只引用不自判）；§5 工具 hash 更新到 v1.4 |
| v0.4（2026-10-18 01:0x 收尾） | **按构建收口结果更新**：新增 §0.1「本轮场次结果」（NO_BITSTREAM 5 掷明细/综合 PASS/失败诊断 25/30 CE 锥+route 56.6%/板验未执行/失败轮不覆盖在库产物/归档与 SHA256.txt/下次开工主修建议，全部 `[L2]`）；§1 全部状态改为 **NOT_OBTAINED/SKIP** 并明确"本轮不写通过"；§2 标注本轮无板级证据；§3 改为"本轮实际状态"（R2 位流/ltx/xsa 未产出；在库 R1 参照 c8cd3a32/c9b52dd7；失败轮 ltx 仅核对探针名；综合 PASS；扫描 FAIL；诊断/BUILD_STATUS/SHA256.txt 实 hash）；§4 增加综合 PASS/扫描 FAIL/诊断 `[L2]` 行；§5 工具 hash 更新到 v1.5；§6 增加本轮构建未收口口径；§7 PENDING 台账逐行置为 NOT_OBTAINED/PENDING（等下一次成功位流对）；§8 复算命令改为失败轮归档/构建证据/S0 NOT_OBTAINED 复现；§9 补本轮收尾事实 |
