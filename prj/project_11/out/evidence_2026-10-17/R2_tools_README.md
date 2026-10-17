# R2 上板判据工具链说明（prj11 路线 B / B3-2 桥①写侧换层 S2MM）

- **交付者**：Agent Team 成员 `script-tools`（PC/离线侧）；**硬件在环（烧录/串口/JTAG/ping/ILA）由 Lead 亲自执行**。
- **状态（2026-10-18 01:0x 收尾）**：工具链交付完成；**本轮 R2 构建结局 = NO_BITSTREAM（时序门限 WNS≥0 & WHS≥0 拒收，5 掷全败），无 R2 位流；板验未执行（用户要求收尾+断电，板卡未被本次 R2 工作触碰：未烧/未开串口/JTAG/未 ping）⇒ S0 依赖项判 NOT_OBTAINED、S2–S11 全部 SKIP。等下一次成功位流对（先按 `archive\b31b_r2_2026-10-17\BUILD_STATUS.md` §3 主修时序）。** 工具链/判据 G0–G11 一条未删。
- **等级边界**：本工具链不产生任何板上结论；所有机制性描述等级见 AGENTS.md §6a（本文按 `[L1-设计]/[L2-离线]/[L3-板证]` 标注）。本轮仅有 `[L2]` 离线事实（综合 PASS/时序门限失败/失败诊断），**无 `[L3]/[L4]`**。
- **写 scope**：本目录（`out/evidence_2026-10-17/`）+ `out/r2_*`；未改 R1 脚本/未改 prj11 现有文件/未 commit/未碰板卡（`r2_dryrun.log` §7 有只读纪律自证）。
- **配套**：R2 设计草案 `out\R2_S2MM_DESIGN.md`（v1.2）；R1 判据口径 `out\S0S8_DESIGN.md`；R1 证据台账 `evidence_2026-10-17\R1_evidence_index.md`；**构建轮次/失败诊断/修复建议** `out\archive\b31b_r2_2026-10-17\BUILD_STATUS.md`；**记录正文** `C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`（docs 镜像由 Lead 负责）。

---

## 1. 文件清单与指纹（SHA256，实算）

| 文件 | 作用 | 大小 | SHA256 前 8 | SHA256 全量 |
|---|---|---|---|---|
| `out\r2_board.ps1` | **S0–S11 判据总控**（dry-run 默认，`-Run` 才执行；可自动串起 ILA/四档/10MB/J3） | 115,936 B | `ec3ea5ba` | `ec3ea5badb989b015c860a1aae9d1ceb6de0be49d08b67011859b6f07c8ea79b` |
| `out\r2_ilacap.tcl` | ILA PRE/POST 快照抓取（env 参数化；**纯 ASCII**、注释独立成行） | 13,971 B | `fcc262e6` | `fcc262e63b8773f800ca93e92c5a14e5176380472ffcffbf08b09684cf5fdccb` |
| `out\r2_counter_recon.py` | 双桥计数对账（J4 口径）/ ILA 前后差分 / 判据工具正负自检 / Tcl 结构+ASCII 检查 / s2mm_state 解码 | 44,256 B | `a425ad75` | `a425ad75eca3690ea546ba7b98495e3cd7620eabde1c1f574759a2a45daa8a54` |
| `out\r2_mb10_sha.ps1` | 10MB 质量档（json_storm 默认间隔）+ SHA256 判定封装（dry-run 默认） | 22,037 B | `edb2e32b` | `edb2e32bc6ab05d37c4a2820c8ffbc2ef4c5112659e7c80a66975a1729815ca8` |
| `out\r2_dryrun.ps1` | **dry-run 自证一键复现器**（BOM/ParseFile/py_compile/自检/两脚本 dry-run/只读纪律） | 13,588 B | `b65f047a` | `b65f047a7ac74c1a1f10947750f8c634d0a8e260b42755c13af99ecba6007e16` |
| `out\r2_dryrun.log` | 自证输出（7/7 PASS；UTF-8 BOM） | 36,256 B | `dabf05bb` | `dabf05bbd635eacd6af0be17e46cfb997ae50d82e8eaf9bf37c04e0fc179f5fe` |
| `evidence_2026-10-17\R2_20261018_010305.log` | 最后一次 `r2_board.ps1` dry-run 自身日志（UTF-8 BOM） | 19,725 B | `91f49523` | `91f495233e5c38681c5c4982c8cea4058d28c7ae920fe30b79d0b4f6f1ce9079` |
| `evidence_2026-10-17\R2_mb10_20261018_010312.log` | 最后一次 `r2_mb10_sha.ps1` dry-run 自身日志（UTF-8 BOM） | 2,840 B | `9f152915` | `9f1529150c2143c98dc1c0e0683a60de2c51f7ccc40ea553864e2d2987fd8158` |

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

