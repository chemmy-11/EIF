---
alias: 结论_cross_dsh-vivado实战问题与改进
type: 结论
摘要: dsh-vivado（Vivado 预设 + vivado-mcp 32 工具 + 技能包）在 prj12 离线 P0 会话中的实测问题清单：进程启动层 6 条、会话/后台作业 3 条、MCP 覆盖度 6 条、技能与预设文本 3 条、仓库 CI 1 条；每条给命令/输出证据、影响与改进建议；另附本会话时间账
created: 2026-10-25
updated: 2026-10-25
状态: 实测记录（2026-10-24 会话取证，2026-10-25 整理）；P0 三条 + 技能两条 + CI 一条已于 2026-10-25 落地（§9），vivado-mcp 侧建议仍待上游
related: "[[结论_cross_dsh-vivado插件包分发_2026-10-24]] · [[操作文档/阶段三_prj12_双板互联开工草案_2026-10-24]] · [[规划_cross_短期推进计划_2026-10-24]]"
---

# dsh-vivado 实战问题与改进建议

> **场景**：2026-10-24 20:50～23:30，prj12 离线 P0（fork / `link_ok` 单核 / P1 位流 / 脚本 / P2 候选）。
> **环境**：Windows 11 · Vivado/Vitis 2023.1（`D:\Xilinx`）· xcku060-ffva1156-2-i · DSH web GUI · `Vivado` 会话预设（32 个 `mcp__vivado__*` + 8 个技能）。
> **依据等级**：本文全部为 **L3（本机实测）**，每条给命令 + 输出片段；纯推断性建议标注 `[建议]`。
> **不涉及**：板上有结论的东西（板卡不在场）；vivado-mcp 源码未读、未改，问题只按**对外可观测行为**记录。

---

## 0. 一页结论

| # | 问题（一句话） | 直接代价 | 该改哪里 |
|---|---|---|---|
| 1 | `win_bash` 里跑 `cmd //c vivado.bat` 会**杀掉持久 bash** | 每踩一次丢一次 shell | 预设（persona 事实卡） |
| 2 | `pwsh` 里 `& vivado.bat` / `cmd /c "…" \| Out-String` **静默 exit=1、零输出** | ~6 min 排查 + 极易把失败当成功 | 预设 + 核心（工具捕获语义） |
| 3 | `Start-Process cmd.exe -ArgumentList '/c', <含引号整串>` 会被**二次套引号** | 1 轮构建空跑（~2 min） | 预设（启动配方） |
| 4 | `pwsh` 工具**中途消失**（坑 #71 复现） | 需切换备选路径 | 核心（工具可见性） |
| 5 | 直接调 `vivado.exe` / `tclsh85t.exe` 报 `0xC0000135`（DLL 缺） | 轻量探针写不出来 | 预设（给可用配方） |
| 6 | `vivado.bat -version` **不是**健康探针（静默 exit 1） | 探活失败 | 预设 |
| 7 | DSH 后台作业**随回合中断被杀**（21:02 synth 死） | 一次 ~10 min 构建 | 预设（长构建脱离配方） |
| 8 | 外部 `^C` 两次打断构建（impl DRC 阶段、xelab） | 一次 34 min 重跑 | 核心/预设（可恢复构建） |
| 9 | `run_synthesis/run_implementation` 只覆盖**工程 run**，盖不住 checkpoint 式自定义实现 | 头牌工具不可用 | vivado-mcp |
| 10 | `check_bitstream_readiness` 同理（会对我这条流误判 BLOCK） | 门禁不可信 | vivado-mcp |
| 11 | `run_tcl` 30 min 预算 vs 实现 34 min + 单次 ~8k token stdout | 无法阻塞调用 | vivado-mcp（`background`/`log_file`） |
| 12 | `get_timing_report` text 模式把 **540 条路径**全打出来（153 KB 溢出到临时文件） | 上下文被吃掉 | vivado-mcp（`include_paths=false`） |
| 13 | `xdc_lint` 对 GT refclk / MIG 引脚报 109 条 `MISSING_IOSTANDARD` | 需要人肉判"是否阻断" | vivado-mcp（已知误报分组） |
| 14 | 技能包按"有板 + 活会话"写，**缺板卡不在场**的离线流程 | 无技能可依 | 技能包 |
| 15 | 预设说"prefer MCP"，但缺**决策表**（哪种流走 MCP、哪种走脚本） | 每次现场判断 | 预设 |
| 16 | CI 第 5 项"tclsh 不可用 → SKIP"，其实 **Vivado 自带 8.5.14 可用** | 少了真语法门禁 | 仓库 CI |

