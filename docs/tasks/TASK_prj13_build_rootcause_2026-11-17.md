# 任务派发：定位 prj13 单板修复版构建超时（PC2）并给出接管判定

## 0. 任务角色与目标

你是本次排查的执行 agent。目标不是“再跑一遍构建”，而是：

1. **定位** 2026-11-17 PC2 上 prj13 单板修复版（A 参数对照）构建从 14:55 跑到 17:10 仍未完成一轮的根因；
2. 判定根因属于 **PC2 工具/环境（优先怀疑）**、**工程/路径/脚本**、**设计/时序收敛**，还是 **测量/包装器假象**；
3. 给出明确决策：**PC2 修复环境后重跑**，还是 **移交 PC1 接手构建**；
4. 若移交，产出可直接执行的交接清单（源提交、patch、参数、命令、产物/哈希、验收标记）。

**不要**在没有证据的情况下改 RTL、改协议、改冻结点，也不要用“CPU 还在涨”证明构建正常。

## 1. 已知事实（先读，不要重复踩坑）

- EIF issue #2 最新状态评论：`6944430015`（2026-11-17，PC2）
  - `STOPPED_BY_USER / INCOMPLETE`；停在 **route Phase 17.1.1 Update Timing / Post Hold Fix**；
  - 启动 **14:55:53**，停止 **17:10**；job `tcljob-20261117-145552-ee653b`；
  - 中间时序 WNS **-0.212 ns**、TNS **-3.819 ns**、WHS **+0.004 ns**、THS 0；**只是 route 中间值**，不是最终门限；
  - 无 `IMPL_GATE`、`IMPL_BUILD_OK`、`BASELINE_IMPL_OK`；无新 bit/ltx/READY；
  - 未连 JTAG、未烧录、未做档 1/档 2；两档 `NOT_TESTED`。
- 详细现场记录：`AFTERNOON_SUMMARY_2026-11-17.md`（PC2 本地；本文末尾给出要点）。
- 源码基线：`3ce6eb1dfe7ab15ddefb1d41201a83f87cf0b870`（含前导/SFD 修复 `ae666ef7`）。
- 输入：44 个设计文件 + 6 个 XCI 已核对指纹；综合 DCP `pre_impl_debug.dcp`（23,714,181 B，SHA256 `1b75a934…b4ee3`）已通过；post-place DCP `post_place_retry_01.dcp`（47,000,837 B）。
- 工具：Vivado 2023.1，part `xcku060-ffva1156-2-i`；配方含 `ExtraPostPlacementOpt` 与 WNS/WHS≥0 门限。
- 本轮是 **A 参数修复对照、单板验证用**，不是正式 V4 A/B 候选；不能拿它替代双板验收。
- 已知旧候选 `CFA98553`/`F16FCE70` 全部作废，不得作为回退。

## 2. 核心问题（按优先级）

### Q1（第一优先，用户怀疑）：是不是 PC2 工具/环境问题？
逐项排除：
- **主机资源**：CPU 型号/核心/线程、当前频率、负载、温度/降频、电源计划、是否电池供电、内存/页承诺、磁盘类型/队列、Windows Defender/杀软实时扫描、Windows Update/索引、其他 Vivado/xsim/游戏/渲染进程。
- **Vivado 配置**：`general.maxThreads`、job 数、license、Vivado 安装路径/版本、`TEMP/TMP` 路径、进程亲和性、命令行参数、日志/jou 是否在被包装器重定向。
- **路径/文件系统**：工程是否在 junction/OneDrive/网络盘/非 ASCII 路径；D: 是否 HDD/低速盘；DCP 是否被 AV 扫描或锁；路径长度；只读源被写入。
- **包装器**：PowerShell wrapper 是否阻塞/缓冲；`rc=0` 是否假成功；`Get-Process` 看到的 PID 是否真是 Vivado；CPU 增长是否只是日志写入/单线程轮询。

### Q2：是不是工程/脚本层面（非设计）？
- 是否误用了错误的 Vivado 安装（`D:\vavido` vs `D:\Xilinx`）；
- 是否在**同一个工程目录**上重复/并发运行，或复用了被中断的 checkpoint；
- `create_project/build_synth_only/build_impl` 的 P/proj 根是否指向预期目录；
- 是否缺少 `post_route` checkpoint 恢复点，导致 route 从头开始；
- `build_impl.tcl` 的 route directive/seed/phys_opt 是否与 PC1 成功构建不同。

