# R2 round3c 板验 Runbook（Lead 执行；工具链作者 `script-tools` 离线交付）

> **一句话顺序**：`Plan` 离线预检（钉 hash/查工具/查串口）→ `Burn` 烧 bit+ELF → `Serial` 串口 `U→d→W` → `Cap` 四核 ILA（PRE→武装 ILA4/ILA5 触发→ping 1→POST）→ `Diag` JTAG/LMB 读 g_step/g_wa_* → 用 `r3c_ila_analyze.py` 判读 CSV。
> **本 runbook 的每一步都可单跑、幂等；任一步 FAIL/NOT_OBTAINED 不自动重试**（AGENTS.md §6a；round2d/round3b 纪律：失败现场先取证，再决定重烧）。

---

## 0. 交付物清单（本目录 `out\evidence_2026-10-19\tools\`）

| 文件 | 作用 | 谁执行 |
|---|---|---|
| `r3c_seq.ps1` | 板验序列编排（Plan/Burn/Serial/Ping/Cap/Diag/SerialPost/Status/All；默认 dry-run，`-Run` 才碰硬件） | Lead（PowerShell 5.1） |
| `r3c_cap.tcl` | **4 核 ILA 采集**（LTX 自动发现核/探针；触发式 PRE/POST；坑 #66 合规） | Lead（`vivado -mode batch`） |
| `r3c_diag.tcl` | **楔死后 JTAG/LMB 现场读取**（PC/g_step/g_wa_*/g_dma_mode/g_wr_last_toggle；坑 #54 同址复读） | Lead（`xsct`） |
| `r3c_ila_analyze.py` | CSV 判读器（ILA4 打包总线解码、ILA5 GO/ACK/intr/state、legacy ILA3/ILA0；**假设签名 `R3C_ILA4/5_HYPOTHESIS`**；纯标准库） | 任意（离线） |
| `r3c_pin.md` | S0 钉 hash 计划 + 4 核 LTX 期望 + 待回填表 | Lead 回填 |
| `r3c_board_session_template.md` | 板验会话记录模板（烧录 hash / 串口原文 / ILA 各核结果 / g_step / 判读等级 / 证据清单） | Lead 板验时复制填写 |
| `tcl_selfcheck.py` | Tcl 静态自检（括号/引号平衡 + 坑 #66 API 清单） | 任意（离线） |
| `selfcheck.txt` | 全部自检结果留档（BOM/ParseFile/py_compile/干跑样例/假设签名正负自检） | — |
| `selftest\` | 合成 CSV 干跑样例（ILA4 named/packed、ILA5）+ `hypothesis_selftest.py` 正负自检 + dry-run 日志 | — |

**运行环境**：Windows PowerShell **5.1**（`.ps1` 必须 UTF-8 BOM，已验 0 语法错）；Python 全路径 `C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe`（坑 #45，勿用 `python` 别名）；Vivado/Vitis 2023.1；串口 `COM5 @9600`。

---

## 1. 阶段性预检（离线，约 3 分钟；不碰板）

```powershell
# 1) 只读 dry-run：校验 -Bit/-Elf/-Ltx 存在性与 SHA256、工具路径、pyserial、COM5 是否在列
powershell -NoProfile -ExecutionPolicy Bypass -File `
  D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_seq.ps1 -Step Plan
```

- 期望看到：`TOOL_OK` ×8、`PY_PYSERIAL: pyserial 3.5`、`SERIAL_PORTS: ... present=True`、`R3C_STEP_RESULT: step=Plan result=PASS`。
- round3c 产物未归档前：`ARTIFACT_MISSING/ARTIFACT_PENDING` 属正常，按 `r3c_pin.md` §1 回填后用 `-Bit/-Elf/-Ltx/-ExpectBitHash8/-ExpectElfHash8` 显式重跑。
- **S0 身份判据**（`r2_board.ps1` dry-run，**不进本轮板验序列**）见 `r3c_pin.md` §3；S0 PASS 只是产物身份，不是功能结论。

---

## 2. 阶段 A：烧录 bit + ELF（约 40 s）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_seq.ps1 -Step Burn -Run `
  -Bit  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\aurora_mem_bridge_r2_<XXXXXXXX>.bit `
  -Elf  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\j3_soft_r2_<YYYYYYYY>.elf `
  -Ltx  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\probes_r2_<XXXXXXXX>.ltx `
  -ExpectBitHash8 <XXXXXXXX> -ExpectElfHash8 <YYYYYYYY>
```