**亮点（别改坏）**：离线三件套真的好用 —— `xdc_lint`（纯 Python、不占 Vivado）、`get_timing_report(report_file=...)`、`parse_ltx(file_path=...)`。其中 `get_timing_report` 在本次**抓到了我自己写的 WNS 口径 bug**（见 §3.4），这是纯 MCP 收益。

---

## 1. 进程启动层（本会话 ~25 min 工具链耗时里的主要部分）

### 1.1 `win_bash` 跑 `cmd //c vivado.bat` 会终止持久 bash

```
$ cmd //c "D:\Xilinx\Vivado\2023.1\bin\vivado.bat -version > D:\FPGA\prj\project_12\out\_ver.txt 2>&1"
[stderr]
[the command ended the persistent bash process; the next win_bash call starts a fresh shell]
[exit code: 1]
```
- 之后 `_ver.txt` 为 0 字节；同一条命令换 `pwsh` 也是静默失败（见 1.2）。
- **影响**：任何"在 bash 里顺手跑一下 Vivado"的写法都会丢 shell 上下文。
- **[建议]** 预设 persona 增加硬事实一条：「`win_bash` 不得直接执行 `vivado.bat`/`cmd //c`；Vivado 一律走独立进程（见 2.2 配方）」。

### 1.2 `pwsh` 里两种"看起来正常"的写法静默失败

```
PS> $out = & 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat' -version 2>&1
PS> "exit=$LASTEXITCODE"; $out
exit=1                      # $out 为空（不带任何管道裁剪）
PS> cmd /c "D:\Xilinx\Vivado\2023.1\bin\vivado.bat -version" 2>&1 | Out-String
exit=1                      # 同样为空
```
- 判据陷阱：`is_error=false`、`exit=1`、**零输出** —— 按"没报错就是没问题"会直接走错分支。
- **[建议]** 预设增加判据：「Vivado 探针必须能看到 banner 或 `TCL_OK`；`exit!=0 且 0 字节输出` 一律当作启动失败，不可当成功」。

### 1.3 `Start-Process` 的引号二连击（我踩的那版）

失败版（脚本第一版）：
```powershell
$cmdline = '"{0}" -mode batch -source "{1}" -notrace -log "{2}" -journal "{3}"' -f $vivado,$Source,$log,$jou
Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmdline ...
# create.console.log.err:
#   The filename, directory name, or volume label syntax is incorrect.
```
成功版：
```powershell
Start-Process -FilePath 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat' `
  -ArgumentList @('-mode','batch','-source',$Source,'-notrace','-log',$log,'-journal',$jou) `
  -NoNewWindow -Wait -PassThru -RedirectStandardOutput $console -RedirectStandardError "$console.err"
# → EXIT=0, banner + TCL_OK 8.5.14
```
- 细节：`cmd.exe -ArgumentList '/c', <不含引号的整串>` 其实是能跑通的（我用无引号探针验证过）；一旦整串里**带引号**，PowerShell 会把整串再包一层，cmd 解析崩。
- **[建议]** 预设直接给"最优配方"：`-FilePath <bat> -ArgumentList <数组>` + 文件重定向；并注明"不要用 `cmd.exe /c <带引号整串>`"。

### 1.4 `pwsh` 工具中途消失（坑 #71 在本会话复现）

```
Error: unknown tool "pwsh"
```
- 发生在我需要重启构建的时刻（**约 21:51**，不是深夜那轮），此后全部改走 `win_bash` + `powershell.exe -Command`。
- 取证注记：更早还有一条 `& vivado.bat -version 2>&1 | Select-Object -First 8` 也返回 exit=1，但那行**不能作证据**——
  `Select-Object -First N` 会提前掐断管道、导致原生进程被终止并返回 1。真正的证据是 1.2 里不带裁剪的两行。
- **[建议]** 预设已警告会消失，但可补一句"消失后**可用**的替代路径"：`win_bash` 里调 `powershell.exe -NoProfile -Command '…'`（实测可用，见 1.5 的 tclsh 探针）。

### 1.5 直接调 `vivado.exe` / `tclsh85t.exe` 的 DLL 问题与可用配方