### Q3：是不是设计/时序收敛（最后再归因）？
- route Phase 17.1.1 反复 hold fix 是否因为 WHS 余量只有 +0.004、P2 前导修复后组合逻辑增加；
- 对照 PC1 同 commit、同配方构建耗时（B1D 约 39 min 通过；P2 F16FCE70 历史因主机睡眠/争用曾跑数小时）；
- **中间 WNS -0.212 不是设计失败证据**；只有最终 `IMPL_GATE`/失败端点/拥塞报告能说明。

### Q4：是不是“没卡死，只是很慢”？
- 用日志时间戳/阶段推进判断，不只看 CPU；
- 若 route 每 10–20 min 仍有新 Phase/iteration，说明在算；否则可能 I/O/锁/挂起。

## 3. 调查步骤（建议 60–90 分钟内出结论；先取证，后受控复跑）

### Step 0：取证（不启动新构建，15 min）
1. 读取并整理 `runtime/impl_retry_01/` 下 log/jou/job/rc、`stop_record.json`、`pre_impl_debug.dcp`、`post_place_retry_01.dcp`；
2. 建立时间线：create/synth/place/phys_opt/route 各阶段起止、route 迭代、最后日志行时间；
3. 提取：ERROR/CRITICAL WARNING、`Phase 17.1.1` 前后文本、`route_design` 参数、`general.maxThreads`、part/version、路径；
4. 检查进程/系统残留：`Get-Process vivado,xsim,xvlog,xelab`、`Get-Process | Sort CPU`、`Get-CimInstance Win32_Processor`、内存/磁盘/电源计划/电池/Defender 排除项。

### Step 1：主机与工具基线（15 min）
在 PC2 采集并记录（命令可按本机调整）：
```powershell
Get-CimInstance Win32_Processor | Select Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,CurrentClockSpeed,LoadPercentage
Get-CimInstance Win32_OperatingSystem | Select TotalVisibleMemorySize,FreePhysicalMemory
Get-PSDrive D
powercfg /getactivescheme
Get-MpPreference | Select ExclusionPath,DisableRealtimeMonitoring
Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name,Id,CPU,WorkingSet
```
Vivado Tcl（在 batch 中，不打开板）：
```tcl
puts [get_param general.maxThreads]
report_property [current_project]
report_utilization -file util.rpt
report_design_analysis -congestion -file congestion.rpt
```
检查 `build_impl.tcl` 是否显式设置线程/`-jobs`/`ExtraPostPlacementOpt`。

### Step 2：受控复跑（不要直接再跑完整 3 小时）
二选一，优先 A：
- **A. 从 post-place checkpoint 受控 route**：复制 `post_place_retry_01.dcp` 到临时目录，用 `route_design -directive Default`（或原配方）跑 15–20 min，监控 CPU/磁盘/日志阶段；能推进到 route 完成则说明设计可收敛、原构建是环境慢；仍卡同一 Phase 则记录并转设计/工具排查。
- **B. 小规模基准**：用已有综合 DCP 或小设计做 `synth/impl` 计时，测 PC2 的 Vivado 基线速度，与 PC1 同版本同 part 对比。
> 受控复跑必须新建 job/目录，不能续接已停止进程；不得覆盖原 log/checkpoint。

### Step 3：对照（关键）
- 若 PC1 可用：用**同一源提交 `3ce6eb1` + 同配方**在 PC1 跑一次构建，记录各阶段耗时（这是“接管”的第一步，也可作为基线）；不要在 PC2 与 PC1 同时抢同一工程/许可。
- 对比 PC2 与 PC1 的：CPU/线程、Vivado 版本/安装、TEMP/路径、磁盘、AV、route 阶段耗时。
- 若 PC1 同配方 40–60 min 完成、PC2 3 h 未完成，基本可判 PC2 环境/资源问题；若 PC1 也同样慢，转设计/时序/配方。

## 4. 判定与接管条件