- 实际命令以 `-Step Plan` 打印为准；**ELF 未归档时可给 live 路径** `D:\FPGA\prj\project_11\sw\j3_soft\Debug\j3_soft.elf`（sha8 `F5E0F1F3`）。
- 判据：日志出现 `PAIR_BURNED`（脚本自动检查并打 `BURN_OK`）；`R3C_SEQ_RESULT: PASS`。
- **纪律**：`-Run` 下未钉 `-ExpectBitHash8` 会 `BURN_REFUSED`（防烧错）；`HASH_MISMATCH` 立即停，查归档/文档，不要 `-AllowUnpinned` 硬烧。
- 烧后等 3 s 再进串口（固件启动）。

---

## 3. 阶段 B：串口探针 `'U' → 'd' → 'W'`（约 8 s）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_seq.ps1 -Step Serial -Run
```

脚本内部调用（等价手工命令）：

```powershell
$py='C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe'
& $py D:\FPGA\prj\project_11\out\uart_probe.py --port COM5 --cmd U --wait 2.5 --drain 0.2 --raw
& $py D:\FPGA\prj\project_11\out\uart_probe.py --port COM5 --cmd d --wait 1.5 --drain 0.2 --raw
& $py D:\FPGA\prj\project_11\out\uart_probe.py --port COM5 --cmd W --wait 1.5 --drain 0.2 --raw
```

**期望/判读**：

| 命令 | 期望输出 | 说明 |
|---|---|---|
| `'U'` | `[B2] U id: ... 50314231 ...`、`[B2] U mode=0` | 固件存活基线；`mode=0` = 未切 DMA |
| `'d'` | `[B2] DMAMODE now=DMA` | **toggle 命令**：烧后首次发一次即可；脚本会打印 `SERIAL_D_OK`。若回的是 `bridge`（说明发了两次/固件重启过），**不要盲目再发**，先记录 |
| `'W'` | `[B2] W s2cr=... s2sr=... s2len=...` + `halt= idle= ioc= int= slv= dec= err=` | 记录原始值；`s2sr` bit0=Halted、bit1=Idle、bit12=IOC；初判见 `SERIAL_W_INFO` |

- **坑 #44**：串口打印期间**不得穿插 AXI 读**。本工具链把串口步骤与 JTAG/ILA 步骤严格串行（不同时开两个会话）。
- 该步 FAIL 条件：`'U'` 无任何应答 ⇒ 固件未 boot/串口被占/板卡已楔死；先查 `Get-PnpDevice -Class Ports` 与 COM5 占用。

---

## 4. 阶段 C：4 核 ILA 采集（核心；约 3–5 分钟，取决于触发等待）

### 4.1 推荐路径：触发式（楔死前/后对照）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_seq.ps1 -Step Cap -Run `
  -Ltx D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\probes_r2_<XXXXXXXX>.ltx `
  -TrigTimeoutMin 1
```

脚本做的事（`r3c_cap.tcl`）：
1. 连接 hw_server → 设 `PROBES.FILE`=LTX → `refresh_hw_device`；
2. 按探针名**自动发现/标注** 4 个核（不硬编码 `hw_ila_N`；坑 #40③）：ILA4=`dbg_l_bus*`、ILA5=`dbg_wd_*`/`tdata64`、ILA3=`dbg_mem2_rd_frm` 等、ILA0=`dbg_mem2_u_wr` 等；打印 `R3C_CORE_TOTAL`、每核 `R3C_PROBE_MAP`（probes 数/总位宽）与 `R3C_WIDTH`；
3. **PRE**：四核各 `run_hw_ila -trigger_now` 快照 → `R3C_<tag>_<ILA>_pre.csv`；
4. **武装**：ILA4 触发 `dbg_l_bus[35]==1`（=|stuck，粘滞）、ILA5 触发 `dbg_wd_go_ui==1`；显式 `CONTROL.TRIGGER_MODE BASIC_ONLY` + `CONTROL.TRIGGER_CONDITION AND`（坑 #66①）；
5. **刺激**：`ping -n 1 -w 900 192.168.1.10`；
6. **POST**：`wait_on_hw_ila -timeout <分钟>`（坑 #66②，默认 2 min，`-TrigTimeoutMin 1` 可缩短）→ `upload_hw_ila_data` → `write_hw_ila_data -csv_file <基名>`（坑 #66③）→ `R3C_<tag>_ILA4_post.csv` / `_ILA5_post.csv`；未武装的 ILA3/ILA0 在 settle 后补 `trigger_now` 快照 → `_post.csv`。