```
$ cmd /c "...\unwrapped\win64.o\tclsh85t.exe"      → exit=-1073741515   (0xC0000135, DLL 缺)
$ cmd /c "...\unwrapped\win64.o\vivado.exe -version" → exit=-1073741515
```
可用配方（**这是我本会话唯一成功的"轻量 Tcl 解释器"**，用来做语法门禁）：
```bash
export PATH="/d/Xilinx/Vivado/2023.1/lib/win64.o:$PATH"
export TCL_LIBRARY="D:/Xilinx/Vivado/2023.1/tps/tcl/tcl8.5"
echo 'puts "TCLSH_OK [info patchlevel]"' | \
  /d/Xilinx/Vivado/2023.1/bin/unwrapped/win64.o/tclsh85t.exe
# TCLSH_OK 8.5.14
```
- 用它跑 `info complete` 把本会话 7 个 `.tcl` 全部验过：`complete=1`（含 `burn_*.tcl`、`ila_capture.tcl` 这些**没被任何工具执行过**的脚本）。
- **[建议]** 预设把这个配方写进"实测事实"；同时 §5.1 让仓库 CI 用它，别再说"tclsh 不可用"。

### 1.6 `vivado.bat -version` 不是健康探针

- `-version` 走的是 `rdiArgs.bat → prodversion.exe → exit /b 1` 的分支，在无控制台/管道捕获场景下**既不打印也不报错**。
- 可靠探针：`vivado -mode batch -source <只含 puts 的 tcl> -log/-journal`，看 banner + `TCL_OK`。
- **[建议]** `hw-*` 技能与预设里"确认 Vivado 可用"的步骤改成上面这条。

---

## 2. 会话与后台作业

### 2.1 DSH 后台作业随回合中断而死

- 21:02:03 我以 `run_in_background` 起的 synth 日志停在：
  ```
  [Sat Oct 24 21:02:03 2026] Launched synth_1...
  [Sat Oct 24 21:02:03 2026] Waiting for synth_1 to finish...
  ```
  回合被用户消息打断后：`job_output(pwsh-454095d0479546e3)` → `Error: unknown job …`；`tasklist | grep -i vivado` → 空。**构建被杀**。
- **[建议]** 预设把它写成纪律：「长构建不得挂在会话后台作业上；必须脱离进程树（2.2）」。

### 2.2 有效方案：WMI/CIM 脱离进程树（本会话跑了 3 次，全部存活）

```bash
powershell.exe -NoProfile -Command '
$cl = "cmd.exe /c D:\FPGA\prj\project_12\scripts\build_p1.cmd > D:\FPGA\prj\project_12\out\build_p1.console.log 2>&1"
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$cl}
"RV=$($r.ReturnValue) PID=$($r.ProcessId)"'
# RV=0 PID=46848 → 15 s 后 vivado.exe 出现，回合结束后仍在跑
```
- 代价：进程不在会话树里 ⇒ `job_output` 拿不到；必须让脚本自己写 `out\build_status.txt` / `.ok` 标记行，靠 `tail`+标记行轮询（本会话就是这么做的）。
- **[建议]** 预设给一份"脱离式长构建"模板：`*.cmd` 里落 `BUILD_START/SYNTH_OK/IMPL_OK/BUILD_FAILED` 标记 + 判据只看标记行。

### 2.3 外部 `^C` 会打断子进程（两次，触发源只定了一半）

| 时间 | 目标 | 现象 | 后果 | 触发源 |
|---|---|---|---|---|
| 22:29:19 | `opt_design` 的 DRC 阶段（impl1） | `impl1.console.log` 尾部 `^C` | 34 min 实现作废，改 `impl1b` 重跑 | **未知**：当时我在 `sleep`，没有任何 kill 命令 |
| 约 22:14:4x | `xelab tb_relay_tx` | `xelab_tb_relay_tx.log` 尾部 `^C 终止批处理操作(Y/N)?` | 单元仿真重跑 | **不能排除是我**：同窗口我执行过 `taskkill /F /IM vivado.exe /T`（杀失败构建），`/T` 的波及面当时未核 |