| 判定 | 证据门槛 | 行动 |
|---|---|---|
| **ENV（PC2 环境/资源）** | 受控复跑显示 CPU/磁盘/AV/电源/路径瓶颈；同 checkpoint 在 PC1 快数倍 | 修环境（电源/排除项/线程/临时盘），PC2 重跑一次并设定 90 min 超时监控 |
| **TOOL（Vivado/脚本）** | maxThreads=1、错误安装、错误工程根、日志缓冲/包装器阻塞 | 修工具/脚本后重跑；记录版本/参数 |
| **DESIGN（收敛）** | 同 checkpoint 在 PC1 也卡同一 Phase，或拥塞/时序报告明确 | 不改 RTL 先出报告；由负责人决定 route 策略/seed/时序修复；V4 保持 BLOCKED |
| **UNKNOWN** | 60–90 min 内无法收敛到以上 | **移交 PC1 构建**，PC2 不再重复构建 |

**接管触发（满足任一）**：
- 60 min 内无法给出 ENV/TOOL/DESIGN 的 L2 以上结论；
- 修复环境后一次重跑仍 >90 min 无 `IMPL_GATE`；
- PC2 构建耗时 > PC1 同配方基线 2 倍且原因不明；
- 继续排查会占用板窗口/影响单板验证排期。

**接管方式**：PC1 使用 `3ce6eb1` + 同 patch/参数/配方构建 A 版本（本轮为单板修复对照，不加正式 V4 的 DROP 观测）；产出 bit/ltx/日志后登记哈希；PC2 保留板侧准备工作，不再重复构建。正式 A/B V4 仍待 G1/G3 后另行构建。

## 5. 交付物（1 页报告，直接可贴 EIF #2）

```text
BUILD-ROOTCAUSE-REPORT | date=2026-11-17 | machine=PC2 | job=<...>
VERDICT: ENV | TOOL | DESIGN | UNKNOWN
CONFIDENCE: L1/L2/L3/L4（列出证据）
TIMELINE: create/synth/place/route 各阶段耗时；最后日志时间；停止点
HOST: CPU/线程/频率/负载/温度/电源/内存/磁盘/AV
VIVADO: version/part/maxThreads/install/TEMP/path/directive
CONTROLLED-RUN: 从 post-place DCP 的 route 结果（是否推进、耗时、最终时序/错误）
COMPARE: PC1 同源同配方结果（若已跑）
DECISION: RERUN_PC2（预计 <X min） | TAKEOVER_PC1（已交接项/待交接项）
NEXT: 具体动作、负责人、ETA、是否需要板窗口
EVIDENCE: log/jou/rc/checkpoint/报告路径 + SHA256
```

同时：
- 更新 EIF #2（由 PC1 代发，或把报告交给负责人）；
- 若接管，附 `build_recipe.md`：源 commit、patch 列表/哈希、A 参数五元组、Vivado 路径/版本、create/synth/impl 命令、产物命名/哈希、验收标记；
- 失败/停止的原始文件只增不覆盖，不把 `rc=0` 写成成功。

## 6. 约束

- 不访问板卡、不烧录、不改 RTL/协议/冻结文档；
- 不杀无关进程、不重启主机、不改电源计划前先记录原值；
- 不并发跑 Vivado 会话；受控复跑用独立目录/新 job；
- 不把中间 WNS 当最终时序；不把“CPU 在涨”当构建正常；
- 不重复启动完整构建来“碰运气”；先取证、再受控复跑、再决定接管；
- 若发现 PC2 环境问题是**临时性**（如 AV 扫描/Windows Update），记录证据并建议重跑；若是**结构性**（磁盘/CPU/权限），直接建议接管，不在 PC2 上反复试。

## 7. 参考

- EIF #2 评论 `6944430015`（PC2 2026-11-17 状态）
- `AFTERNOON_SUMMARY_2026-11-17.md`（PC2 现场记录，含 checkpoint 哈希/停止点/证据边界）
- EIF #9（D1–D10 决议；D8 构建预算 45–60 min + 1 次重试）
- `prj/project_13/docs/M1_prj13_P2上板验证执行单_2026-11-10.md`（档 1/档 2 判据；本轮只做构建，不做板测）
- `prj/project_13/README.md`（构建流程/产物命名/位流-ltx 配对）