> ⚠️ **本轮场次（2026-10-17 构建）结局 NO_BITSTREAM：无 R2 位流 ⇒ 本命令本轮不可用**（`-Run` 缺 `-Bit` 会按参数/依赖判 `NOT_OBTAINED` 并提示"等下一次成功位流对"）。下列命令是**下一次成功位流对**的模板，判据不变。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 -Run `
    -Bit  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\aurora_mem_bridge_r2_<bit8>.bit `
    -Elf  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\j3_soft_r2_1bc8088d.elf `
    -BuildLog D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\build_r2_sweep.log `
    -ExpectBitHash8 <bit8> -ExpectElfHash8 1bc8088d `
    -Xsa D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\mb_ctrl_r2.xsa `
    -IlaCapture -IlaLtx D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\probes_r2_<bit8>.ltx `
    -Port COM5
```

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
| **S0** | 离线：bit/ELF SHA256、构建日志 WNS/WHS/标记/DRC、xsa hash（可选） | hash8 与 `-Expect*Hash8` 一致（ELF=`1bc8088d`）；日志 `SWEEP_*: WNS/WHS` 或 `WNS_GATE/WHS_GATE` ≥0；成功标记在/失败标记不在；`DRC finished with 0 Errors` 且 ERROR 行=0 | 位流是否真过时序门限；工件身份是否烧错/归档错；xsa 是否新 | 无 `-BuildLog` ⇒ `SKIP`（非失败）；日志存在但解析不到门限/DRC ⇒ `NOT_OBTAINED`（`-SkipDrcRequirement` 可降级 DRC）；**本轮场次构建 NO_BITSTREAM ⇒ 无 R2 位流可钉身份，S0 依赖项判 `NOT_OBTAINED`、S2–S11 全部 `SKIP`（等下一次成功位流对）** |
| **S1** | 在位配置记录（**不烧绿基线**）：离线记录默认名产物/R1 在位对/R2 目标对 hash8；`-Run` 时只读 `'U'/'L'`/邻居/ping1 快照 | 离线记录落盘；`-Run` 要求 `'U'` 可解析或 `'L'` 有 LAT 行 | 板/线/PC 侧“换 R2 前”的状态基线（DESIGN §10：S2 烧 R2 对 = 唯一变量） | 板卡不响应 ⇒ `NOT_OBTAINED`（不阻塞 S2 烧写） |
| **S2** | 烧 R2 对后**全程不发 `'d'`**：`'U'` 断言 mode=0&bit24=0 → `'S'` → ping1 → `'U'` | 硬判：ping 0/1 + NIC `ReceivedBytes` delta=0 + `wmwr` delta=0；INFO：`WR_REQ.pending`（~56ms 窗口内可能=1；WAITGO 超时后良性丢帧回落 0 均属正常，**不硬判**） | **位流身份原位判据**：R2 写路径=S2MM 需软核服务，未切 DMA ⇒ 不提交、读侧零启动 ⇒ 不回包；回包=烧错/烧旧/引擎位已 1 | 烧后 `'U'` 无应答/引擎位非 0 ⇒ `NOT_OBTAINED`（不要为凑判据发 `'d'`） |
| **S3** | `Set-EngineMode DMA`（`'d'` 翻转，最多 3 次，双重回读）→ `'S'` → settle 2s → 整段 `'U'` | 硬判：mode=1 & `req.bit24=1`；`WR_DBG.fault==0`（fault=1 ⇒ FAIL 并打印 wdbg/wreq/s2sr + ACK 恢复提示）；WARN：settle 后 pending 仍=1、slot/len 合法性、s2sr（`-StrictS2sr` 时 Halted=0&errbits=0 硬判） | 引擎/写服务真的切到 DMA；写引擎是否 fault（粘滞）；S2MM DMASR 是否报错/长度异常 | `'U'` 无应答/解析失败 ⇒ `NOT_OBTAINED`；Set-EngineMode 失败 ⇒ `FAIL` |
| **S3b** | 只读静默窗：轮询 `'U'` 到 `wmwr==wmrd` 且 `bit25=0` 连续两拍 | 静默窗建立 | 清 S2 残留挂起帧，使 S4/S5 差分基线干净 | 10 次轮询不静 ⇒ `FAIL`（读出侧未排空，S4/S5 自动降级 `NOT_OBTAINED`） |
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