**判据（脚本自动打印）**：
- `R3C_RESULT: PASS`（4 核 CSV 齐全、武装核均触发）；
- `R3C_RESULT: NO_TRIGGER armed but not triggered: ...`（**判据未取得**，CSV 只有预触发样本，**不得当 PASS**，§6a 规则 3）；
- `R3C_RESULT: FAIL ...`（LTX 不符/上传失败/CSV 写失败）。

### 4.2 兜底路径：已楔死后的“当前态”快照（无触发）

若板卡在进入 Cap 之前就已楔死（例如串口步骤后 UART 已静默），或 4.1 报 `NO_TRIGGER`，**直接用快照模式抓 4 核当前态**：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_seq.ps1 -Step Cap -Run -SnapshotOnly `
  -Ltx D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\probes_r2_<XXXXXXXX>.ltx
```

- 产出 `R3C_<tag>_ILA{4,5,3,0}_pre.csv`（当前态四核快照；`R3C_RESULT: PASS snapshot`）。
- 注意：**粘滞 `|stuck` 在快照里仍可判读**（它一旦置位保持）；但 GO/ACK 脉冲若已过去，ILA5 快照只能看稳态（state/introut 粘滞位），因此 4.1 仍优先。

### 4.3 手工等价命令（不走 ps1 时）

```powershell
$env:R2_LTX='D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\probes_r2_<XXXXXXXX>.ltx'
$env:R2_OUT_DIR='D:\FPGA\prj\project_11\out\evidence_2026-10-19'
$env:R2_TAG='r3c'
$env:R2_STIM_CMD='ping -n 1 -w 900 192.168.1.10'
$env:R2_WAIT_MIN='2'
$env:R2_TRIG_ILA4="dbg_l_bus[35]=eq1'b1"
$env:R2_TRIG_ILA5="dbg_wd_go_ui=eq1'b1"
cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source `"D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_cap.tcl`" -notrace -log D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3C_cap_vivado.log > D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3C_cap_console.log 2>&1"
```

> **坑 #58**：长 Vivado 命令的输出必须 `> log 2>&1` 落文件，**不要**经 PowerShell 管道捕获（`r3c_seq.ps1` 已按此实现）。

---

## 5. 阶段 D：楔死后 JTAG/LMB 现场读取（约 20 s）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_seq.ps1 -Step Diag -Run
```

等价手工命令（**xsct**，不是 vivado）：

