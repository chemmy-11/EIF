# R2 上板判据工具链说明（prj11 路线 B / B3-2 桥①写侧换层 S2MM）

- **交付者**：Agent Team 成员 `script-tools`（PC/离线侧）；**硬件在环（烧录/串口/JTAG/ping/ILA）由 Lead 亲自执行**。
- **状态（2026-10-18 14:5x round2c）**：**round2c 成功位流已产出并钉 S0**。`ExtraTimingOpt` 过门限：**`V5_SWEEP2_OK` WNS=+0.004 / WHS=+0.004；DRC 0 Errors/22 Warnings；write_bitstream completed**。归档 `out\archive\b31b_r2_2026-10-18\`（**27 项清单 + `SHA256.txt`（28 文件）**，14:53 升级版）。身份：bit `aurora_mem_bridge_r2_28921C6B.bit`（10,266,180 B，`28921C6B…`）、ltx `probes_r2_28921C6B.ltx`（64,593 B，`4AC25546…`，round2b 裁剪版）、xsa `mb_ctrl_r2.xsa`（`16A4F01F…`）、ELF `j3_soft_r2_1bc8088d.elf`（`1bc8088d`，**已被 round2d 候选取代**）、RTL bridge blob `f43267db…`（ARM 时序修复版）。**S0 dry-run 已 PASS**（`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`）；S6/S10 用 ILA0+ILA3 保留项。
- **状态（2026-10-18 16:3x–16:5x round2d 板验初场，未收口）**：板卡上电并烧 R2 对；**S0/S1/S3 PASS**、端到端未建立。① **固件阻塞缺陷（已修）**：`serve_write_once` 的 `dread()` 2 读在紧循环交替地址(0x44/0x40)仍滞后 >1 笔 ⇒ 固件从不看到 pending（JTAG 实证 `pending_seen=0/arm_cnt=0`）；改 3 读后 `pending_seen=1/arm_cnt=1/WRREQ=0x80010056`，**候选 ELF `1e3a42db`（50,944 B）**。② 修后写引擎可被服务：`'I'`=wr6/rd3、ILA `dbg_mem_wm=5/rd_frm=5/WR_DBG.last_commit_len=86` ⇒ S2MM commit 与 MM2S 读出均发生。③ **未收口 A[L1]**：高频 `serve_any()`（~143kHz Lite 读）后 MicroBlaze 楔死在 `dread()` volatile load（`lwi`，`g_dbg_addr=0x44A00034`=lite_regs DMA_REQ 读）；UART 静默、`rst -processor` 不恢复、只能重配 FPGA；1ms 限速可多次存活但非确定性 ⇒ 疑 lite_regs 写命令(SET_WRGO)后紧接读的握手竞争。④ **未收口 B**：`rd_frm` 增长但 ping 0/4、NIC `ReceivedBytes` delta=0（eth 域 ILA 已裁掉，需补探针）。
- **round2d 判据口径修正（已落地）**：`'U' wmwr`(+0x08)=`u_wr_frame` 是**收帧接受计数**（frame_mem_if 在帧接受时即+1，早于 commit），R2 未服务阶段每来一帧都会+1 且被 WAITGO 良性丢帧 ⇒ **S2 硬判改为** ping 0/1 + NIC `ReceivedBytes` delta=0 + `WR_DBG.last_commit_len==0` + `fault==0`（wmwr delta 仅 INFO）；**S3b 静默窗改为** `pending==0 && fault==0`（& bit25=0）连续两拍（wmwr/wmrd/backlog 仅 INFO；R2 下 `wmwr==wmrd` 不可达）。详见 §5-17。
- **round2d 触发式 ILA**：`r2_ilacap.tcl` 新增 `R2_TRIGGER_PROBE/R2_TRIGGER_COMPARE/R2_TRIGGER_TIMEOUT_S/R2_TRIGGER_POSITION/R2_TRIGGER_ARM_MS`（armed-before-stim，超时仍上传并标 `R2CAP_TRIGGER_STATUS`）；用法见 §4.5；后续重建的最小探针清单见 §4.6。会话记录 `evidence_2026-10-18\R2_board_session_20261018.md`（Lead 落盘）。
- **round2c 判据边界**：ILA1@eth_rxc / ILA2@user_clk_b 整核移除；ILA0 92 bit（+probe1 9b 发射字节流不变）、ILA3 152 bit；缺失 `dbg_mem_bresp/wslot/rslot` ⇒ **INFO/NOT_OBTAINED（判据未取得≠失败，§6a）**，S6/S10 不因缺 ILA1/2 报错；S10 仍用桥① ui `wm/wr_frm/rd_frm/stall/len_err/ost` + 桥② ui 四计数 + user 侧 `u_wr/u_rd/u_drop/ost_s/mem2_u_*`；S8c 用 ILA0 probe1（9b）不变。
- **round1 历史**：round1 构建 NO_BITSTREAM（5 掷时序门限全败，S0 依赖项 NOT_OBTAINED、S2–S11 SKIP；归档 `b31b_r2_2026-10-17` 保留作历史）。
- **Lead 修复留痕**：`r2_board.ps1` 曾因 **okMarker 不识别 `V5_SWEEP2_OK`** 会误判 S0 FAIL；Lead 已修复（`okMarker`/`bitInLog` 正则加入 `V5_SWEEP2_OK`）。script-tools 复验 BOM+ParseFile 0 语法错误，并补齐 round2c 常量/归档目录/钉法说明（新 hash 见 §1）。
- **等级边界**：本工具链不产生任何板上结论；所有机制性描述等级见 AGENTS.md §6a（本文按 `[L1-设计]/[L2-离线]/[L3-板证]` 标注）。S0 PASS 为**离线判据**（`[L2]`），板验结论待 S1–S11。
- **写 scope**：本目录（`out/evidence_2026-10-17/`）+ `out/r2_*`；未改 R1 脚本/未改 prj11 现有文件/未 commit/未碰板卡（`r2_dryrun.log` §7 有只读纪律自证）。**证据目录按日期动态：当轮日志落 `out\evidence_<yyyy-MM-dd>\`（round2c = `evidence_2026-10-18\`）。**
- **配套**：R2 设计草案 `out\R2_S2MM_DESIGN.md`（v1.3）；R1 判据口径 `out\S0S8_DESIGN.md`；R1 证据台账 `evidence_2026-10-17\R1_evidence_index.md`；round2c 归档 `out\archive\b31b_r2_2026-10-18\{SHA256.txt, build_r2_sweep2.log, rpt2_ExtraTimingOpt.timing_summary.rpt}`；round1 构建轮次/诊断 `out\archive\b31b_r2_2026-10-17\BUILD_STATUS.md`；**记录正文** `C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`（docs 镜像由 Lead 负责）。

---

## 1. 文件清单与指纹（SHA256，实算）

| 文件 | 作用 | 大小 | SHA256 前 8 | SHA256 全量 |
|---|---|---|---|---|
| `out\r2_board.ps1` | **S0–S11 判据总控**（dry-run 默认，`-Run` 才执行；可自动串起 ILA/四档/10MB/J3） | 123,653 B | `f92666f5` | `f92666f555512afded793587f016cd520c0ede863875f33cc18d09a5ae7ac7f2` |
| `out\r2_ilacap.tcl` | ILA PRE/POST 快照抓取（env 参数化；**纯 ASCII**、注释独立成行；round2d 加 `R2_TRIGGER_*` 触发式抓取） | 20,866 B | `9fda27ba` | `9fda27ba448d2c1d2a9e92f2a7502715919ed7387d40b4634499c6210822bc97` |
| `out\r2_counter_recon.py` | 双桥计数对账（J4 口径）/ ILA 前后差分 / 判据工具正负自检 / Tcl 结构+ASCII 检查 / s2mm_state 解码 | 45,947 B | `c4aa2c3a` | `c4aa2c3aafb050f51161d773e468a12f8a58b7c63955ff0f8f3c3c9939af695d` |
| `out\r2_mb10_sha.ps1` | 10MB 质量档（json_storm 默认间隔）+ SHA256 判定封装（dry-run 默认） | 22,063 B | `8836a046` | `8836a0462e9bd94085ac088311ef44ea65d29dd51a12713e4a400d7565614d19` |
| `out\r2_dryrun.ps1` | **dry-run 自证一键复现器**（BOM/ParseFile/py_compile/自检/两脚本 dry-run/只读纪律） | 13,588 B | `b65f047a` | `b65f047a7ac74c1a1f10947750f8c634d0a8e260b42755c13af99ecba6007e16` |
| `out\r2_dryrun.log` | 自证输出（7/7 PASS；UTF-8 BOM；round2d 重跑） | 37,938 B | `9a58c426` | `9a58c4265aa80c0877fae2dcfdfa587c9b70457bd4d655d04dcccdc53c390e66` |
| `evidence_2026-10-18\R2_20261018_170246.log` | round2d 最后一次 `r2_board.ps1` dry-run 自身日志（UTF-8 BOM） | 20,351 B | `64bc8a01` | `64bc8a01dd3532233cc6e120c2dc966505a522055cd1d910346609b1316e2598` |
| `evidence_2026-10-18\R2_mb10_20261018_170255.log` | round2d 最后一次 `r2_mb10_sha.ps1` dry-run 自身日志（UTF-8 BOM） | 2,840 B | `40eac7a0` | `40eac7a0624715c7306f26a619cf31b411ae50f0b6dfd8ff902c1ebf6dd3cc52` |

> 注：当轮证据目录按日期动态（`evidence_<yyyy-MM-dd>`）；round2c/round2d 都在 `evidence_2026-10-18\`（另有 round2c 的 `R2_20261018_144715.log` `ef05a653`、`R2_20261018_144731.log` `f32e4a01`，round2b 的 `R2_20261018_125156.log`/`R2_mb10_20261018_125207.log` `198651c9`/`74a4ce08`）；round1 旧日志在 `evidence_2026-10-17\`（`91f49523`/`9f152915`）。**round2d 板验原始日志/CSV/会话记录见 `evidence_2026-10-18\{R2_board_session_20261018.md, R2_20261018_16*.log, R2_ila_*, r2cap_*, r2_manual_*, r2_jtag_*}`（Lead 落盘）。**

> 复算：`Get-FileHash -LiteralPath <file> -Algorithm SHA256`。
> `.ps1` 纪律：前 3 字节 = `EF BB BF`（UTF-8 BOM）+ PowerShell 5.1 `[System.Management.Automation.Language.Parser]::ParseFile` **0 语法错误**（本机实跑，见 `r2_dryrun.log` §1）。**编辑工具会静默剥 BOM（坑 #18），每次改动后必须复验。**

---

## 2. 快速用法

### 2.1 dry-run（默认；不碰板，可随时跑）

```powershell
# 一键自证（推荐先跑这个；会把全过程写入 out\r2_dryrun.log）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_dryrun.ps1