- 两次都发生在**CIM 脱离的子进程**上；也就是说"脱离进程树"解决了"回合结束被杀"，但**不解决**外部 `^C`。
- **缓解**（已验证有效）：构建做成 **checkpoint 式可恢复** —— `pre_impl_debug.dcp` 落盘后，实现段可单独重跑（本会话 impl 重跑只花了 34 min，synth 不必重做）。
- **[建议]** ① 预设把"checkpoint 分段"列为长构建默认形态；② 预设补一条纪律"排查期不要用 `taskkill /T` 打整棵树，先 `tasklist` 定位 PID 再杀单个"；③ `[建议]` 核心侧查清"为何 CIM 子进程会收到 CTRL_C"。

---

## 3. vivado-mcp（32 工具）覆盖度

> 说明：本会话**没有**调 `start_session/run_tcl/run_synthesis/run_implementation`（原因见 3.1–3.3），
> 实际只用离线三件套（3.4–3.6）。所以下面 3.1–3.3 是"按文档语义 + 本工程流程"的**结构性判断**，标注为 `[推断-L1]`。

### 3.1 `run_synthesis` / `run_implementation` 盖不住 checkpoint 式自定义实现

- 本工程的验收配方（prj11 round3d 沿用）是：
  `synth_1` → `open_run` 里脚本插 4 个 ILA → `write_checkpoint pre_impl_debug.dcp` → `open_checkpoint` → `implement_debug_core` → `opt/place(指定 directive)/route/phys_opt ×3` → 写位流。
- `run_synthesis`/`run_implementation` 驱动的是工程 run（`synth_1`/`impl_1`），**中段这套 ILA 插入 + 指定 directive 的实现不在其中**。
- **[建议]** 增加 `run_tcl_file(path, background=True, log=...)`：语义 = "把这份 Tcl 作为 batch 脚本跑，返回 job id + 日志路径"，而不是把 Tcl 拼进会话里跑。

### 3.2 `check_bitstream_readiness` 对本流程会误判

- 它看的是 `impl_1` run 状态；本流程没有 `impl_1`（自定义 checkpoint 实现）⇒ 会报"未就绪/BLOCK"，而实际位流已经出了。
- **[建议]** 支持 `dcp_path` 或 `run_name` 参数；或者在返回里显式说明"未发现 impl_1，结论不适用"。

### 3.3 `run_tcl` 的 30 min 预算 vs 真实实现时长

- 实测：`impl` 单段 **22:31:15 → 23:05:15 = 34 min**；`synth`（含 16 个 OOC IP）约 10 min；`create_project` 约 2 min。
- 预设写 `toolCallTimeoutMs=1800000`（30 min）。**34 > 30** ⇒ 单次阻塞调用必超时；超时后命令仍在跑、后续命令排队，最坏情况是"以为失败其实在跑"。
- 叠加 `run_tcl` 原始 stdout 不裁剪（预设自己写 ≈8k token/次），`open_project`/`open_run` 各一次就把上下文吃掉。
- **[建议]** 见 3.1 的 `background` 形态 + `stdout_tail_bytes` 参数；文档里把"30 min"改成"单段构建上限"的显式提醒。

### 3.4 离线工具是亮点：`get_timing_report` 抓到了我的 WNS 口径 bug（L3）

我脚本里原本这么取 WNS：
```tcl
set wns [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by slack]]
# 日志: IMPL_GATE: directive=ExtraTimingOpt WNS=0.004 WHS=0.004
```
`mcp__vivado__get_timing_report(report_file=out/rpt_impl_timing_summary.rpt)` 返回：
```
Setup  WNS = +0.032 ns   TNS = 0.000 ns   失败端点: 0 / 168083
Hold   WHS = +0.004 ns   THS = 0.000 ns
```
**差了 0.028 ns**：`-delay_type min_max -max_paths 1` 取的是 setup/hold 里**最差的一条**（这里是 hold），不是 setup WNS。
- 已修：`setup` 用 `-delay_type max`、`hold` 用 `-delay_type min`，报告一律以 timing summary 为准。
- **这就是纯 MCP 收益**：同一个数，两个来源交叉核对才发现错。**[建议]** 把"报告文件 vs 即时查询"的交叉核对写进技能/预设的默认步骤。

### 3.5 `get_timing_report` text 模式的输出体量

- 一份 8 MB 的 timing summary，text 模式返回"关键路径 (540 条)"并把 153 KB 溢出到临时文件：
  ```
  (Omitted 153420 bytes. Full formatted result stored at: C:\Users\...\dsh-spill-...\...txt)
  ```
- **[建议]** 增加 `include_paths=false` / `max_paths` / `verbosity=summary`，默认只回摘要 + 前 N 条。