### 4.1 工件（S0 期望；**本轮场次构建 NO_BITSTREAM，无 R2 位流**）

**归档（失败轮）**：`out\archive\b31b_r2_2026-10-17\`（磁盘共 21 个文件：`SHA256.txt` 登记其中 20 项；`BUILD_STATUS.md` 亦在清单内；**hash 以目录内 `SHA256.txt` 为准**）。

| 工件 | 本轮实际状态（以磁盘为准，2026-10-18 01:0x） |
|---|---|
| **R2 位流** | **NO_BITSTREAM（未产出）**：5 掷均被时序门限（WNS≥0 & WHS≥0）拒收，失败轮不写位流、不覆盖在库产物 ⇒ **S0 依赖项 NOT_OBTAINED；S2–S11 全部 SKIP**。等下一次成功构建后再填 `aurora_mem_bridge_r2_<bit8>.bit` 与 `-ExpectBitHash8`。 |
| 在库位流（**R1 参照，不是 R2**） | `archive\b31b_r2_2026-10-17\aurora_mem_bridge_r1_in_service_c8cd3a32.bit`：9,746,300 B、`c8cd3a32…`（与 `out\aurora_mem_bridge.bit` 同 hash，mtime 10-17 21:28）。**禁止当 R2 产物烧/钉身份**。 |
| R2 探针 ltx | 本轮**未产出最终配对 ltx**；失败轮 ILA 网表 = `out\probes_v5_ExtraTimingOpt.ltx`（198,882 B、`453d9173…`），其中已确认新探针名：`dbg_s2mm_state[2:0]`/`dbg_s2mm_tvalid`/`dbg_s2mm_tready`（ILA3@ui）+ `dbg_s2mm_reqpend`/`dbg_wr_fault`（ILA0@user）——**仅用于核对探针名，不可作为 R2 上板判据的配套 ltx**。成功位流后归档为 `probes_r2_<bit8>.ltx`。 |
| ELF | `archive\...\j3_soft_r2_1bc8088d.elf`：**`1bc8088d`（50,896 B，最终冻结，blob `ee256c05`）**；`-ExpectElfHash8 1bc8088d`（SHA256.txt 登记 `1BC8088D…BD42A`）。 |
| R2 xsa | **未产出**；`out\mb_ctrl.xsa` 仍是 R1 版 `c9b52dd7…`（10-17 21:29）。R2 成功后归档为 `mb_ctrl_r2.xsa`。 |
| 综合日志 | `out\r2_synth.log`：232,023 B、`ef7025a1…` —— **PASS：0 errors / 0 critical warnings / 743 warnings**（L1972；`SYNTH_ONLY_DONE` L2170）；`pre_impl_debug.dcp` + ILA 四核（含 R2 新探针）OK（BUILD_STATUS §1）。 |
| 实现扫描日志 | `out\r2_sweep.log` / `out\r2_sweep_console.log`（`e12fbdbd`/`5c8cc0b8`）+ `out\r2_sweep2.log` / `out\r2_sweep2_console.log`（`6bffb869`/`a84d2ed9`）；关键行：`SWEEP_WLDrivenBlockPlacement: WNS=-0.225 WHS=0.004` + `V5_SWEEP_ALL_FAIL`；`SWEEP2_ExtraPostPlacementOpt: WNS=-0.175 WHS=0.004`（无 write_bitstream）。 |
| 构建状态/诊断 | `archive\...\BUILD_STATUS.md`（4,100 B、`EA9E7BC4…`；轮次表/失败诊断/修复建议/复现命令）+ `R2_build_worst_paths_excerpt.txt`（`D8B49C4F…`）+ `rpt2_ExtraPostPlacementOpt.worst.rpt`（250,207 B、`EA05CC30…`）。 |
| 归档清单 | `archive\...\SHA256.txt`（2,488 B、`041db3f1…`；20 行逐文件 hash——**以它为准**）。 |

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
- **错误计数可观测性（Lead 2026-10-17 裁决，全部 INFO 不硬判）**：
  - 桥① `dbg_mem_bresp` 在 S2MM 写路径**恒 0**（IP 内部 BRESP 不可见）；
  - 桥②（HAS_DMA=0，RTL 本轮未动）`stall/len_err/bresp` **无 ILA 探针**；
  - `stat_wr_timeout` 无 Lite 读回路径（见上）。

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
| **R14** | **本轮构建 NO_BITSTREAM**（时序门限 5 掷全败）：无 R2 位流 ⇒ S0 依赖项 NOT_OBTAINED、板验未执行（S2–S11 SKIP） | 记录在 §4.1/§5-14；下一轮先按 `archive\b31b_r2_2026-10-17\BUILD_STATUS.md` §3 主修时序（1 级流水），再重建/归档/板验 |
| **R15** | **失败轮不覆盖在库产物**：`out\aurora_mem_bridge.bit` 仍是 R1 `c8cd3a32`（21:28）、`out\mb_ctrl.xsa` 仍是 R1 `c9b52dd7`、`out\probes.ltx` 不存在 | **禁止**把上述在库产物当 R2 烧/钉身份；S0 只认归档绝对路径 + 实算 hash；R2 成功后新归档再更新 |
| **R16** | `out\probes_v5_ExtraTimingOpt.ltx` 是**失败轮 ILA 网表**（R2 新探针名可见，可用于核对探针名），不是与成功位流配对的 ltx | 不作为 R2 上板判据配套 ltx；成功位流后归档为 `probes_r2_<bit8>.ltx` 再用于 `-IlaLtx` |

---

## 7. dry-run 自证结果（`out\r2_dryrun.log`，2026-10-18 01:03，v1.5）

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

- **本轮场次结论（2026-10-17 构建 / 10-18 收尾，全部 `[L2]` 离线事实，无板上结论）**：
  - 构建 **NO_BITSTREAM**：5 掷全被时序门限拒收（权威：`archive\b31b_r2_2026-10-17\BUILD_STATUS.md` §1；原始：`out\r2_sweep_console.log` 尾 `SWEEP_WLDrivenBlockPlacement: WNS=-0.225 WHS=0.004` + `V5_SWEEP_ALL_FAIL`；`out\r2_sweep2_console.log` 尾 `SWEEP2_ExtraPostPlacementOpt: WNS=-0.175 WHS=0.004`）。
  - 综合 **PASS**：`out\r2_synth.log` `0 errors / 0 critical warnings / 743 warnings` + `SYNTH_ONLY_DONE`；ILA 四核（含 R2 新探针）OK。
  - 失败诊断（`[L2]`，直读 `rpt2_ExtraPostPlacementOpt.worst.rpt`/`R2_build_worst_paths_excerpt.txt`）：25/30 最差路径 = 同步化写指针 gray→decode→新写引擎字节 CE；5/30 桥② 旧写 FSM 同族。
  - **板验未执行**：未烧/未开串口/JTAG/未 ping（用户 10-18 00:2x 要求收尾+断电）⇒ S0 依赖项 NOT_OBTAINED、S2–S11 全部 SKIP。
  - **在库产物仍是 R1**：`out\aurora_mem_bridge.bit`=`c8cd3a32`（21:28）、`out\mb_ctrl.xsa`=`c9b52dd7`（21:29）；**禁止当 R2 烧**。
  - 记录正文：`C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`（§六 构建+诊断、§九 下次开工=先按 BUILD_STATUS §3 主修时序；docs 镜像由 Lead 负责）。
- `[L1-设计]`：R2 机制（S2MM TKEEP→WSTRB、IOC 时刻、S2MM 拆 burst）来自 DESIGN §6/§12，未板上实测；本工具链以 S4/S7/S8/S9 覆盖并标 `TKEEP_SUSPECT`。
- `[L2-离线]`：本工具链自身（dry-run 自证、recon 正负自检、Tcl 结构检查）+ 本轮综合/扫描/诊断日志。
- `[L3-板证]`（引用 R1）：NIC=`ReceivedBytes`（`green_engine1_ping.log` 4/4 时 Unicast=0/Bytes=+296）；J3 `--dma` 失败纪律（C7b/C9）；J4 双桥对账口径（W4/J4）。
- 依据文件：`AGENTS.md` §6a/§七/§八/§九 #17/#18/#40/#43/#45/#46/#53/#55/#56、§十二；`out\S0S8_DESIGN.md`；`out\R2_S2MM_DESIGN.md`（v1.2）；`evidence_2026-10-17\R1_evidence_index.md`；`prj\project_9\scripts\json_storm.py`；`prj\project_10\prj_loop\scripts\udp_verify_ddr.py`；`out\archive\b31b_r2_2026-10-17\{BUILD_STATUS.md,SHA256.txt}`。
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