```powershell
cmd /c "`"D:\Xilinx\Vitis\2023.1\bin\xsct.bat`" `"D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_diag.tcl`" > D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3C_diag.log 2>&1"
```

脚本行为：`connect` → 定位 MicroBlaze target → 读运行态 PC → `stop` → 用 **mb-nm 读 ELF 符号表**核对地址（失败则用离线核实表，并打印 `R3C_SYMTAB_WARN/MISMATCH`）→ **每地址先哑读 2 次、再同址复读至连续两值相等**（坑 #54）→ 读 `g_step/g_dma_mode/g_dma_service/g_wr_last_toggle/g_wa_*` → `con`。

**期望输出（关键行）**：

```
R3C_PC_RUNNING: pc: <hex>
R3C_PC_STOPPED: pc: <hex>
R3C_SYMTAB: g_step = 0x00004534 OK
R3C_RAW: G_STEP addr=0x00004534 value=0000000b stable=1
R3C_KEY: G_STEP=0000000b
...
R3C_SUMMARY: G_STEP=... GDMA_MODE=... G_DMA_SERVICE=... G_WR_LAST_TOGGLE=... WA_CNT=... WA_DONE=... WA_S2CR=... WA_S2SR=... WA_S2LEN=... WA_S2SR2=... WA_S2LEN2=... WA_WREQ=... WA_WDBG=...
R3C_STEP_DECODE: g_step=<n> -> <含义>
R3C_DIAG_RESULT: PASS
R3C_DIAG_DONE
```

**g_step 解码表（live 固件 `main.c` 2026-10-19）**：

| g_step | 位置 | 现象解释 |
|---|---|---|
| 10 | `serve_write_once` 入口 | — |
| **11** | `dread(R_WRDBG 0x44)` 之后置位、**读 0x44 期间挂死** | round3b/3c 已观测的楔死点：读 WR_DBG(+0x44) 不返回 |
| 12 | `dread(R_WRREQ 0x40)` 之后 | 0x40 读已完成（若停在 11，说明卡在 0x44） |
| 13 | 写 `S2MM_LENGTH` 之前 | — |
| 14 | 写 `S2MM_LENGTH` 之后 | 传输已启动 |
| 15 | 写 `R_WRGO(+0x48)` 之后 | GO 已翻 |
| 16 | `busy_ms(20)` 之后 | 写后静默窗 |
| 17/18 | 读 S2MM_LENGTH / S2MM_DMASR 之后 | 快照段 |
| 19 | `serve_write_once` 返回 | 本轮完成 |
| 1/2/3 | `serve_any` 入口 / 读 0x34 后 / 无读请求进写服务 | 空闲环状态 |
| 9 | 有读请求 → `serve_dma_once()` | — |

判据：`R3C_DIAG_RESULT: PASS`（符号表全对；读值 stable）。`PARTIAL` = 符号表与离线核实不一致（ELF 换过）⇒ 用脚本打印的新地址重跑 mb-nm 更新头注释，**不要硬解释错地址的读数**。

---

## 6. 阶段 E：CSV 判读（离线，秒级）

```powershell
$py='C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe'
$env:PYTHONUTF8='1'
& $py D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_ila_analyze.py `
  --dir D:\FPGA\prj\project_11\out\evidence_2026-10-19 --pattern "R3C_*.csv"
```

- 自动识别 profile：ILA4（**PACKED `dbg_l_bus[0..35]` 布局自动解码回命名信号**）、ILA5（go/ack/intr/go_ok/state）、LEGACY_UI/LEGACY_USER（ILA3/ILA0 计数）、GENERIC。
- ILA4 输出：`HANDSHAKE_COUNTS: AR/R/AW/W/B`、`ADDR_DECODE`、`AR_ADDR_SEQ`（解码到 `+0x34/+0x40/+0x44` 等寄存器名）、`LAST_AR`、`R_AFTER_LAST_AR`、`TAIL_WAIT_CYCLES`、`STATE_LAST`（lwst/lrst/stuck/stuck_or）、`MAILBOX_LAST`（a_req/a_ack_s1/r_req/r_ack_s1/d_req_s1/d_ack/aresetn/rstuser_s2/rstuser_evt）、`LAST_8_ROWS`、`ILA4_VERDICT`（[L1] 候选）。
- ILA5 输出：`GO_UI/ACK_UI/INTR_UI/GO_OK` 时间线、`S2MM_STATE` 直方图、`S2MM_BEATS`/`S2MM_FIRST_BEAT`（round3b 内容兼容）、`ILA5_VERDICT`。
- **假设签名（2026-10-19 12:3x 新增，判读器自动标注；全部 [L1]）**：每个 CSV 的 ILA4/ILA5 段末尾会打印
  `R3C_ILA4_HYPOTHESIS: <TAG> | <依据>` / `R3C_ILA5_HYPOTHESIS: <TAG> | <依据>`，直接抄入板验记录模板的“判读结论”栏：

  | 标签 | 触发条件（窗口最后样本态；详见 selfcheck.txt §9） |
  |---|---|
  | `H-reset` | `rstuser_evt`(bit30)=1 ⇒ 用户域复位失配优先 |
  | `H-ARnever` | arvalid=0 & arready=1 & rvalid=0 & lwst=lrst=0 & 邮箱全 0 &（整窗无 AR 握手）⇒ 上游 MCU/互联未发读，非 lite_regs |
  | `H-acklost` | lrst≠0&r_req=1&r_ack_s1=0（读邮箱 C 回程丢）或 lwst≠0&a_req=1&a_ack_s1=0（写邮箱 A 回程丢） |
  | `H-bstuck` | bvalid=1&bready=0&lwst≠0&arvalid=1&arready=0 ⇒ B 未消费、读被冰封 |
  | `H-rvalid` | rvalid=1&rready=0&lrst≠0 |
  | `H-false-hs` | AR/AW/W 握手与 FSM 非 IDLE 同拍（fix2 后不应出现 ⇒ 查旧网表/探针布局） |
  | `GO_NOT_AT_BRIDGE` | go_ui 无上升沿但其他 S2MM 活动存在（整窗全静默会报 UNCLASSIFIED，不算“GO 未到桥”） |
  | `GO_AT_BRIDGE_GO_OK_0` | go_ui 有上升沿、go_ok 从未为 1 ⇒ 桥 WAITGO 没看到 GO |
  | `GO_AT_BRIDGE_GO_OK_1_NOT_STREAM` | GO+go_ok 已见但 state 从未 2(STREAM) |
  | `INTR_STICKY` | intr_ui 上升后从未回落、last=1 ⇒ S2MM 无退休握手 |
  | `ENTERED_STREAM` | state=2 出现过（写流已启动） |

  无匹配时打印 `UNCLASSIFIED` + `R3C_ILA4_BITS_LAST:`/`R3C_ILA5_BITS_LAST:` 全量最后值（打包布局另给 `RAW_BITS_LAST: b0..b35`）。
  自检：`py selftest\hypothesis_selftest.py`（13 场景正/负向，每标签正例+反例，当前 PASS）。