### 3.6 `xdc_lint` 的已知误报需要"可解释分组"

- 结果：`=== XDC 静态检查: WARN (109 warnings) ===`，109 条全是 `MISSING_IOSTANDARD`，落在：
  GT 参考时钟 `gt_refclk_p/n`（T6/T5）+ DDR4 全部数据/地址/控制脚。
- 工程事实：GT refclk 按 MGTREFCLK 用法**不需要** IOSTANDARD（PITFALLS #20）；DDR4 的 IOSTANDARD 由 MIG 生成的 XDC 提供，顶层 XDC 只给 `PACKAGE_PIN` 是既有约定。
- **[建议]** 内置"已知良性族"（GT 引脚族、MIG 引脚族）并把它归到 `INFO/known-benign` 分组，让"是否阻断"一眼可判；或允许传 `port_family_allowlist`。

---

## 4. 技能与预设文本

### 4.1 技能按"有板 + 活会话"写，缺"板卡不在场"的离线路径

- 本次任务的前半段（fork/补丁/构建）与 `hw-ila-debug` / `hw-vio-debug` 的假设（有 live session、有板）不一致；后半段（dry-run 脚本、假 pcap 对照）**没有任何技能覆盖**。
- **[建议]** 新增一节/一技能「板卡不在场时的离线流程」：dry-run 约定、判据不可伪造的负向对照（本次用假 pcap 做 PASS/FAIL/FAIL 三组）、"不宣称上板结论"的口径。

### 4.2 技能里的工具名与实际 `mcp__vivado__*` 前缀的映射成本

- 预设已注明要按技能顶部"本机适配注记"映射（`vivadoExecute`/`vivado_start` → `run_tcl`/`start_session`）。
- 本会话实际**存在**并成功调用的是：`xdc_lint`、`get_timing_report`、`parse_ltx`（均为离线形态）。**没有**任何证据表明需要 `start_session`。
- **[建议]** 在技能/预设里维护一张"实际工具清单 + 每个工具的离线/会话依赖"表，避免每次现场猜。

### 4.3 预设的"prefer MCP"缺决策表

- 本轮 7 类操作里，**只有 3 类适合 MCP**（XDC/报告解析/ltx 解析），其余 4 类（建工程、脚本化插 ILA、自定义实现、烧录）都更适合项目脚本。
- **[建议]** 预设给一张判定表：

| 操作 | 首选 |
|---|---|
| 工程 run 的综合/实现（标准流） | `run_synthesis` / `run_implementation`（`wait:false`） |
| 需要脚本化插 ILA / 指定 place directive / 检查点续跑 | 项目脚本 + 脱离式启动（2.2） |
| 只读分析（report/log/ltx/cdc） | `get_timing_report(report_file)` / `get_critical_warnings` / `parse_ltx` |
| XDC 静态检查 | `xdc_lint`（不占 Vivado） |
| 烧板 / ILA 抓取 | 板上工具链（本会话只做了脚本与 dry-run） |

---

## 5. 仓库 CI 与工具链

### 5.1 CI 第 5 项"tclsh 不可用"是过时结论

```
仓库体检：2611 个已跟踪文件
  [跳过] tclsh 不可用，跳过 Tcl 语法检查
```
- 但 Vivado 自带的 `tclsh85t.exe` 就是 **8.5.14**（与 Vivado 2023.1 的解释器同版本），按 1.5 的配方可用。
- **[建议]** `scripts/ci_check.py` 增加探测顺序：`tclsh` → `$XILINX_VIVADO/bin/unwrapped/win64.o/tclsh85t.exe`（自动设 `PATH`+`TCL_LIBRARY`）。这样第 5 项从"永远 SKIP"变成"真门禁"，且与 Vivado 解析口径一致。
- 附带收益：本次 7 个 `.tcl` 里有 3 个（`burn_one.tcl`/`burn_bit_vivado.tcl`/`ila_capture.tcl`）**只被 `info complete` 验过**，没有其它门禁。

---

## 6. 改进清单（按投入/收益排序）