# 只跑总控的 dry-run（默认无 fixture 时 S0 SKIP；给 R1 归档工件可做真校验）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 `
    -Bit  D:\FPGA\prj\project_11\out\archive\b31b_rdfix_2026-10-17\aurora_mem_bridge_rdfix_c8cd3a32.bit `
    -Elf  D:\FPGA\prj\project_11\out\archive\b31b_rdfix_2026-10-17\j3_soft_n7_2961b585.elf `
    -BuildLog D:\FPGA\prj\project_11\out\archive\b31b_rdfix_2026-10-17\build_retire_fix_sweep.log `
    -ExpectBitHash8 c8cd3a32 -ExpectElfHash8 2961b585

# 10MB 封装 dry-run（真校验 10MB 源 SHA + json_storm 源码参数 + UDP 1234 端口状态）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_mb10_sha.ps1
```

dry-run 保证：不烧写（xsct）、不开串口、不发 ping、不跑 Vivado、不跑四档/10MB/J3。由 `Invoke-BurnPair / Invoke-UartProbe / Invoke-Ping / Invoke-Vivado / Invoke-Python` 统一 GUARD 阻断，末尾打印 5 个计数器（**必须全 0**）自证。

### 2.2 `-Run` 完整判据（Lead 执行；示例）

> ✅ round2c 成功位流已就绪（S0 dry-run PASS）。**round2d 固件缺陷已定位并修出候选 ELF `1e3a42db`（50,944 B）**：下次板验用候选 ELF（`-ExpectElfHash8 1E3A42DB`；归档后路径替换 `<r2d>`）；bit 仍为 `28921C6B`。仍由 Lead 执行 `-Run`；只复跑部分步骤可加 `-SkipBurn`。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 -Run `
    -Bit  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\aurora_mem_bridge_r2_28921C6B.bit `
    -Elf  D:\FPGA\prj\project_11\out\archive\<r2d 归档>\j3_soft_r2_1e3a42db.elf `
    -BuildLog D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\build_r2_sweep2.log `
    -ExpectBitHash8 28921C6B -ExpectElfHash8 1E3A42DB `
    -Xsa D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\mb_ctrl_r2.xsa -ExpectXsaHash8 16A4F01F `
    -IlaCapture -IlaLtx D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\probes_r2_28921C6B.ltx `
    -Port COM5
```

- 若 ELF 尚未归档：可直接给 `sw\j3_soft\Debug\j3_soft.elf` 并加 **`-AllowNonArchive`**（S2 才肯烧；纪律上建议先归档后跑）。
- 不加 `-IlaCapture` 时 S6 打印可复制命令并判 `NOT_OBTAINED`（不冒充通过）；S10 可用 `-IlacapUiPost/-IlacapUserPost` 直接喂 CSV。
- 只用已烧好的 R2 对复跑部分步骤：加 `-SkipBurn`（S2 跳过烧写，身份判据仍需板在未发 `'d'` 的出厂态）。
- 可选：`-StrictS2sr`（s2sr 硬判）、`-RequireR2Probes`（要求 `dbg_s2mm_*` 探针齐）、`-QuickS7`、`-SkipS7/-SkipS8/-SkipS9/-SkipS11`、`-RestoreEngine 0`。
- 失败纪律：任一步 `FAIL/NOT_OBTAINED` 使退出码非 0，末尾 `R2_RESULT: FAIL <step>` / `R2_RESULT: NOT_OBTAINED <step> (判据未取得)`；**不自动重试**。

### 2.3 单独工具

```powershell
# 判据工具正/负对照（5/5 PASS 才算工具可用；坑 #43/#56）
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode selftest

# S6 差分：pre/post 两份 CSV
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode delta `
   --ui-pre  <R2_ila_*_ui_pre.csv>  --ui-post <R2_ila_*_ui_post.csv> `
   --user-pre <R2_ila_*_user_pre.csv> --user-post <R2_ila_*_user_post.csv> --expect-delta 4

# S10 J4 累计对账（--user-post 参与全局 dbg_wr_fault/dbg_s2mm_reqpend 查找）
py D:\FPGA\prj\project_11\out\r2_counter_recon.py --mode recon --ui-post <ui_post.csv> --user-post <user_post.csv>

# ILA 抓取（由 r2_board.ps1 -Run -IlaCapture 自动调用；也可手工）
$env:R2_LTX='D:\...\probes_r2_<bit8>.ltx'; $env:R2_OUT_DIR='D:\...\evidence_2026-10-17'
$env:R2_STIM_CMD='ping -n 4 -w 900 192.168.1.10'; $env:R2_TAG='r2_manual'
vivado -mode batch -source D:\FPGA\prj\project_11\out\r2_ilacap.tcl -notrace -log <evid>\R2_ilacap_vivado.log
```

> 运行环境：Python 全路径 `C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe` + `PYTHONUTF8=1`（脚本内部已设；坑 #45：Git Bash 的 python 是坏壳）。`.ps1` 用 Windows PowerShell 5.1 执行。

---

## 3. 判据分层（S0–S11：能区分什么 / 判据未取得怎么标）

> 统一语义：`PASS` / `FAIL`（有效负结果）/ `NOT_OBTAINED`（判据未取得=实验无效）/ `SKIP`（可选/占位）。`FAIL` 与 `NOT_OBTAINED` 都非 0 退出并逐行打印 `R2_RESULT`。

| 步 | 动作 | 判据 | 能区分什么 | 判据未取得时 |
|---|---|---|---|---|
| **S0** | 离线：bit/ELF SHA256、构建日志 WNS/WHS/标记/DRC、xsa hash（可选） | hash8 与 `-Expect*Hash8` 一致（bit=`28921c6b`/ELF=`1bc8088d`/xsa=`16a4f01f`）；日志 `SWEEP2_*: WNS/WHS` ≥0；成功标记 `V5_SWEEP2_OK` 在/失败标记不在；`DRC finished with 0 Errors` 且 ERROR 行=0 | 位流是否真过时序门限；工件身份是否烧错/归档错；xsa 是否新 | 无 `-BuildLog` ⇒ `SKIP`（非失败）；日志存在但解析不到门限/DRC ⇒ `NOT_OBTAINED`（`-SkipDrcRequirement` 可降级 DRC）；**round2c 已 PASS（`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`）** |
| **S1** | 在位配置记录（**不烧绿基线**）：离线记录默认名产物/R1 在位对/R2 目标对 hash8；`-Run` 时只读 `'U'/'L'`/邻居/ping1 快照 | 离线记录落盘；`-Run` 要求 `'U'` 可解析或 `'L'` 有 LAT 行 | 板/线/PC 侧“换 R2 前”的状态基线（DESIGN §10：S2 烧 R2 对 = 唯一变量） | 板卡不响应 ⇒ `NOT_OBTAINED`（不阻塞 S2 烧写） |
| **S2** | 烧 R2 对后**全程不发 `'d'`**：`'U'` 断言 mode=0&bit24=0 → `'S'` → ping1 → `'U'` | **round2d 硬判（2026-10-18 板证修正）**：ping 0/1 + NIC `ReceivedBytes` delta=0 + **`WR_DBG.last_commit_len==0`（未提交）** + `fault==0`；INFO：`WR_REQ.pending`（~56ms 窗口内可能=1；WAITGO 超时后良性丢帧回落 0 均属正常）、`wmwr` delta（`'U'` +0x08=`u_wr_frame` 是**收帧接受计数**，帧一被接受就+1，**不是提交**；未服务阶段每来一帧都会+1且被良性丢弃，故仅 INFO） | **位流身份原位判据**：R2 写路径=S2MM 需软核服务，未切 DMA ⇒ 不提交、读侧零启动 ⇒ 不回包；回包=烧错/烧旧/引擎位已 1 | 烧后 `'U'` 无应答/引擎位非 0 ⇒ `NOT_OBTAINED`（不要为凑判据发 `'d'`）；无 `wdbg` 字段 ⇒ `NOT_OBTAINED`（commit 判据未取得） |
| **S3** | `Set-EngineMode DMA`（`'d'` 翻转，最多 3 次，双重回读）→ `'S'` → settle 2s → 整段 `'U'` | 硬判：mode=1 & `req.bit24=1`；`WR_DBG.fault==0`（fault=1 ⇒ FAIL 并打印 wdbg/wreq/s2sr + ACK 恢复提示）；WARN：settle 后 pending 仍=1、slot/len 合法性、s2sr（`-StrictS2sr` 时 Halted=0&errbits=0 硬判） | 引擎/写服务真的切到 DMA；写引擎是否 fault（粘滞）；S2MM DMASR 是否报错/长度异常 | `'U'` 无应答/解析失败 ⇒ `NOT_OBTAINED`；Set-EngineMode 失败 ⇒ `FAIL` |
| **S3b** | 只读静默窗：轮询 `'U'` 到 **`pending==0` 且 `fault==0`（且 `bit25=0`）连续两拍**（round2d 新口径） | 静默窗建立 | 使 S4/S5 差分基线可信；**wmwr/wmrd/backlog 仅 INFO**（R2 良性丢帧使 `u_wr_frame` 永久多计 ⇒ `wmwr==wmrd` 不可达，旧判据会把正常板判成读出侧停摆） | 10 次轮询不静 ⇒ `FAIL`（S4/S5 自动降级 `NOT_OBTAINED`） |
| **S4** | `'U'` 前 → ping1 → `'U'` 后 | 硬判：ping 1/1 + `ReceivedBytes` ≥74 + `WM_WR+1` & `WM_RD+1`；fault=1 ⇒ FAIL；打印 s2sr + emit{len,slot,byte0}（ping32B 期望 **len_tab=86**=64+22 ⇒ 尾拍 TKEEP 自然覆盖） | 单帧端到端（栈→桥①S2MM写→DDR→桥①读→第二跳→PHY→PC）；失败形态可切分 `WR+0`/`RD+0`/线上 0 | 前置/静默窗/NIC 不可用 ⇒ `NOT_OBTAINED`；计数在但线上 0/1 ⇒ `FAIL`（交 S6） |
| **S5** | ping×4 + 前后 `'U'` 差分 | 硬判：`WM_WR+4` & `WM_RD+4` + ping 4/4 + `ReceivedBytes`≥296 | 唯一“到没到线上”真值；`WM_RD+0` 直接排除线上问题，断点锁读出侧 | S3b 不干净/NIC 不可用 ⇒ `NOT_OBTAINED`；计数在但 0/4 ⇒ `FAIL` |
| **S6** | ILA PRE/POST 快照（建议 `-Run -IlaCapture`：连 hw_server→set PROBES.FILE→PRE→`ping -n 4`→静默 2s→POST→CSV）；或 Lead 手工抓 | 桥② `dbg_mem2_rd_frm` 前后 **+4** 且 `ost` 前后均 0；桥① `dbg_mem_wm/wr_frm/rd_frm` 各 **+4** 且 `dbg_mem_ost` 前后 0；`dbg_wr_fault`(ILA0@user) 窗口内 0；`dbg_s2mm_state` 仅 INFO（timeout 计数不可观测） | 桥②读路径一字未动的**直接证据**（R1 缺陷形态=rd_frm 恒 0/ost 只增）；桥①写经 S2MM、读经 MM2S 的计数闭合 | 抓不到/CSV 缺列 ⇒ `NOT_OBTAINED`（不判 FAIL）；`-SkipIla` ⇒ `SKIP` |
| **S7** | `udp_verify_ddr.py`（prj10，四档） | 尾部 `DDR_VERIFY: PASS`（20/20·12/12·12/12·300/300；`-QuickS7` 只跑 1/2/3 档） | 数据穿 DDR 写-读往返逐字节无损（覆盖帧长%8 全部余数类） | UDP 1234 绑定失败/脚本缺 ⇒ `NOT_OBTAINED`；其余失败 ⇒ `FAIL`（若 S4/S5 已通则自动附 `TKEEP_SUSPECT`） |
| **S8** | `r2_mb10_sha.ps1` → `json_storm.py` 质量档（**源码默认**：chunk=1466B, gap-ms=1.0ms；不传 `--pace-us`） | exit0 & `lost==0` & `corrupt==0` & `sha_match==true` & `recv==chunks`(=7022)；PowerShell 侧独立复算源/重组 SHA256 与脚本打印双核对（源 SHA 钉死 `4F38AF2C…BF5`） | 10MB 全量 100%+SHA（业务级质量档）；独立复算防“工具静默失效” | 端口占用/无 summary ⇒ `NOT_OBTAINED`；失败 ⇒ `FAIL`（+`TKEEP_SUSPECT` 提示） |
| **S9** | `j3_fourchains.ps1 -Run -Bitstream retired`（内部带 `--dma`，逐轮 M/A/B，nslots=256；失败不重试） | 外层前置：`'S'` + `wmwr==wmrd & bit25=0` 两拍；J3 判据 `FOURCHAINS_RESULT: PASS` | 功能面收口 + 逐字节/J3′ 证据；R2 写 S2MM 下规则号 1 的等价性（写槽/长度/退休语义） | 前置不干净/`wr+255`/收帧停摆/`WAITWR-FAIL` ⇒ `NOT_OBTAINED` + **板卡需重烧**（失败现场自动查 `WR_DBG.fault`，fault=1 提示需 `+0x4C ACK` 恢复或重烧）；J3 后不自动 ping |
| **S10** | `r2_counter_recon.py --mode recon`（默认复用 S6 post CSV，cumulative 静默后口径；不另开 Vivado 会话） | J4 口径：mem/mem2 各自 `wm==wr_frm==rd_frm`；`ost==0`；错误硬判 = 桥① `len_err/stall` + 全局 `dbg_wr_fault/ro_stat_wr_timeout`（桥① `bresp` 仅 INFO：S2MM 下 BRESP 不可见；桥② 无错误探针则记 INFO） | 双桥计数闭合（判据③）；两桥分别判，不得用一桥相等掩盖另一桥失配 | 无 post CSV/缺探针列 ⇒ `NOT_OBTAINED` |
| **S11** | `Set-EngineMode` 收尾（默认 DMA=1；`-RestoreEngine 0` 切回 bridge） | mode=目标值 & `req.bit24` 对应；目标 DMA 时追加 `'S'` | 收尾状态可复现（J3 轮末 R_ENGINE=0/R_MODE=RND） | 收尾未确认 ⇒ `FAIL` |

