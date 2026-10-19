# R2 round3c 板验会话记录（模板）

> 用法：**复制本文件**为 `out\evidence_2026-10-19\R3C_board_session_<yyyy-mm-dd_HHmm>.md` 并逐项填写；
> 未取得判据的栏写 `NOT_OBTAINED`（判据未取得 ≠ 通过，AGENTS.md §6a），不要留空、不要补猜。
> 所有结论行必须带等级：`[L3]` 板上直接观测 / `[L2]` 对照成立 / `[L1]` 相容假说（仅假设栏）；
> 单侧对照不得写「判定/根因」（归因三禁，§6a 硬规则 1）。
> 原始日志/CSV 一律落 `out\evidence_2026-10-19\`，**证据文件路径必须写绝对路径**。

---

## 0. 会话元信息

| 项 | 值 |
|---|---|
| 会话时间 | `____-__-__ __:__` ～ `__:__`（Asia/Shanghai） |
| 操作者 / 复核者 | `__________________`（Lead 执行）/ `__________________`（复核） |
| 工具链版本 | `r3c_cap.tcl` sha8 `A876EEC3`；`r3c_diag.tcl` sha8 `7EE22D6D`；`r3c_seq.ps1` sha8 `EC748C15`；`r3c_ila_analyze.py` sha8 `6FFF80B8`（若不符，先核对版本再判读） |
| 板卡 / 指示灯 | 板卡上电 `YES/NO`；T23 `____`；LAT 行 `____` |
| PC 环境 | PowerShell `5.1.xxxx`；Python `3.14.6`（全路径）；Vivado/Vitis `2023.1` |
| 串口 | `COM5 @9600`（`Get-PnpDevice -Class Ports` 枚举：`____________`） |
| 本轮目的 | round3c：4 核 ILA（ILA0/3/4/5）+ 诊断 ELF（g_step）；复现/定位 `'d'→'W'→ping 1` 后 AXI 楔死 + S2MM 零 commit |

**产物身份（S0 辅助；round3c 归档 hash 以 `r3c_pin.md` §1 为准）**

| 产物 | 路径（绝对） | 大小 | SHA256（全量） | 期望 sha8 一致？ |
|---|---|---|---|---|
| BIT | `D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c\____________.bit` | `________` | `________________________________` | `OK/MISMATCH`（期望 `________`） |
| LTX | `...\____________.ltx` | `________` | `________________________________` | 4 核？`YES/NO` |
| ELF | `...\____________.elf` 或 `sw\j3_soft\Debug\j3_soft.elf` | `________` | `________________________________` | `OK/MISMATCH`（期望 `________`） |
| XSA | `...\mb_ctrl_r2.xsa` | `________` | `________________________________` | `OK/MISMATCH/N.A.` |

> 校验命令：`Get-FileHash -LiteralPath <file> -Algorithm SHA256`（**判据只认归档绝对路径 + 实算 hash**）。

---

## 1. 阶段 A：烧录（`r3c_seq.ps1 -Step Burn -Run`）

- 命令：`______________________________________________________________`
- 实际 SHA256 校验：BIT `HASH_OK/MISMATCH`；ELF `HASH_OK/MISMATCH`
- 日志：`D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3C_<ts>_burn.log`
- 关键行：`PAIR_BURNED` = `YES/NO`；`BURN_OK` = `YES/NO`；`R3C_SEQ_RESULT: _______`
- 烧录后等待：`____ s`；重烧次数（失败不自动重试纪律）：`____`

**阶段判据**：`PASS / FAIL / NOT_OBTAINED`  — 依据：`________________________________`

---

## 2. 阶段 B：串口探针（`-Step Serial -Run`；`'U' → 'd' → 'W'`）

### 2.1 原始输出（逐字粘贴，勿改写；`UART_RX[...]` 行或 uart_probe 原文）

**'U' 探针**
```
<粘贴原文： [B2] U id/req/reqX/wmrd/stat/arl/emit/wreq/wdbg/s2sr/wmwr/ust/mode 各行>
```
**'d' 探针**
```
<粘贴原文： [B2] DMAMODE now=____>
```
**'W' 探针（楔死前）**
```
<粘贴原文： [B2] W s2cr=... s2sr=... s2len=... m2sr=... m2len=...
             [B2] W wreq=... wdbg=... dreq=...
             [B2] W dec halt= idle= ioc= int= slv= dec= err=>