| 优先级 | 改进 | 归属 | 依据 |
|---|---|---|---|
| P0 | 预设加"Vivado 启动配方"硬事实：`-FilePath <bat> -ArgumentList <数组>`；禁 `win_bash` 直调、禁 `cmd /c <带引号整串>` | 预设 persona | 1.1–1.3 |
| P0 | 预设加"长构建必须脱离进程树"模板（CIM + 标记行 + checkpoint 分段） | 预设 persona | 2.1–2.3 |
| P0 | 预设加判据："`exit!=0` 且零输出 = 启动失败"；探活改用 batch Tcl banner | 预设 persona | 1.2/1.6 |
| P1 | `run_tcl_file(path, background, log)`；`run_tcl` 加 `stdout_tail_bytes` | vivado-mcp | 3.1/3.3 |
| P1 | `check_bitstream_readiness` 支持 `dcp_path`/`run_name`，或明示"不适用" | vivado-mcp | 3.2 |
| P1 | `get_timing_report` 加 `include_paths=false`/`max_paths` | vivado-mcp | 3.5 |
| P1 | `xdc_lint` 内置 GT/MIG 良性族分组（或 `port_family_allowlist`） | vivado-mcp | 3.6 |
| P1 | `ci_check.py` 自动探测 Vivado `tclsh85t`，第 5 项不再 SKIP | 仓库 CI | 5.1 |
| P2 | 技能补"板卡不在场"离线流程 + 负向对照口径 | 技能包 | 4.1 |
| P2 | 技能/预设维护"实际工具清单 + 离线/会话依赖"表 | 技能包 | 4.2 |
| P2 | 预设加"操作 → 首选工具"决策表 | 预设 | 4.3 |
| P2 | 把"报告文件 vs 即时查询"交叉核对写进默认步骤 | 技能包 | 3.4 |
| P2 | 核心侧排查"CIM 子进程为何会收到 CTRL_C" | dsh core | 2.3 |

### 6.1 可直接粘贴进 `Vivado` 预设 persona 的片段（`[建议]`，实测支撑见 §1–§2）

> **已落地（2026-10-25）**：实际文本在 `dsh-vivado/templates/persona/2023.1.frag.yml` 与 `2025.2plus.frag.yml`（两档同步改），并去掉了对第三方 shell（`win_bash`）的依赖；落地与验证证据见 §9。

```text
- Vivado 启动矩阵（2026-10-24 本机实测）：win_bash 里 `cmd //c vivado.bat` 会杀掉持久 bash；
  pwsh 里 `& vivado.bat` / `cmd /c "…" | Out-String` 会静默 exit=1 且零输出。
  唯一稳定写法：Start-Process -FilePath <Vivado>\bin\vivado.bat
  -ArgumentList @('-mode','batch','-source',$src,'-notrace','-log',$log,'-journal',$jou)
  -NoNewWindow -PassThru -RedirectStandardOutput <console> -RedirectStandardError <console>.err
- 探活判据：必须看到 banner 或 TCL_OK；`exit!=0 且 0 字节输出` = 启动失败（不是成功）。
- 长构建：不得挂在会话后台作业上（回合结束即被杀）。用 WMI 脱离：
  Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='cmd.exe /c <build.cmd> > <log> 2>&1'}
  构建脚本自己落 BUILD_START/SYNTH_OK/IMPL_OK/BUILD_FAILED 标记行，外部只认标记行。
- 能分段就分段：synth 落 pre_impl.dcp，实现段可单独重跑（本次 ^C 打断后只重跑 34 min，不重做 synth）。
- 排查期杀进程：先 tasklist 定位 PID，再杀单个；不要 `taskkill /T` 打整棵树（会波及无关子进程）。
- 轻量 Tcl 语法门禁：PATH+=<Vivado>/lib/win64.o、TCL_LIBRARY=<Vivado>/tps/tcl/tcl8.5，
  然后 <Vivado>/bin/unwrapped/win64.o/tclsh85t.exe 跑 `info complete`（8.5.14，与 Vivado 同版本）。