- **典型判读模板**（供记录用，等级按 §6a 标注）：
  - 楔死已复现：`ILA4_VERDICT` 出现 `READ FSM stuck in LR_RACK` + `LAST_AR ... +0x44 WR_DBG` + `NO R beat after it`，且 `R3C_DIAG g_step=11` ⇒ 「读 +0x44 跨域邮箱无应答」这类候选升到 **[L2/L3]** 的路径（需与 diag/串口互证）；
  - 若 `LAST_AR` 是 `+0x40 WR_REQ` 且卡 `LR_RACK` ⇒ 与 g_step=11 不符，回查 ELF 版本/抓取时点；
  - ILA5：`GO_UI reached ...` 但 `introut STICKY`/未进 STREAM ⇒ 可把“GO 到桥但 S2MM 未完成/未退休”作为候选（INFO/L1，不单独定案）。
- **禁止**把 `NO_TRIGGER` 的预触发 CSV 当“总线正常/无楔死”证据（§6a 规则 3）。

---

## 7. 阶段 F：收尾与记录

1. （可选）`-Step SerialPost -Run`：楔死后补发一次 `'W'`；**无应答本身是证据**（`SERIAL_POST_INFO: no response after ping ...`），不重试、不长时间阻塞。
2. `-Step Status`：离线汇总最新 `R3C_*` 日志中的 `R3C_RESULT/R3C_KEY/R3C_SUMMARY`。
3. 证据落盘清单（本轮）：`R3C_<ts>_seq.log`、`R3C_<ts>_burn.log`、`R3C_<ts>_cap_vivado.log`、`R3C_<tag>_ILA*_{pre,post}.csv`、`R3C_<ts>_diag.log`。
4. 板卡状态：若已楔死且需退场，**断电重上**（坑 #49 族：用户域/总线死锁后重配 FPGA 才干净）；下一轮重新 Burn。
5. 结论写记录时必须带等级（[L1]/[L2]/[L3]）与证据文件路径；单次板验默认最高 [L3]（板上直接观测），跨“软核/位流”归因需 2×2 对照（坑 #52）。

---

## 8. 故障处置（不自动重试）