```

### 2.2 解析摘要

| 字段 | 值 | 备注（INFO/硬判） |
|---|---|---|
| `U mode` | `____` | 0=未切 DMA（烧后基线） |
| `d` 回读 | `DMAMODE=DMA / bridge` | toggle 命令；只发一次，回 bridge 说明异常，**不要盲目重发** |
| `s2cr` | `0x________` | 期望 RS=1 |
| `s2sr` | `0x________` | bit0 Halted / bit1 Idle / bit12 IOC（INFO） |
| `s2len` | `0x________` | `0x56`=86 与 ping 帧长一致（INFO） |
| `wreq` / `wdbg` | `0x________ / 0x________` | pending/fault 位（INFO） |
| halt/idle/ioc/int/slv/dec/err | `_/_/_/_/_/_/_/_` | S2MM 错误位（INFO，首次只 WARN） |

**阶段判据**：`PASS / FAIL / NOT_OBTAINED` — 依据：`____________________________`
（坑 #44 自证：本阶段仅串口，无并发 AXI 读；下一阶段才开 Vivado/JTAG 会话）

---

## 3. 阶段 C：4 核 ILA 采集（`-Step Cap -Run`，在 Diag 之前）

- 命令：`______________________________________________________________`
- 模式：`触发式（默认） / 快照兜底（-SnapshotOnly）`；`-TrigTimeoutMin ____`
- 关键 env：`R2_LTX=____`、`R2_STIM_CMD=____`、`R2_TRIG_ILA4=dbg_l_bus[35]=eq1'b1`、`R2_TRIG_ILA5=dbg_wd_go_ui=eq1'b1`
- Vivado 日志：`...\R3C_<ts>_cap_vivado.log`；控制台：`...\R3C_<ts>_cap_console.log`

### 3.1 核与探针清单（从日志抄 `R3C_CORE_TOTAL / R3C_ILA_LABEL / R3C_PROBE_MAP / R3C_WIDTH`）

| ILA | `hw_ila_N`（实测） | probes 数 | 总位宽 | 期望（pin §2） | 一致？ |
|---|---|---|---|---|---|
| ILA0 @user | `________` | `____` | `____` | 110 | `OK/WARN` |
| ILA3 @ui | `________` | `____` | `____` | 152 | `OK/WARN` |
| ILA5 @ui | `________` | `____` | `____` | 82 | `OK/WARN` |
| ILA4 @clk_100m | `________` | `____` | `____` | 37 | `OK/WARN` |

`R3C_CORE_TOTAL` = `____`（期望 4）；`R3C_ILA_COUNT_WARN` = `有/无`

### 3.2 触发与结果

| ILA | 触发 spec | 武装 | `R3C_TRIG_STATUS` | POST CSV 是否存在 |
|---|---|---|---|---|
| ILA4 | `dbg_l_bus[35]=eq1'b1` | `YES/NO` | `TRIGGERED / NO_TRIGGER / ARM_FAILED` | `YES/NO` |
| ILA5 | `dbg_wd_go_ui=eq1'b1` | `YES/NO` | `TRIGGERED / NO_TRIGGER` | `YES/NO` |
| ILA3 | 空（快照 POST） | — | — | `YES/NO` |
| ILA0 | 空（快照 POST） | — | — | `YES/NO` |

`R3C_RESULT` = `PASS / FAIL / NO_TRIGGER` — 依据：`________________________`
**若 NO_TRIGGER**：按 runbook §4.2 用 `-SnapshotOnly` 重抓一次（记录为“判据未取得后的兜底快照”，**不得写成 PASS**）。

### 3.3 CSV 路径清单（绝对路径）

| ILA | pre CSV | post CSV | 行数 |
|---|---|---|---|
| ILA0 | `D:\...\R3C_<tag>_ILA0_pre.csv` | `D:\...\R3C_<tag>_ILA0_post.csv` | `____/____` |
| ILA3 | `...` | `...` | `____/____` |
| ILA5 | `...` | `...` | `____/____` |
| ILA4 | `...` | `...` | `____/____` |

**阶段判据**：`PASS / FAIL / NOT_OBTAINED` — 依据：`____________________________`

---

## 4. 阶段 D：楔死后 JTAG/LMB 现场读取（`-Step Diag -Run`，xsct）

- 命令：`______________________________________________________________`
- 日志：`D:\FPGA\prj\project_11\out\evidence_2026-10-19\R3C_<ts>_diag.log`
- 符号表：`R3C_SYMTAB_MISMATCH = ____`（期望 0；非 0 ⇒ 先核 ELF 版本，再解释读数）

### 4.1 PC 与全局量（抄 `R3C_PC_* / R3C_KEY / R3C_RAW`）

| 键 | 值 | stable | 备注 |
|---|---|---|---|
| `R3C_PC_RUNNING` | `pc: ________` | — | 运行态 PC（楔死现场） |
| `R3C_PC_STOPPED` | `pc: ________` | — | stop 后 PC |
| `G_STEP` | `0x________` | `0/1` | **g_step 解码见 4.2** |
| `GDMA_MODE` | `0x________` | `0/1` | 期望 1（'d' 后） |
| `G_DMA_SERVICE` | `0x________` | `0/1` | 轮内服务开关 |
| `G_WR_LAST_TOGGLE` | `0x________` | `0/1` | 最近 arm 的 toggle |
| `WA_CNT` | `0x________` | `0/1` | 已 arm 写服务次数 |
| `WA_DONE` | `0x________` | `0/1` | 完成态快照已取 |
| `WA_S2CR` | `0x________` | `0/1` | S2MM_DMACR 快照 |
| `WA_S2SR` | `0x________` | `0/1` | S2MM_DMASR 快照 |
| `WA_S2LEN` | `0x________` | `0/1` | 期望 `0x56`（86） |
| `WA_S2SR2` | `0x________` | `0/1` | pending 落零后 DMASR |
| `WA_S2LEN2` | `0x________` | `0/1` | pending 落零后 LENGTH |
| `WA_WREQ` | `0x________` | `0/1` | WR_REQ 快照 |
| `WA_WDBG` | `0x________` | `0/1` | WR_DBG 快照 |
| `BSS_END` | `0x________` | `0/1` | 期望 `0x453c` |