```

---

## 7. 附：本会话时间账（2026-10-24）

| 时段 | 在做什么 | 结果 | 是否被工具链拖累 |
|---|---|---|---|
| 20:50–20:52 | 读文档、摸 prj11 事实 | ✅ | 否 |
| **20:52–20:58** | **"Vivado 起不来"**：bash 被杀 → pwsh 静默 → `Start-Process` 三版 | ✅ 收敛出配方 | **是（~6 min）** |
| 20:58–21:03 | fork 复制、`create_project.tcl`（~2 min）、首次 synth 启动 | ✅ / 半 | 否 |
| 21:03–21:49 | （回合间隔；**后台作业被系统回收**，synth 死） | — | 环境（非工具） |
| **21:49–22:03** | 发现作业已死 → CIM 脱离试验 → `build_p1.cmd` 三版（UTF-8/GBK、缺 `call`、重试循环） | ✅ | **是（~14 min）** |
| 22:03–22:15 | OOC IP 并发崩 `TclStackFree` 的判别与"逐 run 重试"设计 | ✅ 16/16 过 | 半（Vivado 侧问题，但加重了绕坑成本） |
| 22:15–22:25 | synth（DDR4 重生成 + OOC 逐 run + 顶层 + ILA 插入） | ✅ 10 min | 否 |
| 22:25–23:05 | impl（首次 4 min 后被 `^C` 打断 → 重跑 34 min） | ✅ | **是（~5 min 重跑）** |
| 23:05–23:30 | 报告/文档/提交 | ✅ | 否（WNS 口径 bug 靠 §3.4 交叉核对才发现） |

> 有效工作约 **2 h 15 min**（另有 46 min 回合间隔），其中约 **25 min** 直接消耗在"工具怎么起 / 被系统或 `^C` 打断"上；
> 另有 ~12 min 是 Vivado 自身的 OOC 并发崩（不是插件问题，但把"重试设计"变成了必修项）。
> 这些都不产生设计价值，是本文的主要动机。

---

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-25 | 建文：按 5 类（启动层/会话作业/MCP 覆盖度/技能文本/CI）整理 16 条实测问题 + 13 条改进建议 + 时间账 |
| 2026-10-25 | 落地 §6 里属于本包与仓库 CI 的 6 条（P0×3、技能×2、CI×1），并解除对第三方 shell 插件的依赖；新增 §9 落地记录 |

---

## 9. 落地记录（2026-10-25）

> 原则：只写**已经改进并验证**的项。`vivado-mcp` 侧 4 条（§6 P1）按「PR 优先、不做私有 fork」**未动**，仍等上游。
> 本轮前提变化：作者环境里 `@linxin666/dsh-win-bash` 已禁用，且他人环境不一定有 —— 所以不再"适配第三方 shell"，改成**只用会话里真实存在的官方 `pwsh`/`bash`**。

### 9.1 与 §6 清单的对应

| §6 条目 | 落到哪 | 怎么验证的 |
|---|---|---|
| P0 启动配方（1.1–1.3） | persona 两档 + 新增 `tools/vivado-probe.ps1`、`tools/vivado-run.ps1` | 真机：`PROBE_RESULT=OK`（PROBE_EXIT=0 / TCL 8.5.14）；`RUN_RESULT=OK`（exit 0） |
| P0 判据（1.2/1.6） | persona 两档 + `vivado-probe.ps1` 的 `PROBE_*` 契约 | 同一轮探针输出里 banner=yes、TCL_OK=yes、EXIT=0 三条同时成立才判 OK |
| P0 长构建脱离（2.1–2.3） | `vivado-run.ps1 -Detach` + `templates/build-markers.tcl` + persona 纪律 | 真机 detach：`RUN_RESULT=LAUNCHED`，6 s 后状态文件出现 `BUILD_EXIT=0`，Vivado 计数 0 |
| 1.5 轻量 Tcl 解释器 + 5.1 CI 门禁 | 新增 `tools/tcl-check.ps1`；EIF `scripts/ci_check.py` 第 5 项改探测顺序 | `tcl-check.ps1` 对 prj12 的 7 个 `.tcl`：7/7 `complete=1`、`TCLCHECK_RESULT=PASS`（Tcl 8.5.14） |
| 2.3 `taskkill /T` 纪律 | persona 两档 + `docs/troubleshooting.md` §2.13 | 文本断言（见下） |
| 3.4 报告 vs 即时查询交叉核对 | persona 两档 + 技能 §9 | 文本断言 |
| 4.1 板卡不在场离线流程 | 技能 `vivado-workflow-discipline` §8 | 文本断言 |
| 4.2 工具清单/离线依赖 | 新增 `docs/tools.md`（32 工具按签名分类） | 与 32 一致；分类依据写在文首 |
| 4.3 操作→工具决策表 | persona 两档 + `docs/tools.md` §1 | 文本断言 |
| **（本轮新增）第三方 shell 依赖** | persona 两档 + 4 处文档 | `dev/validate_patch.py` 新增 `PERSONA_FORBIDDEN`（`"is the shell for command work"`、`"fall back to \`win_bash\`"`）；两档 validate PASS |

### 9.2 验证证据（2026-10-25 真机）

| 门禁 | 结果 |
|---|---|
| `py tools\gen_skills_manifest.py --check` | PASS（8 技能，sha256 `f6372ec0…`） |
| `py tools\make_template.py --check` | PASS（22 行、9 占位符、无个人路径） |
| 两档渲染 + `dev\validate_patch.py --tier` | 2023.1 PASS（persona 25 行/7268 字符）、2025.2plus PASS（25 行/7093 字符） |
| `dev\accept_all.py --only static` | **9/9 PASS**（新增「launcher assets present and ASCII-only」一条；矩阵 49→50） |
| `tools\vivado-probe.ps1` | `PROBE_EXIT=0`、`PROBE_RESULT=OK`（Vivado 2023.1 / Tcl 8.5.14） |
| `tools\vivado-run.ps1`（wait） | `RUN_EXIT=0`、`RUN_RESULT=OK`，状态文件 `BUILD_EXIT=0` |
| `tools\vivado-run.ps1 -Detach` | `RUN_RESULT=LAUNCHED`，轮询 6 s 见 `BUILD_EXIT=0`，Vivado 计数 0 |
| `tools\tcl-check.ps1 <prj12 scripts>` | `TCLCHECK_RESULT=PASS`（7/7） |

### 9.3 这一轮**新踩到的坑**（都已写进代码注释/文档，别再踩）

1. **WinPS 5.1 对 `.bat` 的 `Start-Process -PassThru` 拿不到 `ExitCode`**：Vivado 已正常 `Exiting`，`$proc.ExitCode` 仍是 `$null` ⇒ 按它判退出码会全错（第一版脚本就是这么判错的）。改法：生成 `.cmd` 包装器，让 cmd 自己把 `%ERRORLEVEL%` 写进 `build_status.txt` 再读回来。
2. **批处理里不加 `call` 调用另一个 `.bat`，控制权不返回**：`vivado.bat` 末行是 `exit /b %errorlevel%`，包装器里直接 `"vivado.bat"` 调用导致 `BUILD_EXIT` / `BUILD_FAILED` 两行**永远不执行** ⇒ 退出码仍然丢失（第二版复测 FAIL 的根因，用最小 `.bat` 对照实验定案）。加 `call` 后通过。
3. **cmd 的 `%DATE%` 在中文 Windows 带「周日」**：cmd 按 OEM/GBK 写入，任何 UTF-8 读取都得到乱码 ⇒ 状态行只用 `%TIME%`。
4. **`dsh-tool-pwsh` 在本机后端是 Windows PowerShell 5.1**（`$PSVersionTable` 实测 5.1.26100）：persona 因此写明"不要假设 PowerShell 7 语法"。
5. **EIF `scripts/ci_check.py` 的 `git ls-files` 解码坑**（本轮顺手修掉）：`subprocess.run(..., text=True)` 在中文 Windows 上按 GBK 解码 git 的 UTF-8 文件名 ⇒ `UnicodeDecodeError` 被 `except Exception` 吞掉 ⇒ **退回全盘 `rglob`**。实测：应扫 **2730** 个已跟踪文件，实际扫了 **17969** 个（含未跟踪/`.gitignore` 项），而输出仍写"已跟踪文件"。修法：`encoding="utf-8", errors="replace"`。
6. **工具链版本漂移会让 MCP 行被静默丢弃**：本轮 `dsh.cmd --version` 已从 `0.2.1-rc.2` 变成 **`0.2.1-rc.3`**，而 `compatibility.json` 只允许 `rc.2` ⇒ `doctor` 第 12 项 WARN，MCP 行可能在重启后**静默消失**（正是 §2.2 那类症状的前置条件）。已把 `rc.3` 合并进豁免（备份 `compatibility.json.bak-20261025`）→ 该项转 PASS。

### 9.4 仍未做的（如实挂账）

- §6 P1 的 4 条 vivado-mcp 改动（`run_tcl_file` / `background` / `include_paths=false` / `xdc_lint` 良性族分组）：属上游仓库，按「不做私有 fork」未动。
- `2025.2+` 档依旧没有任何实测；本次只保证"两档纪律同步"。
- 本包新增脚本的**脱离式构建只验证到 6 秒的小 Tcl**（真实 34 min 实现段未在本轮重跑）。