| 现象 | 处置 |
|---|---|
| `R3C_RESULT: FAIL ltx not found / PROBES.FILE failed` | LTX 与在位位流不同源或路径错；核对 `r3c_pin.md` §1/§2，重跑 `-Step Plan` |
| `R3C_CORE_TOTAL: 3`（期望 4） | 烧的是 round3b 位流或 LTX 旧版；核对 bit sha8 后再烧 |
| `R3C_WIDTH_WARN` | LTX 与 `r3c_pin.md` §2 期望不符（构建改动或 ltx 不配套）；采集仍有效但**记录为 INFO**，先核对再判读 |
| `R3C_RESULT: NO_TRIGGER` | ①ILA5 的 GO 脉冲早于武装：改 `-SnapshotOnly` 抓当前态；②ILA4 未置 stuck：楔死未复现或抓取时点太早/太晚；记录为“判据未取得” |
| `Cap` 卡住 >5 min | 检查 `-log` 文件；`wait_on_hw_ila` 超时单位是**分钟**（坑 #66②），`-TrigTimeoutMin 1` 可退；必要时杀 vivado 进程后重来（勿用管道捕获输出，坑 #58） |
| 串口 `'U'` 无应答 | 固件未 boot（重烧）或已楔死；`Get-PnpDevice -Class Ports` 查 COM5；**不要**反复发 `'d'`（toggle） |
| `xsct` 失败（TCF/`fpga`） | 长时间 JTAG 后链路劣化 ⇒ **断电重上**（坑 #49），重启 hw_server 无用 |
| 两个会话抢 JTAG | 本工具链串行执行；若手工并发（vivado hw_manager + xsct 同时连着）必有一方失败，先关一方 |
| `R3C_SYMTAB_MISMATCH` | 烧的 ELF 与离线核实表不同（重编过）；按脚本打印地址更新 `r3c_diag.tcl` 头注释/`EXPECT` |

---

## 9. 附录

### 9.1 阶段用时预估

| 阶段 | 时长 | 备注 |
|---|---|---|
| Plan | ~5 s | 离线 |
| Burn | ~40 s | xsct + `fpga` + `dow` + `con` |
| Serial | ~8 s | 3 次 uart_probe |
| Cap | ~90 s + 触发等待（≤1–2 min/核） | vivado batch 启动约 60–90 s |
| Diag | ~20 s | xsct |
| Analyzer | 秒级 | 纯离线 |

### 9.2 `r3c_seq.ps1` 关键参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Step` | `Plan` | Plan/Burn/Serial/Ping/Cap/Diag/SerialPost/Status/All |
| `-Run` | 关 | **不传则全部 dry-run**；传了才碰硬件 |
| `-Bit`/`-Ltx` | 空（自动在 `-Round3cDir` 找最新 `*.bit/*.ltx`） | round3c 归档后回填 |
| `-Elf` | live `sw\j3_soft\Debug\j3_soft.elf` | sha8 `F5E0F1F3` |
| `-ExpectBitHash8`/`-ExpectElfHash8` | 空 / `F5E0F1F3` | `-Run` Burn 未钉 bit hash 会拒绝 |
| `-Port`/`-Baud` | `COM5` / 9600 | 串口 |
| `-TrigTimeoutMin` | `2` | `wait_on_hw_ila -timeout` 的**分钟**数 |
| `-TrigILA4`/`-TrigILA5` | `dbg_l_bus[35]=eq1'b1` / `dbg_wd_go_ui=eq1'b1` | 触发 probe 规格；可用 `;` 串联多条件（AND） |
| `-SnapshotOnly` | 关 | Cap 只抓当前快照（非触发） |
| `-StimCmd` | `ping -n 1 -w 900 192.168.1.10` | Cap 的刺激命令（`-SnapshotOnly` 时忽略） |
| `-AllowUnpinned` | 关 | 允许未钉 hash 烧写（仅 consciously override） |

### 9.3 关键 marker 速查

| marker | 含义 |
|---|---|
| `R3C_CORE_TOTAL: <n>` | 发现 ILA 核数（round3c 期望 4） |
| `R3C_PROBE_MAP: label=... probes=N total_bits=M` | 每核探针数/总位宽（对照 `r3c_pin.md` §2） |
| `R3C_TRIG_ARMED/STATUS/SUMMARY` | 触发武装与结果（`TRIGGERED`/`NO_TRIGGER`） |
| `R3C_RESULT: PASS/FAIL/NO_TRIGGER` | **采集判据行** |
| `R3C_CSV: <label> <pre/post> <path>` | 产出 CSV 路径 |
| `R3C_DIAG_RESULT` / `R3C_STEP_DECODE` / `R3C_SUMMARY` | JTAG LMB 现场 |
| `ANALYZE_FILE/PROFILE/..._VERDICT` | 判读器输出 |