`R3C_SUMMARY`（一行粘回）：`______________________________________________________________`

### 4.2 g_step 解码（勾选一项）

- [ ] `g_step=11`：`dread(R_WRDBG 0x44)` 期间挂死（round3b/3c 观测形态）
- [ ] `g_step=12/13/14/15/…`：`____________`（按 r3c_diag.tcl 头注释表解释）
- [ ] `g_step=1/2/3/9`：空闲环（说明楔死时固件不在写服务路径，需回查抓取时点）
- [ ] 其它/无法稳定：`____________`；`stable` 列出现 0 的地址：`____________`

**阶段判据**：`PASS / PARTIAL / FAIL / NOT_OBTAINED` — 依据：`________________________`

---

## 5. 阶段 E：CSV 判读（离线）

- 命令：`& $py ...\tools\r3c_ila_analyze.py --dir D:\...\evidence_2026-10-19 --pattern "R3C_*.csv"`
- 每个 CSV 的 `ILA4_VERDICT/ILA5_VERDICT` 与 `R3C_ILA4/5_HYPOTHESIS` 摘录：

| CSV | profile | 关键观测（握手数/LAST_AR/state/intr/stream） | HYPOTHESIS 标签 | VERDICT 摘要 |
|---|---|---|---|---|
| `R3C_.._ILA4_post.csv` | ILA4(PACKED) | `AR=__ R=__ AW=__ W=__ B=__; LAST_AR=______; lwst/lrst=__/__; stuck_or=__` | `H-____` | `______` |
| `R3C_.._ILA5_post.csv` | ILA5 | `go_ui rising=__; go_ok=__; intr sticky=__; state hist=______` | `GO______` | `______` |
| `R3C_.._ILA3_post.csv` | LEGACY_UI | `wm/wr_frm/rd_frm: __/__/__（delta __）; state=____` | — | `______` |
| `R3C_.._ILA0_post.csv` | LEGACY_USER | `u_wr/u_rd/u_drop: __/__/__（delta）; reqpend=__; fault=__` | — | `______` |

**判读结论（每条带等级与依据）**
1. `[L_][结论]` — 依据：`<CSV 路径 + 行/字段>`、`<diag 日志字段>`、`<串口输出>`。
2. `[L_][结论]` — 依据：`……`
3. 与既有证据的一致性/矛盾：`________________________________________________`
4. **明确列出未取得判据项**（若有）：`____________________________________________`
   （例：ILA5 触发 NO_TRIGGER ⇒ GO 时序不可判；串口无应答 ⇒ 固件侧状态不可判）

**阶段判据**：`PASS / FAIL / NOT_OBTAINED` — 依据：`____________________________`

---

## 6. 异常 / 处置记录（失败不自动重试纪律）

| 时间 | 现象 | 判据/证据 | 处置 | 重试？ |
|---|---|---|---|---|
| | `____________` | `____________` | `____________` | `否/是（原因）` |
| | | | | |

- 板卡最终状态：`已楔死（UART 静默）/ 端到端可用 / 需断电重上`
- 是否触发 `hw_server/JTAG` 异常（坑 #49）：`YES/NO`；处置：`断电重上 / 重启 hw_server / 其它`

---

## 7. 证据文件清单（绝对路径 + 实算 hash）

| 文件 | 大小 | SHA256 前 8 | 说明 |
|---|---|---|---|
| `D:\...\R3C_<ts>_seq.log` | `____` | `________` | 序列总日志 |
| `D:\...\R3C_<ts>_burn.log` | `____` | `________` | 烧录 |
| `D:\...\R3C_<ts>_cap_vivado.log` | `____` | `________` | ILA 采集（vivado） |
| `D:\...\R3C_<tag>_ILA4_post.csv` | `____` | `________` | **楔死判读主证据** |
| `D:\...\R3C_<tag>_ILA5_post.csv` | `____` | `________` | GO/ACK/intr/state |
| `D:\...\R3C_<tag>_ILA3_post.csv` / `ILA0_post.csv` | `____` | `________` | 桥梁计数 |
| `D:\...\R3C_<ts>_diag.log` | `____` | `________` | g_step/g_wa_* |
| `D:\...\R3C_<ts>_ana_*.log`（判读输出） | `____` | `________` | 分析器 stdout |

---

## 8. 下一步决定

- [ ] 需要 round3d 修复（候选：[L1] `____________`；建议动作：`____________`）
- [ ] 需要补探针/改触发后重建再验（原因：`____________`）
- [ ] 现有证据已足以支撑结论升级到 `[L2]/[L3]`（附对照实验说明：`____________`）
- [ ] 本轮判据未取得（原因：`____________`），板卡需重烧/断电重上后重跑

**一句话结论**：`______________________________________________________________`