---

## 4. 板端依赖（工件与寄存器协议，Lead 2026-10-17 最终冻结口径 + DESIGN v1.2 文档对齐）

### 4.1 工件（S0 期望；**round2c 成功位流已产出并 S0 PASS**）

**round2c 归档（成功轮）**：`out\archive\b31b_r2_2026-10-18\`（**27 项逐文件清单 + `SHA256.txt`（28 文件）**；**hash 以 `SHA256.txt` 为准**；该清单 2026-10-18 14:53 升级版含 BUILD_STATUS/congestion/diag 新证据）；round1 失败轮归档 `out\archive\b31b_r2_2026-10-17\` 保留作历史。

| 工件 | round2c 实际状态（以磁盘为准，2026-10-18 14:4x） |
|---|---|
| **R2 位流（成功）** | `archive\b31b_r2_2026-10-18\aurora_mem_bridge_r2_28921C6B.bit`：**10,266,180 B、`28921C6B38BE92447950B8C81405F278945529BB007E94461EC2CEEF0D324627`（bit8=28921c6b）**；`V5_SWEEP2_OK: directive=ExtraTimingOpt wns=0.004 whs=0.004`（`build_r2_sweep2.log` L2659/L2764），DRC 0 Errors/22 Warnings，`write_bitstream completed successfully`。**S0 dry-run PASS 已复验**。 |
| R1 在库参照（历史，非 R2） | `archive\b31b_r2_2026-10-17\aurora_mem_bridge_r1_in_service_c8cd3a32.bit`：9,746,300 B、`c8cd3a32…`。**仅历史参照。** `out\aurora_mem_bridge.bit` 在 round2c 后已变为 R2 默认名（hash8=`28921c6b`，10-18 14:43），但**判据仍只认归档绝对路径+实算 hash**。 |
| R2 探针 ltx（round2b 裁剪版，已拿到） | `archive\b31b_r2_2026-10-18\probes_r2_28921C6B.ltx`：**64,593 B、`4AC2554667F94BC3E052E0A652FF2DE322E2CE51FEE2B47399A108DF9E6B7C33`**；实测**仅 `u_ila_0`/`u_ila_3`**（无 ILA1/2）；ILA0 probe0=**92b** + probe1 发射字节流 **9b**；ILA3 probe0=**152b**；`dbg_mem_bresp/wslot/rslot` 确认**不存在** ⇒ 不可观测（INFO）。`-IlaLtx` 用此文件；S8c 用 ILA0 probe1（9b）不变。 |
| ELF | `archive\...\j3_soft_r2_1bc8088d.elf`：**`1bc8088d`（50,896 B，最终冻结，blob `ee256c05`）**；`-ExpectElfHash8 1BC8088D`（SHA256.txt 登记 `1BC8088D…BD42A`）；round2c 未变。 |
| R2 xsa（已产出） | `archive\b31b_r2_2026-10-18\mb_ctrl_r2.xsa`：2,606,995 B、**`16A4F01F51AF9665B4C79686812FEAA353C3CF8C27C8BC3C47DA1EC7D28EC59E`（hash8=16a4f01f）**；`-ExpectXsaHash8 16A4F01F`。 |
| 综合日志（round2c） | `archive\...\build_r2_synth.log`：181,651 B、`14F1DD74…`；`Synthesis finished with 0 errors, 1 critical warnings and 718 warnings`（**该 1 critical warning = `Synth 8-3321 create_generated_clock` aurora IP 既有族，非新增**）；`SYNTH_ONLY_DONE`。 |
| 实现扫描（round2c，通过） | `archive\...\build_r2_sweep2.log`：318,807 B、`062D9091…`；`SWEEP2_ExtraTimingOpt: WNS=0.004 WHS=0.004` + `V5_SWEEP2_OK ... bit=...` + DRC 0E/22W + write_bitstream 成功。时序摘要 `rpt2_ExtraTimingOpt.timing_summary.rpt`（8,142,267 B、`CB10118F…`）另见 WNS 0.042/WHS 0.004（报告口径；门限行以 `V5_SWEEP2_OK` 的 0.004 为准，两者均 ≥0）。 |
| 归档清单（round2c，27 项） | `archive\...\SHA256.txt`：**3,243 B、27 项逐文件 hash（+ 清单自身）**；清单自身实测 SHA256 = `73fb1aae…`（全量 `73fb1aaebd81879f9c1e80c9ecbcef36d0ca9c604669f56ccac1201259ebe9b5`，2026-10-18 14:53 版；**以磁盘复算为准**，Lead 稍后发最终值）。 |
| 归档新增证据（2026-10-18 14:53 升级版） | `BUILD_STATUS.md`（3,656 B、`3E038904…`；round2c 构建/修复/复查状态）+ `congestion_iter_3.txt`（16,497 B、`6A1D9459…`）+ `congestion_iter_4.txt`（12,603 B、`871A9638…`；拥塞证据）+ `diag_arm_path_probe.tcl`（675 B、`A3151B6B…`；ARM 关键路径逐级探针脚本）。 |
| RTL blob（round2c） | `rtl_axi4_master_bridge.v` 68,296 B、文件 SHA256 `B64300B4…`；**git blob = `f43267db82b84305cfeb519adcfa76f79443f6b3`**（ARM 时序修复版，实测 `git hash-object`）。**升级版 `SHA256.txt` 头部已更正为 `f43267db`**（旧笔误 `06e6bd72` 已修，R19 关闭）。 |

### 4.2 寄存器协议（软核经 `axi_lite_regs`；PC 侧只读，不写寄存器）

| 偏移 | 方向 | 布局/语义 |
|---|---|---|
| `+0x40` | 读 | `WR_REQ = {pending[31],6'b0,toggle[24],slot[23:16],len[15:0]}` |
| `+0x44` | 读 | `WR_DBG = {fault[31],7'b0,last_alloc_slot[23:16],last_commit_len[15:0]}`（A12：last_alloc_slot=最近**分配**槽号，last_commit_len=最近**提交**帧长，分配≠提交） |
| `+0x48` | 写（opcode 0x05，任意值） | 翻 `GO`（软核完成 S2MM 编程 + 清 IOC 后写）—— **只写不读** |
| `+0x4C` | 写（opcode 0x06，任意值） | 翻 `ACK`（写引擎 fault 恢复：桥 WD_HALT 从 HALT 退回 IDLE）—— **只写不读**；**固件/软核路径，PC 脚本不写** |

### 4.3 `'U'` 探针（真实固件输出；解析兼容冒号后多空白）

```
[B2] U wreq: <hex> <hex> <hex>     # WR_REQ，dread 同址连读 3 次（取最后/相等校验）
[B2] U wdbg: <hex> <hex> <hex>     # WR_DBG，同上
[B2] U s2sr: <hex> <hex>           # S2MM_DMASR 原始值（2 次连读）
```

- 原有 9 行（id/req/reqX/wmrd/stat/arl/emit/wmwr/ust/mode）保留；每行**首值是上一地址残值**，只用第 2..N 个。
- `req(+0x34)` 布局：`bit25`=sticky 待服务、`bit24`=engine(1=DMA)、`slot[23:16]`、`len[15:0]`。
- `s2sr` 位定义（PG021 直通模式）：`bit0=Halted`、`bit1=Idle`、`bit12=IOC`、`bit4..bit7` 等=错误位。**Lead 裁决：Halted 期望=0**（`'d'` 后已 RS=1；Halted=1 说明 S2MM 通道没起来 ⇒ 现场重要线索）；首次上板默认只 WARN 看原始值，`-StrictS2sr` 复跑时硬判。
- `emit(+0x3C)`：`len[31:16]`、`slot[15:8]`、`byte0[7:0]`；字节流=8B 前导+帧+4B FCS ⇒ 帧长 74B 时 `len=86`。
- **ILA 新探针（已与最终 `build_synth_only.tcl`/`build_debug.tcl` 机械对齐）**：
  - ILA3 @ui_clk：`dbg_s2mm_state[2:0]`、`dbg_s2mm_tvalid`、`dbg_s2mm_tready`（`bus_nets 3` + 2 单 bit）；
  - ILA0 @user：`dbg_s2mm_reqpend`、`dbg_wr_fault`（2 单 bit）；
  - **`dbg_s2mm_state` 编码（Lead 2026-10-17 冻结，仅 INFO）**：0=IDLE / 1=WAITGO / 2=STREAM / 3=PUSH / 4=WAITDONE / 5=DRAIN / 6=HALT（recon 自动解码打印）；
  - `dbg_wr_timeout` **未挂 ILA（有意）**：省 300MHz ILA3 余量（R1/W6 教训：300MHz 域加 96b 曾把 WNS 打到 -1.142）；`stat_wr_timeout` 是桥内 16b 计数器且**无 Lite 读回路径**（不在 `+0x40/+0x44`）⇒ **上板不可观测，仅 INFO**；
  - **可观测替代物（INFO，不作硬判据）**：ILA3 `dbg_s2mm_state` + ILA0 `dbg_wr_fault` + `'U'` 的 `wreq/wdbg/s2sr` + `ro_wm` 是否推进；
  - `r2_ilacap.tcl` 以 `R2_EXPECT_PROBES` 对这 5 个探针做存在性核对（缺失只 WARN，说明 ltx/位流不配套）；`r2_counter_recon.py --require-r2-probes` 可升硬判。
- **错误计数可观测性（Lead 裁决，全部 INFO 不硬判；round2b 进一步裁剪）**：
  - 桥① `dbg_mem_bresp` 在 S2MM 写路径**恒 0**（IP 内部 BRESP 不可见）；**round2b 已裁掉该探针 ⇒ 本轮连"看到 0"都不可得，缺失列一律 INFO**；
  - 桥②（HAS_DMA=0，RTL 本轮未动）`stall/len_err/bresp` **无 ILA 探针** ⇒ INFO（不可观测）；
  - `stat_wr_timeout` 无 Lite 读回路径（见上）。

### 4.4 round2b/round2c ILA 探针集（已进入 round2c 位流；与 2026-10-18 build_synth_only.tcl/build_debug.tcl 机械对齐）

> **round2c 位流已产出并复核**：`probes_r2_28921C6B.ltx`（64,593 B、`4AC25546…`）实测**仅 `u_ila_0`/`u_ila_3`**（无 ILA1/2），ILA0 92+9b、ILA3 152b，`dbg_mem_bresp/wslot/rslot` 确认不存在——与下表一致。

> 目的：省 300MHz 布线/资源余量（round2 place/route 首掷 WNS 仍 −0.135、`AggressiveExplore` 布局失败）；**round2c 位流已用裁剪后探针集通过**（RTL bridge blob `f43267db…`、ELF `1bc8088d` 不变）。

| ILA | 本轮位宽 | 保留探针 | 裁掉/移除 |
|---|---|---|---|
| ILA0 @user | probe0 **374→92 bit**（probe1 发射字节流 9b **保留不变**，S8c 用） | `dbg_mem_u_wr[16]`/`u_rd[16]`/`u_drop[16]`、`dbg_mem_rden(1)`、`dbg_mem_ost_s[9]`、`dbg_mem2_u_wr[16]`/`u_rd[16]`、`dbg_s2mm_reqpend(1)`、`dbg_wr_fault(1)` | — |
| ILA3 @ui | probe0 **184→152 bit** | `dbg_calib` + `dbg_mem_wm[16]`/`wr_frm[16]`/`rd_frm[16]`/`stall[16]`/`len_err[16]`/`ost[9]` + `dbg_mem2_wm[16]`/`wr_frm[16]`/`rd_frm[16]`/`ost[9]` + `dbg_s2mm_state[2:0]`/`tvalid`/`tready` | `dbg_mem_bresp[16]`、`dbg_mem_wslot[8]`、`dbg_mem_rslot[8]` |
| ILA1 @eth_rxc | **整核移除** | — | 整核（R2 S0–S11 判据不使用） |
| ILA2 @user_clk_b | **整核移除** | — | 整核（R2 S0–S11 判据不使用） |

**判据边界（round2b ILA 裁剪）**：S6/S10 **不因缺 ILA1/ILA2 报错**；`dbg_mem_bresp/wslot/rslot` 列缺失 ⇒ **INFO/NOT_OBTAINED（判据未取得≠失败，§6a）**，recon 不判 FAIL（`r2_counter_recon.py` 已按此实现，selftest 5/5 覆盖）。S10 仍可用：桥① ui `wm/wr_frm/rd_frm/stall/len_err/ost` + 桥② ui `wm/wr_frm/rd_frm/ost` + user 侧 `u_wr/u_rd/u_drop/ost_s/mem2_u_*`。`R2_EXPECT_PROBES` 保留 5 个新探针（`reqpend/fault`@ILA0 各 1b；`state[2:0]/tvalid/tready`@ILA3）。

---

### 4.5 触发式 ILA 抓取（round2d 新增；AXI 楔死/握手竞争诊断）

`r2_ilacap.tcl` 在原有"PRE 快照 → 刺激 → POST 快照（trigger_now）"基础上新增**触发式 POST**：在跑刺激**之前**对目标 ILA 武装 trigger，刺激后等待触发/超时再上传；未被武装的另一个 ILA 仍做普通 trigger_now POST。仍是**只读**（不写寄存器），CSV 命名不变（`R2_ila_<tag>_{ui,user}_{pre,post}.csv`）。

| 环境变量 | 默认 | 含义 |
|---|---|---|
| `R2_TRIGGER_PROBE` | 空（关） | 触发探针名子串，如 `dbg_s2mm_reqpend`/`dbg_s2mm_state`/`dbg_wr_fault`/`dbg_lite_arvalid`/`dbg_lite_hang_st`；空=旧 trigger_now 行为 |
| `R2_TRIGGER_COMPARE` | `eq1'b1` | Vivado `TRIGGER_COMPARE_VALUE` 表达式；单 bit 用 `eq1'b1`，总线示例 `eq3'b001` |
| `R2_TRIGGER_TIMEOUT_S` | `R2_WAIT_S`(30) | 等触发超时秒数；超时仍上传并打 `R2CAP_TRIGGER_STATUS`（可能含预触发样本） |
| `R2_TRIGGER_POSITION` | 1024 | 触发点在 2048 采样窗口中的位置（1024=前后各半） |
| `R2_TRIGGER_ARM_MS` | 300 | 武装后到刺激前的等待 ms |

**关键标记行**（供脚本/人工判读）：`R2CAP_TRIGGER_PROBE_HIT/ARMED/STATUS/TIMEOUT/SUMMARY`、`R2CAP_TRIGGER_FALLBACK`（探针缺失时回落 trigger_now）、`R2CAP_GRAB_POST_UI/POST_USER`（含 `trigger=`）。

**手工用法（AXI 楔死复现：先设 env，再跑 tcl）**：
```powershell
$env:R2_LTX='D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-18\probes_r2_28921C6B.ltx'
$env:R2_OUT_DIR='D:\FPGA\prj\project_11\out\evidence_2026-10-18'
$env:R2_TAG='wedge'
$env:R2_TRIGGER_PROBE='dbg_s2mm_reqpend'      # 或新构建的 dbg_lite_hang_st / dbg_lite_arvalid
$env:R2_TRIGGER_COMPARE="eq1'b1"
$env:R2_TRIGGER_TIMEOUT_S='20'
$env:R2_TRIGGER_POSITION='1536'               # 多留前因(3/4 预触发)
$env:R2_STIM_CMD='<你的高频 serve/flood 命令>'  # 例: 触发楔死的那条 bat/命令
$env:R2_SETTLE_MS='2000'
vivado -mode batch -source D:\FPGA\prj\project_11\out\r2_ilacap.tcl -notrace -log <evid>\R2_ilacap_vivado_wedge.log
```
**经 `r2_board.ps1 -Run -IlaCapture` 自动抓取**：board 脚本继承 PowerShell 会话环境变量，所以**在 `-Run` 前先设** `$env:R2_TRIGGER_PROBE=...`（其余默认即可）；S6 的刺激默认 `ping -n 4`，楔死复现时应改 `$env:R2_STIM_CMD` 指向高频 serve 命令。注意：触发只作用于**拥有该探针的单个 ILA**；跨域不要假设同时触发。

### 4.6 下一次重建的最小探针清单（供 RTL/构建脚本；诊断用，不作判据）

> 目的：把 `lite_regs` 的 AXI 握手与 user↔ui 请求/应答握手搬上 ILA，能在楔死时看到"卡在哪个握手"。**这些探针只作诊断，不是 S0–S11 判据**；缺失按 INFO/NOT_OBTAINED 处理。

**A. `axi_lite_regs.v` / AXI-Lite slave（@user_clk，建议挂 ILA0@user）**——最小 24 bit：

| 建议探针名 | 宽 | 说明 |
|---|---|---|
| `dbg_lite_arvalid` / `dbg_lite_arready` | 2 | 读地址通道握手（楔死核心：arvalid=1 且 arready=1 而 rvalid 不来） |
| `dbg_lite_araddr[5:0]` | 6 | 读地址字偏移（`0x34` 是 DMA_REQ；`g_dbg_addr=0x44A00034` 已定位） |
| `dbg_lite_rvalid` / `dbg_lite_rready` | 2 | 读数据通道握手 |
| `dbg_lite_awvalid/awready`、`wvalid/wready`、`bvalid/bready` | 6 | 写命令(SET_WRGO)通道握手（怀疑"写后紧接读"竞争） |
| `dbg_lite_wr_cmd` + `dbg_lite_wr_addr[5:0]` | 7 | 内部写命令脉冲+地址（`+0x48` 的写 go 命令可见） |
| `dbg_lite_hang_st`（派生 1b） | 1 | `= arvalid & arready & ~rvalid`（可直接做触发条件；避免慢仪器漏看） |

可选（有空间再加）：`dbg_lite_rdata[31:0]`（32b，判读返回值）、`dbg_lite_hang_cnt[15:0]`（hang 周期计数，1 个 sticky 标志更佳）。

**B. user↔ui 握手 / 写引擎（user 域，建议 ILA0@user；最小 ~10 bit）**：

| 建议探针名 | 宽 | 说明 |
|---|---|---|
| `dbg_u_r_req` / `dbg_u_r_ack` | 2 | 用户域读请求/应答（异步跨域握手） |
| `dbg_u_d_req` / `dbg_u_d_ack` | 2 | 用户域数据请求/应答 |
| `dbg_u_wdst[3:0]` | 4 | 写目标/状态码 |
| `dbg_u_wpending` / `dbg_u_dma_wr_go` / `dbg_u_dma_wr_toggle` / `dbg_u_dma_wr_pending` | 4 | 写挂起/GO/toggle/pending（GO 是否发出、pending 是否被清） |

**C. ui 域桥侧（@ui_clk，建议 ILA3@ui；最小 6 bit）**：`dbg_wdst[3:0]`、`dbg_wpending`、`dbg_dma_wr_go`。另建议 1b 派生 `dbg_go_read_race = set_wrgo_pulse & (lite_arvalid | lite_rvalid)` 做触发。

**预算与取舍**（当前 ILA0=92+9b、ILA3=152b，300MHz 已紧）：
- ILA0：A+B 最小约 **34b**（不含 rdata）；建议**临时移走 `dbg_mem2_u_wr/u_rd[16+16]` 或 probe1 9b**（S8c 不在楔死段判）后再加，避免超 130b；
- ILA3：C 最小 **6b**（→158b），若时序吃紧先只留 `dbg_dma_wr_go`+`dbg_wpending`（2b）；
- 若两域都要大窗口，考虑新增独立 `u_ila_4 @user`（约 64b）承担 A+B，ILA0/3 不动——代价是 45–60min 重综合 + 时序余量。
- 命名统一 `dbg_*` 并在 `build_synth_only.tcl`/`build_debug.tcl` 用 `bus_nets/one_net` 接入；新 ltx 归档后本工具链**不需要改判据**（新探针只进 dump/触发，不进硬判）。

---

## 5. 判据口径要点（与 R1 一致处引用 `out\S0S8_DESIGN.md`）

1. **NIC 主判据 = `ReceivedBytes`**：静态 ARP 环境下板端学不到 PC MAC ⇒ 板自发帧 dst=`ff:ff:ff:ff:ff:ff`（广播）⇒ `ReceivedUnicast` 恒 0。单帧 ICMP 回包 74B，ping×4=296B；`ReceivedBroadcastPackets` 仅辅助打印。用 Unicast 会假 FAIL（R1 `[L3]` 定案）。
2. **`'d'` 是翻转命令**：一律走 `Set-EngineMode`（`'U'` 回读 mode+`req.bit24` 双重确认，最多 3 次）；不要盲发两次。
3. **ping 前不跑 M/A/B 轮**：轮末 `R_ENGINE=0`/`R_MODE=RND`；S4/S5 在 S3/S3b 之后、J3 之前。
4. **S2 不发 `'d'`**：身份判据前提；不要为凑判据发 `'d'`，否则剩 NOT_OBTAINED。
5. **J3 = 带 `--dma`、nslots 默认 256、失败不重试**：`wr+255`/收帧停摆/`WAITWR-FAIL` ⇒ 判据未取得 + 板卡需重烧（重试会级联假 FAIL 甚至楔死）。
6. **J4 口径**：mem/mem2 各自 `wm==wr_frm==rd_frm`、`ost=0`、错误计数 0；两桥分别判。
7. **R2 新口径（Lead 最终版）**：`WR_DBG.fault==1 ⇒ FAIL`（粘滞；恢复=软核写 `+0x4C`（opcode 0x06）ACK，PC 只提示）；S3/S4 打印 s2sr；S4 emit 期望 `len_tab=86`；**TKEEP_SUSPECT** 标记——若 ping 通但 S7/S8/S9 字节级判据失败，自动在判据行标注“优先怀疑 S2MM 尾拍 TKEEP→WSTRB `[L1]`”。
8. **10MB 质量档 = `json_storm.py` 源码默认参数**（chunk=1466B/CHUNK_MAX、gap-ms=1.0ms）；**不传 `--pace-us`**（节拍档是吞吐量测，不属于质量档）。判据额外做 PowerShell 独立 SHA 复算。
9. **S10 数据来源**：默认复用 S6 post CSV（不另开 Vivado 会话）；如需 J3 后最终快照，用 `-IlacapUiPost/-IlacapUserPost` 显式给。
10. **异常/超时口径（DESIGN v1.2 §13/§14，审计 A3–A6）**：四类看门狗统一 **24 位 `0xFFFFFF` ≈56ms@300MHz**（§4.3 旧“WAITDONE 2^25≈112ms”**作废**）。
    - **WAITGO 超时 = 良性丢帧**：丢帧 / `pending=0` / `stat_wr_timeout++` / **不置 fault、不停泊**（S2b 身份判据依赖该行为；陈旧 GO 窗口由固件“写 LENGTH/翻 GO 前二次确认 pending&&toggle”兜底）。
    - **STREAM/PUSH/WAITDONE 超时 = fail-stop**：`fault=1` + 停泊 `WD_HALT(6)` + 不 commit；唯一出口 = 软核恢复序列 `S2MM_DMACR=0x4(reset)→等 Halted=1→0x1001(RS+IOC)→清 IOC→写 +0x4C(opcode 0x06) 翻 ACK`。
    - 由此：S2 的 `WR_REQ.pending` 只在 **~56ms 窗口**内可能为 1；ping 后隔久读到 pending=0 属预期（良性丢帧），**均只作 INFO**。
11. **D8/A11：桥① `ro_lat_w` 恒 0**（AXI 写口退役后；B3-0 口径只对桥②/HAS_DMA=0 有意义）⇒ **禁止用 `GET_LATENCY` 的桥① 值做判据**。
12. **A12：`WR_DBG.last_alloc_slot` = 最近分配槽号；`last_commit_len` = 最近提交帧长**（分配≠提交）——只作取证解释，不硬判。
13. **D4/A9 与 A3/G2 的等级边界**：离线 TB 只证 DUT 输出流（TKEEP/TLAST/字节），**不证厂商 IP 的 TKEEP→WSTRB/IOC 行为**（归板验 S4 后升 L3）；STREAM/PUSH 看门狗分支离线未触发（仅代码审查 `[L1]`），板验靠 `dbg_s2mm_state=6/HALT` + `fault` 观测承接。
14. **本轮构建未收口（NO_BITSTREAM，[L2] 离线事实）**：5 掷均被时序门限拒收（`ExtraTimingOpt` −0.098 / `WLDrivenBlockPlacement` −0.225 / `ExtraPostPlacementOpt` −0.175；`Default` = MIG 瞬态 `Opt 31-306`；`AggressiveExplore` = 布局器放不下）⇒ **无 R2 位流，S0 依赖项 NOT_OBTAINED、板验未执行（S2–S11 SKIP）**。失败诊断（`rpt2_ExtraPostPlacementOpt.worst.rpt`）：25/30 最差路径 = `u_mem/u_wr_bytes/wr_gray_s2_reg[3]` → `u_mem/u_bridge/g_wr_dma.wd_data_r_reg[*]/CE`（3.238ns，route 56.6%，slack −0.175），另 5/30 为桥② 旧写 FSM 同族（未被 R2 改动）。**下次开工第一步**按 `BUILD_STATUS.md` §3 主修（新写引擎字节捕获加 1 级流水、不动 `HAS_DMA=0`），备选：裁 ILA3 低价值探针后重综合 / 追加 place 指令 / 单掷 `build_debug.tcl`。
15. **round2b ILA 探针集裁剪（2026-10-18 12:5x，[L2] 以 build_synth_only.tcl/build_debug.tcl 磁盘为准）**：为省 300MHz 布线余量（round2 place/route 首掷 WNS 仍 −0.135、`AggressiveExplore` 布局失败），**不改 RTL**、只裁 ILA：ILA1@eth_rxc / ILA2@user_clk_b 整核移除；ILA0 probe0 374→92 bit；ILA3 probe0 184→152 bit；裁掉 `dbg_mem_bresp`/`dbg_mem_wslot`/`dbg_mem_rslot`。**判据边界=缺失探针列 INFO/NOT_OBTAINED（判据未取得≠失败，§6a）**：S6/S10 不因缺 ILA1/2 报错；recon 对上述被裁列缺失不判 FAIL（selftest 5/5 覆盖）；S10 仍用桥① ui `wm/wr_frm/rd_frm/stall/len_err/ost` + 桥② ui 四计数 + user 侧 `u_wr/u_rd/u_drop/ost_s/mem2_u_*`。
16. **round2c 成功构建 + S0 PASS（2026-10-18 14:4x，[L2]）**：`ExtraTimingOpt` 过门限——`V5_SWEEP2_OK: directive=ExtraTimingOpt wns=0.004 whs=0.004`（`build_r2_sweep2.log` L2764）；`SWEEP2_ExtraTimingOpt: WNS=0.004 WHS=0.004`（L2659）；DRC 0 Errors/22 Warnings；`write_bitstream completed successfully`。归档 `out\archive\b31b_r2_2026-10-18\`；位流 `aurora_mem_bridge_r2_28921C6B.bit`（10,266,180 B、`28921C6B…`）、ltx `probes_r2_28921C6B.ltx`（64,593 B、`4AC25546…`）、xsa `16A4F01F…`、ELF `1bc8088d`、RTL bridge blob `f43267db…`（ARM 时序修复版）。**S0 dry-run PASS 一行**：`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`（另 xsa hash8 `16a4f01f` 与期望一致 ✓；日志 `evidence_2026-10-18\R2_20261018_144715.log`）。⚠️ `r2_board.ps1` 的 **okMarker 之前不识别 `V5_SWEEP2_OK`** 会误判 S0 FAIL——Lead 已修复（`okMarker`/`bitInLog` 正则加 `V5_SWEEP2_OK`）；script-tools 已复验 BOM+ParseFile 并把 round2c 常量/归档目录写入脚本（新 hash 见 §1）。
17. **round2d 板验初场结论 + 判据修正（2026-10-18 16:3x–16:5x，[L2] 离线事实 + [L3] 板证）**：
    - **S0 PASS、S1 PASS、S3 PASS**（S3：`'d'` 后 mode=1 & bit24=1；S2/S3b 本轮按旧口径 FAIL，已定位为**判据建模错误**而非板故障）。
    - **`'U' wmwr`(+0x08)=`u_wr_frame` 是收帧接受计数**：RTL `frame_mem_if.v` L341-348 在 `wr_last` 且未 drop 时 `u_wr_frame_cnt+1`，**早于 commit**；`axi_lite_regs.v` L16/70/464 证实 0x08=u_wr_frame。R2 未服务阶段每来一帧（含 Windows 广播）都会 +1，随后被 WAITGO 良性丢帧清 pending ⇒ **旧 S2 的 `wmwr delta=0` 硬判必然假 FAIL**。
    - **提交证据 = `WR_DBG.last_commit_len`**（commit 时=帧长）：run2 S2 后置 `WR_DBG=0x00010000` ⇒ `last_commit_len=0` ⇒ 身份成立。**新 S2 硬判**=ping 0/1 + NIC Bytes delta=0 + last_commit_len==0 + fault==0；wmwr delta 仅 INFO。
    - **旧 S3b 的 `wmwr==wmrd` 在 R2 下不可达**（良性丢帧使 u_wr_frame 永久多计）；**新 S3b 静默窗**=pending==0 && fault==0（& bit25=0）连续两拍，wmwr/wmrd/backlog 仅 INFO。S9 J3 前置同步改用新口径（同一 helper）。
    - 工具改动已落地：`r2_board.ps1` S2/S3b 判据与文案、S0 ELF 常量（候选 `1e3a42db`/旧 `1bc8088d` 兼容 WARN）、头部 round2d 注记；`r2_ilacap.tcl` 新增 `R2_TRIGGER_*`（§4.5）；README 本节/§4.5/§4.6/风险同步。
18. **round2d 固件阻塞缺陷修复（[L2] Lead JTAG 实证 + [L3] 板证）**：`serve_write_once` 的 `dread()` **2 次读**在紧循环交替地址（0x44/0x40）时仍滞后 >1 笔 ⇒ 固件从不看到 `pending`（JTAG 读固件全局：`pending_seen=0 / arm_cnt=0`）。**改 3 读**后 `pending_seen=1 / arm_cnt=1 / WRREQ=0x80010056`；修后 `'I'` 命令 = **wr6/rd3**，ILA `dbg_mem_wm=5 / dbg_mem_rd_frm=5 / WR_DBG.last_commit_len=86` ⇒ **S2MM commit 与 MM2S 读出都发生**（写引擎可被服务）。**候选 ELF = `1e3a42db`（50,944 B）**（尚未归档；旧冻结 `1bc8088d` 50,896 B 即本缺陷版）。工具 S0 已把候选设为 `KnownR2ElfHash8`（旧值保留为 `KnownR2ElfPrevHash8`，二者 -Expect 均不告警）。
19. **round2d 未收口项（勿当"通过"）**：
    - **A. AXI 总线楔死（[L1] 假说）**：高频 `serve_any()`（~143kHz Lite 读）后 MicroBlaze 挂死在 `dread()` volatile load（PC 定位 `lwi`，标记定位 `g_dbg_addr=0x44A00034` = lite_regs DMA_REQ 读）；UART 静默、`rst -processor` 不恢复、**只能重配 FPGA**；1ms 限速可多次存活但**非确定性** ⇒ 疑 lite_regs 写命令(SET_WRGO)后紧接读的握手竞争。**待**：按 §4.6 加 AXI-Lite 握手/用户域 req-ack 探针，重综合（~45–60min）后用 §4.5 触发式 ILA 复现抓波形定案。
    - **B. TX 无帧**：`rd_frm` 增长但 ping 0/4、NIC `ReceivedBytes` delta=0（eth 域 ILA 已裁掉 ⇒ 第二跳不可见）。**待**：补 eth/TX 侧探针或分段 ILA 后再判；当前不得写成"通过"。
    - 两条都未取得判据 ⇒ S4–S11 仍 PENDING；本轮 S6/S10 CSV 只作格式/探针验证（计数 delta=0 是 S2/S3b 未进入服务链的结果），不入 S6/S10 判据。

---

## 6. 已知风险 / 未覆盖项（Lead 需知）

| # | 风险/缺口 | 当前处置（默认） |
|---|---|---|
| R1 | **桥② 无错误计数 ILA 探针**（Lead 裁决：不加，省 300MHz ILA 余量）：prj11 ILA3 只挂 `dbg_mem2_wm/wr_frm/rd_frm/ost` ⇒ 桥②“错误计数 0”**不可观测**（RTL 本轮未动，语义同 R1） | recon 记 INFO 正确；**S10 对桥② 只硬判 `wm==wr_frm==rd_frm` + `ost` 前后/当前 0**（错误计数不作判据） |
| R2 | s2sr 错误位定义未在本板实测（直通非 SG）；**Lead 裁决 Halted 期望=0**（`'d'` 后已 RS=1；Halted=1 = S2MM 通道没起来 ⇒ 现场重要线索） | 首次上板默认 WARN + 打印原始值；`-StrictS2sr` 复跑时硬判 Halted=0&errbits=0 |
| R2b | **timeout 计数上板不可观测**：`dbg_wr_timeout` 未挂 ILA（有意）+ `stat_wr_timeout` 无 Lite 读回路径（不在 `+0x40/+0x44`） | recon 记 INFO 不硬判；用可观测替代物解释现场：`dbg_s2mm_state` 编码（0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT）+ `dbg_wr_fault` + `'U'` wreq/wdbg/s2sr + `ro_wm` 推进 |
| R2c | 桥① `dbg_mem_bresp` 在 S2MM 写路径恒 0（IP 内部 BRESP 不可见） | 仅 INFO（recon 已按此实现） |
| R3 | `fault` 恢复（`+0x4C` ACK）是软核/固件路径，PC 脚本只读不写 | S3/S9 失败现场打印 fault/s2sr 并提示“需软核 ACK 恢复或重烧”；**不重试** |
| R4 | S6 自动抓取需：hw_server/JTAG 可用 + ltx 与在位位流配套 + 探针名匹配 | 失败一律 `NOT_OBTAINED` 并打印 vivado 日志路径/探针 dump；可改用手工 CSV |
| R5 | S6 期望增量 = ping 次数（默认 4）；若改 `-IlaExpectPing` 必须与 stim 命令的 `-n` 一致 | 两者同参控制（S6 用同一变量拼 `ping -n N` 与 `--expect-delta N`） |
| R6 | S10 用的是 S6 post 快照（ping×4 后累计）；J3 之后若想再对账需另给 CSV | 按 Lead 裁决：cumulative 静默口径即可，不再开 Vivado 会话 |
| R7 | `udp_verify_ddr.py`/`json_storm.py` 绑定 UDP 1234；端口被占则实验无效 | dry-run 会检查 1234 监听；失败判 `NOT_OBTAINED` 不判 FAIL |
| R8 | 板卡 wedge（历史 ×2）/ xsct TCF 失败（坑 #49） | 现象出现时按坑账本处置（断电重上），本工具链不自动重试 |
| R9 | 10MB `--out` 重组文件 = 10,293,111 B，落 evidence 目录；多次跑会累积 | 文件名带 `<ts>`；确认后可手工清理旧 `.recomposed.jsonl` |
| R10 | S0 DRC 判据依赖构建日志含 `DRC finished with N Errors` 行（R1/R2 sweep 流程实证有） | 日志无该行 ⇒ S0 `NOT_OBTAINED`（`-SkipDrcRequirement` 可降级） |
| R11 | **桥① `ro_lat_w` 恒 0**（D8/A11：写口退役；B3-0 口径只对桥②） | 本工具链**不使用** GET_LATENCY/桥① lat_w 作判据；README/脚本已标注 |
| R12 | **STREAM/PUSH 看门狗分支离线未触发**（A3/G2：T9 只触发 WAITDONE 同构路径）⇒ 该分支结构仅代码审查 `[L1]` | 板验靠 `dbg_s2mm_state=6(HALT)` + `dbg_wr_fault` + `'U'` 现场承接；不预先写成结论 |
| R13 | **WAITGO 超时良性丢帧**（~56ms）⇒ S2/S3 的 `pending` 观测有窗口限制 | pending 仅 INFO（1=窗口内挂起；0=已良性丢帧/无帧触发均正常）；不硬判 |
| **R14** | ~~本轮构建 NO_BITSTREAM~~ **已解除（round2c 通过）**：round1 5 掷时序门限全败；round2c `V5_SWEEP2_OK` WNS+0.004/WHS+0.004、DRC 0E/22W、位流已出 | 历史见 §4.1 下方 round1 归档 `b31b_r2_2026-10-17\BUILD_STATUS.md`；当前以 round2c 归档为准 |
| **R15** | **默认名/在库产物身份**：round2c 后 `out\aurora_mem_bridge.bit` 已变为 R2 `28921c6b`（10-18 14:43），`out\mb_ctrl.xsa` 亦为新版；但默认名会被下次构建覆盖 | **判据只认归档绝对路径+实算 hash**；`-Bit` 用 `archive\b31b_r2_2026-10-18\aurora_mem_bridge_r2_28921C6B.bit`；R1 `c8cd3a32` 仅在旧归档作历史参照 |
| **R16** | `out\probes_v5_ExtraTimingOpt.ltx` 是**失败轮 ILA 网表**（R2 新探针名可见，可用于核对探针名），不是与成功位流配对的 ltx | 不作为 R2 上板判据配套 ltx；成功位流后归档为 `probes_r2_<bit8>.ltx` 再用于 `-IlaLtx` |
| **R17** | **round2b ILA 裁剪**：ILA1/ILA2 整核移除、ILA0 92b/ILA3 152b、裁掉 `dbg_mem_bresp/wslot/rslot`（本轮不可观测） | S6/S10 不因缺 ILA1/2 报错；被裁列缺失记 **INFO/NOT_OBTAINED（判据未取得≠失败）**，recon 不判 FAIL；S10 仍硬判 trios+ost+`stall/len_err`+`dbg_wr_fault`；详见 §4.4 |
| **R18** | ~~round2b 位流尚未产出~~ **已解除**：round2c 位流 `28921c6b` 已归档（WNS+0.004/WHS+0.004）；RTL bridge blob `f43267db…`（ARM 时序修复版）、ELF `1bc8088d` 不变 | S0 已钉并 dry-run PASS；板验进行中（S1–S11） |
| **R19** | ~~归档 `SHA256.txt` 头部旧 RTL blob `06e6bd72…`~~ **已修复（2026-10-18 14:53 升级版清单）**：头部现写 `f43267db…`；清单升级为 **27 项**（新增 BUILD_STATUS/congestion_iter_3/4/diag 探针）；清单自身 3,243 B、`73fb1aae…`（以磁盘复算为准） | 以实测 blob/SHA256 为准；R19 关闭 |
| **R20** | **固件 Lite 读滞后缺陷**：`serve_write_once` 的 `dread()` 2 读在紧循环交替地址(0x44/0x40)仍滞后 >1 笔 ⇒ 看不到 pending（JTAG 实证 pending_seen=0/arm_cnt=0；改 3 读后 pending_seen=1/arm_cnt=1） | 修出**候选 ELF `1e3a42db`（50,944 B）**；S0 已知固件常量已含候选+旧值；归档后 `-ExpectElfHash8 1E3A42DB` 钉死 |
| **R21** | **AXI 总线楔死（[L1] 假说）**：高频 `serve_any()`(~143kHz Lite 读)后 MicroBlaze 挂死在 `dread()` volatile load（PC `lwi`；`g_dbg_addr=0x44A00034`=lite_regs DMA_REQ 读）；UART 静默、`rst -processor` 不恢复、只能重配 FPGA；1ms 限速可多次存活但非确定性 ⇒ 疑 SET_WRGO 写后紧接读的握手竞争 | 待重建加 §4.6 探针 + §4.5 触发式 ILA 复现；**定案前不得写"通过/根因"**（仅 [L1] 假说） |
| **R22** | **TX 无帧**：`rd_frm` 增长但 ping 0/4、NIC `ReceivedBytes` delta=0；eth 域 ILA 已在 round2b 裁掉 ⇒ 第二跳当前不可见 | 需补 eth/TX 侧探针或分段 ILA；在此之前 S4–S11 全 PENDING，不得用本轮数据判"通过" |
| **R23** | **旧 S2/S3b 判据建模错误**（`wmwr`=收帧接受计数 ≠ 提交；良性丢帧使 `wmwr==wmrd` 不可达） | 已按 RTL 证据修正（新 S2=commit_len/fault；新 S3b=pending/fault 两拍）；本轮旧结果作废、不据此判板 |

---

## 7. dry-run 自证结果（`out\r2_dryrun.log`，2026-10-18 16:5x，v1.9 round2d）

`r2_dryrun.ps1` 一次跑 7 项，**7/7 PASS**（可直接复跑）。**注意：这是工具链自证，不是板上判据；本轮板验未执行。**

| # | 自证项 | 结果 |
|---|---|---|
| 1 | 全部 `r2_*.ps1`：BOM `EFBBBF` + PS5.1 `ParseFile` 0 错 | PASS（3/3 文件 0 语法错误） |
| 2 | `r2_counter_recon.py` `py_compile` | PASS（exit=0） |
| 3 | `r2_counter_recon.py --mode selftest`（正/负对照 5 例） | PASS 5/5（负向均精确指认到判据行） |
| 4 | `r2_ilacap.tcl` 结构完整性 + **ASCII-only**（引号/花括号/方括号/行尾 `#`/非 ASCII 字节=FAIL） | PASS（纯 ASCII；Vivado 按 GBK 解码 Tcl 源，见坑 #1 同族） |
| 5 | `r2_board.ps1` DRY-RUN（R1 归档 fixture 真校验：SHA/日志 WNS=0.004 WHS=0.004 DRC=0/串口枚举 COM5 在列/邻居 Permanent/NIC 实测） | PASS（GUARD 5 项全 0 + `R2_RESULT: SKIP`） |
| 6 | `r2_mb10_sha.ps1` DRY-RUN（10MB 源 SHA 与钉死一致、json_storm 源码默认参数实测、端口 FREE） | PASS（未建 socket/未发送） |
| 7 | 只读纪律：R1 参考脚本/设计文档自证前后 SHA256 不变 | PASS（7 个 R1 资产 hash 全部不变） |

dry-run 中实做的**只读真校验**：工件 SHA256（bit `c8cd3a32`/ELF `2961b585` 与 R1 归档一致）、构建日志解析（WNS/WHS/标记/DRC）、串口 PnP 枚举（COM5 在列）、静态邻居（Permanent + MAC 一致）、NIC 计数、工具齐备、ILA ltx 存在性、10MB 源 SHA、json_storm 参数、UDP 1234 端口状态。

> 说明：dry-run 试跑用 **R1 归档工件作 fixture**（`c8cd3a32`+`2961b585`+`build_retire_fix_sweep.log`），目的是证明“只读检查是真校验”而非空转；R2 最终工件到位后把 `-Bit/-Elf/-BuildLog` 换成 R2 归档路径重跑即可（`-ExpectElfHash8 1bc8088d`）。

---

## 8. 依据等级与引用

- **round2d 板验初场结论（2026-10-18 16:3x–16:5x；`[L2]` 离线事实 + `[L3]` 板证；未收口）**：
  - **S0 PASS、S1 PASS、S3 PASS**（S3：`'d'` 后 mode=1 & bit24=1）。**S2/S3b 本轮旧口径 FAIL 判定作废**（见 §5-17：wmwr=收帧接受计数、wmwr==wmrd 在 R2 不可达），新判据已落地；S4–S11 仍 PENDING。
  - **固件缺陷已修**（R20）：`dread()` 2 读→3 读；候选 ELF `1e3a42db`（50,944 B）；修后 `'I'`=wr6/rd3、ILA `dbg_mem_wm=5/rd_frm=5/WR_DBG.last_commit_len=86` ⇒ 写引擎可被服务 [L3]。
  - **未收口 A/B**（R21/R22）：AXI 楔死仅为 `[L1]` 假说（高频 serve_any 后 MB 挂死 dread lwi，`g_dbg_addr=0x44A00034`；UART 静默/rst-processor 不恢复/只能重配 FPGA；1ms 限速非确定性；疑 SET_WRGO 写后读竞争）；TX 无帧（`rd_frm` 增长但 ping 0/4、NIC delta=0；eth ILA 已裁掉需补探针）。
  - 证据：会话记录 `evidence_2026-10-18\R2_board_session_20261018.md`、`r2_board_run2_20261018.log`、`R2_ila_r2_20261018_163530_*.csv`、`r2cap_*.log`、`r2_manual_*.log`、`r2_jtag_*.log`（Lead 落盘）。工具侧复算（`r2_counter_recon.py --mode delta`）与板脚本结论一致：delta 全 +0（服务链未进入），只作格式验证不入判据。
  - **触发式 ILA 已就绪**：`r2_ilacap.tcl` `R2_TRIGGER_*`（§4.5）+ 重建探针清单（§4.6），供复现楔死。
- **round2c 结论（2026-10-18 14:4x，`[L2]` 离线事实）**：
  - 构建 **PASS（过门限）**：`build_r2_sweep2.log` `SWEEP2_ExtraTimingOpt: WNS=0.004 WHS=0.004`（L2659）+ `V5_SWEEP2_OK: directive=ExtraTimingOpt wns=0.004 whs=0.004 bit=...`（L2764）；DRC `0 Errors, 22 Warnings`；`write_bitstream completed successfully`。
  - 归档 `out\archive\b31b_r2_2026-10-18\`（**27 项清单 + `SHA256.txt`（28 文件）**，清单 2026-10-18 14:53 升级版）：bit `28921C6B…` 10,266,180 B；ltx `4AC25546…` 64,593 B；xsa `16A4F01F…`；ELF `1BC8088D…`；RTL bridge blob 实测 `f43267db…`（升级版清单头部已更正，R19 关闭）；清单自身 3,243 B、`73fb1aae…`（以磁盘复算为准）。
  - **S0 离线 PASS**（dry-run，未碰板）：`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`；日志 `evidence_2026-10-18\R2_20261018_144715.log`（`ef05a653…`）。
  - **lead 修复留痕**：`r2_board.ps1` okMarker 曾不识别 `V5_SWEEP2_OK`（会误判 S0 FAIL）；Lead 已修，script-tools 复验 BOM/ParseFile + 补 round2c 常量（新 hash 见 §1）。
- **round1 场次（历史，`[L2]`）**：构建 NO_BITSTREAM（5 掷时序门限全败）；权威 `archive\b31b_r2_2026-10-17\BUILD_STATUS.md` §1；失败诊断 25/30 新写引擎 CE 锥 + 5/30 桥② 旧 FSM。
- **round2/round2b（历史，`[L2]`）**：round2 place/route 首掷 WNS −0.135（`AggressiveExplore` 布局失败）⇒ 裁 ILA 探针（ILA1/2 整核移除、ILA0 374→92b、ILA3 184→152b、裁 bresp/wslot/rslot）后 round2c 收敛到 +0.004。
- `[L1-设计]`：R2 机制（S2MM TKEEP→WSTRB、IOC 时刻、S2MM 拆 burst）来自 DESIGN §6/§12，未板上实测；本工具链以 S4/S7/S8/S9 覆盖并标 `TKEEP_SUSPECT`。
- `[L2-离线]`：本工具链自身（dry-run 自证、recon 正负自检、Tcl 结构检查）+ 构建/扫描/诊断日志。
- `[L3-板证]`：round2d S0/S1/S3 PASS；圆2d 修后服务证据（'I'=wr6/rd3、ILA wm=5/rd_frm=5/commit_len=86）；引用 R1：NIC=`ReceivedBytes`、J3 失败纪律、J4 双桥口径。
- 依据文件：`AGENTS.md` §6a/§七/§八/§九 #17/#18/#40/#43/#45/#46/#53/#55/#56、§十二；`out\S0S8_DESIGN.md`；`out\R2_S2MM_DESIGN.md`（v1.3）；`evidence_2026-10-17\R1_evidence_index.md`；`out\archive\b31b_r2_2026-10-18\{SHA256.txt,rpt2_ExtraTimingOpt.timing_summary.rpt}`；`out\archive\b31b_r2_2026-10-17\{BUILD_STATUS.md,SHA256.txt}`；`evidence_2026-10-18\R2_board_session_20261018.md`；`prj\project_9\scripts\json_storm.py`；`prj\project_10\prj_loop\scripts\udp_verify_ddr.py`。
- Lead 裁决记录：2026-10-17 22:0x 口径确认（COM5 默认/S2 三项硬判/pending INFO/S3 fault 硬判/s2sr 建议断言/ILA 探针位置/S10 错误计数口径/10MB 默认参数/J3 retired 标签/S1 不烧绿）→ 22:2x–22:3x **v1.1 冻结**（`'U'` 三行 wreq/wdbg/s2sr、`+0x4C` ACK（opcode 0x06）、fault 硬判、S4 s2sr/TKEEP_SUSPECT）→ 22:3x v1.2 回填（timeout 不挂 ILA/无 Lite 读回路径、Halted 期望 0）→ **22:4x 最终**：ELF `1bc8088d`（50,896 B，blob `ee256c05`；fa38a8cd/67c0b73a 作废）+ `R2_S2MM_DESIGN.md` v1.2 文档对齐（A3–A6/A11/A12/D1–D8：超时统一 56ms、WAITGO 良性丢帧 vs STREAM/PUSH/WAITDONE fail-stop、fault 恢复序列、桥① lat_w 恒 0 禁作判据、alloc≠commit）。

---

## 9. 变更记录

| 版本 | 内容 |
|---|---|
| v1.0（22:1x） | 初版交付：`r2_board.ps1`(S0–S11) / `r2_ilacap.tcl` / `r2_counter_recon.py`(含 5 例正负自检) / `r2_mb10_sha.ps1` / `r2_dryrun.ps1` + `r2_dryrun.log`；S0–S11 判据与 R1 口径对齐 |
| v1.1（22:2x–22:3x） | 同步 Lead「RTL/固件冻结」：`'U'` 新增 `wreq/wdbg/s2sr` 解析；S3 `fault=1 ⇒ FAIL`+s2sr；S4 打印 s2sr/emit + `TKEEP_SUSPECT`；S9 失败先查 fault；S10 错误计数口径（`len_err/stall`+`dbg_wr_fault`，mem bresp INFO）；ILA 探针新名字（`dbg_s2mm_*`）与 ui/user 双 ILA 列合并；S0 冻结 ELF `67c0b73a`/xsa/`out/r2_{synth,sweep}.log` 自动发现；`-Xsa/-ExpectXsaHash8/-StrictS2sr` 新参数；重跑 dry-run 7/7 PASS |
| v1.2（22:2x–22:3x，待命期） | 机械对齐最终 `build_synth_only.tcl`/`build_debug.tcl` 探针：`r2_ilacap.tcl` **重写为纯 ASCII**（Vivado GBK 解码纪律）+ `R2_EXPECT_PROBES` 五探针存在性核对（UI/User ILA 双 fallback）；`r2_counter_recon.py` 对齐实际探针清单（移除未挂的 req_tog、timeout 记 INFO、`--check-tcl` 增加非 ASCII 字节 FAIL）；归档命名改为 Lead 最终版（`probes_r2_<bit8>.ltx`/`j3_soft_r2_67c0b73a.elf`/`mb_ctrl_r2.xsa`/`build_r2_{synth,sweep}.log`）并自动发现；Lead 裁决回填（桥② 不加错误探针/S10 仅硬判三计数+ost/Halted 期望 0）；重跑 dry-run 7/7 PASS |
| v1.3（22:3x，待命期） | 回填 Lead 最终裁决：`dbg_wr_timeout` 不挂 ILA 为**有意**（省 300MHz ILA3 余量）+ `stat_wr_timeout` **无 Lite 读回路径**（不在 +0x40/+0x44）⇒ 上板不可观测仅 INFO；`r2_counter_recon.py` 新增 `dbg_s2mm_state` 解码（0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT）与"观测能力说明"INFO 块（桥① bresp 恒 0 INFO / 桥② 无错误探针 INFO / timeout 不可观测 + 可观测替代物）；`r2_ilacap.tcl`/`r2_board.ps1` 文案同步；重跑 dry-run 7/7 PASS |
| v1.4（22:4x，待命期） | **ELF 最终冻结 `1bc8088d`（50,896 B，blob `ee256c05`；fa38a8cd/67c0b73a 作废）** 同步到 `r2_board.ps1` 常量/S0 提示/归档名/示例/证据索引；`R2_S2MM_DESIGN.md` **v1.2** 文档对齐同步：超时统一 24b `0xFFFFFF`≈56ms（旧 WAITDONE 112ms 作废）、WAITGO 良性丢帧（不 fault/不停泊，S2 pending 仅 ~56ms 窗口 INFO）vs STREAM/PUSH/WAITDONE fail-stop（fault=1→WD_HALT(6)，恢复=软核 DMACR reset→RS+IOC→清 IOC→+0x4C opcode 0x06 翻 ACK）、寄存器 opcode 0x05/0x06 细化、D8 桥① lat_w 恒 0 禁作判据、A12 alloc≠commit、D4/A9 与 A3/G2 等级边界；重跑 dry-run 7/7 PASS |
| v1.5（2026-10-18 01:0x，收尾） | **按构建收口结果更新工具文档**：本轮 **NO_BITSTREAM**（5 掷时序门限全败，无 R2 位流）⇒ S0 依赖项 NOT_OBTAINED、板验未执行（S2–S11 全部 SKIP）；`r2_board.ps1` 仅改文案/判定口径（S0 无位流=NOT_OBTAINED；`-Run` 缺 `-Bit` ⇒ `NOT_OBTAINED ARG` + 等下一次成功位流；S1/S2 dry-run 计划加"本次场次无位流"提示；SWEEP2 标记解析与失败标记扩展），**判据一条未删**；README §4.1 改为"本轮实际状态"（R2 位流/ltx/xsa 均未产出；在库产物仍是 R1 `c8cd3a32`/`c9b52dd7`；失败轮 ILA 网表 `probes_v5_ExtraTimingOpt.ltx` 仅核对探针名）、§5 增加构建未收口与失败诊断+修复建议、§6 增加 R14–R16 风险、§7/§8 标注"工具链自证≠板上判据"并登记本轮事实与记录正文；重跑 dry-run 7/7 PASS |
| v1.6（2026-10-18 12:5x，round2b） | **同步 round2b ILA 探针集裁剪**：ILA1@eth_rxc/ILA2@user_clk_b 整核移除、ILA0 probe0 374→92b、ILA3 probe0 184→152b、裁掉 `dbg_mem_bresp/wslot/rslot`（判据边界=缺失探针列 INFO/NOT_OBTAINED，不判 FAIL）。工具改动：`r2_counter_recon.py` 增加 round2b 常量/说明、mem.bresp 缺失由 NOT_OBTAINED 改为 **INFO**、新增"观测能力说明 round2b"行、delta/recon 输出标注裁列；`r2_ilacap.tcl` 更新 round2b 探针布局/期望宽度注释 + 运行时打印 `R2CAP_ROUND2B/TRIMMED_ABSENT/R2PROBE_ALL_COUNT`（不因缺 ILA1/2 报错）；`r2_board.ps1` S6/S10 计划文案改为裁剪后口径。**S10 仍硬判 trios+ost+stall/len_err+dbg_wr_fault**；dry-run 重跑 **7/7 PASS**；新 hash 见 §1。证据目录按日期动态（本轮 `evidence_2026-10-18\`）。 |
| v1.7（2026-10-18 14:5x，round2c 位流钉 S0） | **round2c 成功位流（`V5_SWEEP2_OK` WNS+0.004/WHS+0.004，DRC 0E/22W）钉进 S0 口径**：`-ExpectBitHash8 28921C6B`、`-ExpectElfHash8 1BC8088D`、`-ExpectXsaHash8 16A4F01F`、`-IlaLtx probes_r2_28921C6B.ltx`；`r2_board.ps1` 加 round2c 常量（bit/ltx/xsa hash + RTL blob `f43267db`）、`ExpectedArchiveDir` 指向 `archive\b31b_r2_2026-10-18`、构建日志候选加 `build_r2_sweep2.log`、成功标记文案补 `V5_SWEEP2_OK`（Lead 修复 okMarker 误判，已复验 BOM+ParseFile）；**S0 dry-run PASS**（`[JUDGE] S0 PASS: WNS=0.004 WHS=0.004 DRC=0; bit8=28921c6b elf8=1bc8088d okMarker=有`，日志 `R2_20261018_144715.log`）；README §2.2 改 round2c 钉法、§4.1 改 round2c 实际工件表（bit/ltx/xsa/构建日志/时序报告/实 hash）、§4.4 实测裁剪后 ltx 仅 `u_ila_0/u_ila_3`、§5-16 round2c+S0 PASS、R14/R18 解除/R15 更新/R19 blob 笔误、§7 标 v1.7；dry-run 重跑 **7/7 PASS**；新 hash 见 §1 |
| v1.8（2026-10-18 14:5x，归档清单升级同步） | **同步 Lead round2c 归档清单升级**：21 项→**27 项**（新增 `BUILD_STATUS.md`、`congestion_iter_3/4.txt`、`diag_arm_path_probe.tcl`），清单 3,243 B、自身 SHA256 `73fb1aae…`（以磁盘复算为准）；**清单头 RTL blob 笔误已修**（`f43267db`，R19 关闭）；§4.1 更新“27 项+清单（28 文件）”、新增归档证据行（BUILD_STATUS/congestion/diag 实 hash）、§4.4/§6/§8 同步；声称仍沿用 S0 PASS（未重跑，工具/位流未变） |
| v1.9（2026-10-18 16:5x，round2d 板验初场+判据修正） | **按 round2d 板验初场修正 S2/S3b 判据并加触发式 ILA**：S2 硬判改为 ping 0/1 + NIC Bytes delta=0 + WR_DBG.last_commit_len==0 + fault==0（wmwr=u_wr_frame 收帧接受计数，降 INFO）；S3b 静默窗改为 pending==0 & fault==0（& bit25=0）两拍（wmwr==wmrd 在 R2 不可达，弃用；S9 前置同步）；S0 已知 ELF 改候选 1e3a42db（50,944 B，旧 1bc8088d 保留为 Prev 不告警）；2_ilacap.tcl 新增 R2_TRIGGER_PROBE/COMPARE/TIMEOUT_S/POSITION/ARM_MS（armed-before-stim、超时仍上传、标记行）并恢复 out\r2_ilacap.tcl 工作副本 + 同步证据 tools 快照；README 加 §4.5/§4.6、§5-17~19、R20~R23、round2d 结论段；dry-run 重跑 7/7 PASS；新 hash 见 §1 |
