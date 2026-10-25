# 结论_cross_vivado-mcp 健康与近期使用核查 · 2026-10-24

> 核查人：DSH Team（lead + mcp-health + prj-usage）
> 核查时间：2026-10-24 00:13–00:45（Asia/Shanghai）
> 范围：① vivado-mcp 工具本体功能；② 2026-10-10 → 10-24 近期工程是否正常使用它。
> 纪律：全程对 `D:\vivado-mcp`、`D:\FPGA`、vault 文档的**源码/配置零修改、零删除**；临时脚本只写 `D:\vivado-mcp\tmp\`、`D:\FPGA\tmp*`、`.vivado-scratch\`。
> ⚠️ 唯一副作用：按官方方式运行 `tmp\verify_all.py` 时，它按设计覆盖了 `tmp\recheck_v2_result.json`、`report_tools_result.json`、`live_tools_result.json`（即 2026-10-07 的旧基线，无备份）；`recheck_result.json`（旧套）未受影响。

---

## 0. 一句话结论

| 问题 | 结论 |
|---|---|
| **工具本体正常吗？** | ✅ **正常可用**，无工具级故障。32 工具注册成功，真 Vivado 2023.1 会话/综合/report 全链路实测通过（修正版复测 **17/17 全 PASS**）。 |
| **近期工程正常使用了吗？** | ❌ **实际未使用**。10-10 → 10-23 每一个 Vivado 进程都是 `vivado.exe -mode batch -source xxx.tcl`；vivado-mcp 的唯一一次运行是 **10-24 00:14 本次自检**。 |
| **原 `verify_all` 报「总体 FAIL」** | 假红。复检脚本自身的 3 个缺陷造成（1 假 FAIL + 4 假 PASS），已定位到文件:行号。 |
| **当前 DSH 会话挂了这 32 个工具吗？** | ❌ **没挂**。desktop profile 的 `cordis.patch.yml` 无任何 MCP server 条目 → 本会话工具列表零 `mcp__*` 工具，只能走 `mcp_ctl.py` CLI 桥。**`.dsh/skills/hw-*/SKILL.md` 里「会话已挂 vivado-mcp（32 工具）」的表述与实际不符**（那是条件句，不是现状）。 |

---

## 1. 工具本体：正常（真实得分账）

### 1.1 复检原始结果（`D:\vivado-mcp\tmp\verify_all_20261024.log`）

```
[PASS] 离线+会话核心: exit=0 FAIL=0/13
[PASS] 离线报告解析: exit=0 FAIL=0/3      ← 其中 2 项是假绿
[FAIL] 会话内工具:   exit=0 FAIL=1/9      ← 该 FAIL 是假红，另 2 项假绿
==> 总体: FAIL（见上）
```

**真实账 = 20 真绿 + 2 假绿 + 1 假红 + 2 连带假绿**，而非文档写的「25/25 全绿」。

| 套 | 脚本 | 声称 | **真实** |
|---|---|---|---|
| 套1 离线+会话核心 | `tmp\recheck_v2.py` | 13/13 | **13/13 真绿**（文本级判据复算 0 误判） |
| 套2 离线报告解析 | `tmp\report_tools.py` | 3/3 | **1 真绿 + 2 假绿** |
| 套3 会话内工具 | `tmp\live_tools.py` | 9/9 | **6 真绿 + 1 假红 + 2 假绿** |
| 修正版复测 | `tmp\live_fixed_20261024.py` | — | **17/17 全 PASS**（同步综合 + 真实 report） |

### 1.2 套1：13 项真绿（含真 Vivado）

真 Vivado 2023.1 起会话（10.3 s）、`run_tcl`、`open_project` prj9、`get_project_info`（part `xcku060-ffva1156-2-i`、top `aurora_udp_bridge`）、`list_sessions`、`stop_session`、离线 `parse_xpr` / `parse_bit_header` / `parse_ltx`（3 ILA + dbg_hub，45 probe）/ `xdc_lint`（2 条 MISSING_IOSTANDARD 属设计侧）。

### 1.3 套2 的两个「假绿」

`tmp\report_tools.py:32-35` 给 `get_utilization_report` / `get_io_report` 传了 `report_file`，但这两个工具**源码里根本没有该参数**：

- `D:\vivado-mcp\site\vivado_mcp\tools\report_tools.py:53` → `get_io_report(session_id, ctx)` — 无 `report_file`
- 同文件 `:308` → `get_utilization_report(detail, session_id, ctx)` — 无 `report_file`
- 只有 `:91-130` 的 `get_timing_report` 支持离线 `report_file`（`get_cdc_report` 也支持，见 `cdc_tools.py:34-44`）

于是两次调用落到 `[ERROR] 会话 'default' 不存在。请先调用 start_session。`，而 `tmp\verify_all.py:26-41` 的 `count_fail` 对无 `steps` 键的结果**只数 `is_error`** → 记成 PASS。**这是 README 自己警告过的「判据陷阱」，脚本仍未修干净。**

### 1.4 套3 的「假红」——量化根因

- `tmp\live_tools.py:36` 标签写 `run_synthesis(async)`，却**没传 `"wait": False`**；
- `run_synthesis` 默认 `wait=True`（`flow_tools.py:318` → `_launch_and_wait`，`:203` 才走异步返回）；
- `tcl_scripts.py:71-86` 的 `LAUNCH_RUN_IF_IDLE` 每次都 `reset_run` + `launch_runs`，**全量重综合，无增量复用**；
- 实测 prj9 综合：`synth_design` elapsed **00:01:38**（`prj/project_9/prj/project_9.runs/synth_1/runme.log:1119`），整段墙钟 **136.8 s**；
- 客户端 `read_timeout_seconds=120` → **在综合完成前 17 s 超时** → `MCPError: Request 'tools/call' timed out`。

而综合**其实成功了**：`__synthesis_is_complete__`、`aurora_udp_bridge.dcp`(988 KB)、`aurora_udp_bridge_utilization_synth.rpt` 均于 00:16 落地。

连带的两个「假绿」：紧随的 `get_utilization_report` / `get_io_report` 返回 `[ERROR] Common 17-53 No open design`，但 `live_tools.py:18` 的 `bad()` **只在 `tcl=True` 时启用**（`:37-38` 没传），故记成 PASS。

### 1.5 修正版复测：17/17 全 PASS（决定性证据）

`D:\vivado-mcp\tmp\live_fixed_20261024.py` → `live_fixed_20261024.log` / `_result.json`，三处修正（`wait:false` + `get_run_progress` 轮询 + 全量文本级判据）：

| 步骤 | 实测 |
|---|---|
| `run_synthesis(wait=False)` | **1.6 s 返回** `job_id: vfix:synth_1 / 状态: Queued...`（异步语义正确） |
| `get_run_progress` × 9 | 每次正常返回阶段序列 + runme.log 尾巴；结束 `synth_design Complete! / 进度 100%` |
| 综合墙钟 | **136.8 s**（polls=9） |
| `open_run synth_1` | OK（171.1 s） |
| `get_utilization_report` | IOB 25/520 (4.81%)、LUT as Logic 9061/331680 (2.73%)、FF 6628/663360 (1.00%)、LUT as Mem 676/146880 (0.46%)、DSP 0/2760 |
| `get_io_report` | 结构化 JSON：`eth_rst_n → AA33 / IO_T2U_N12_48 / OUTPUT / LVCMOS18 / bank48 / GPIO` |
| `stop_session` | OK |

### 1.6 覆盖度：21/32 已实测，11 项本轮未触达

- 补测 PASS：`xdc_auto_fix`（dry-run，修正 2 条 MISSING_IOSTANDARD 预览，未写盘）、`query_waveform`（离线 VCD）、`compare_xci`（对 **XML 版** .xci 可用：相同 17 / 差异 58）、`verilog_compile_check`（优雅降级 SKIP）。
- **未触达 11 项**（需会话/硬件/长跑，不是失败证据）：`check_bitstream_readiness`、`generate_bitstream`、`get_cdc_report`、`get_next_suggestion`、`get_pre_commit_summary`、`program_device`、`run_implementation`、`safe_tcl`、`set_wave_analog`、`set_wave_zoom`、`verify_io_placement_tool`。

### 1.7 已知限制（不算故障）

| 工具 | 状态 | 说明 |
|---|---|---|
| `compare_xci` | 对 2023.1 工程**实际不可用** | 只解析 XML 版 .xci；Vivado 2020.1 起 .xci 改 JSON → 恒报 `XML 解析失败`。工具没坏（XML 版实测可用）。旁路：`inspect_ip_params` 或直读 JSON。 |
| `verilog_compile_check` | **不可用** | 无 `iverilog` / `verilator` / `vvp` → 返回 SKIP + 安装指引，不报错。 |
| CLI 桥进程模型 | 结构性限制 | `mcp_ctl.py` 每次调用新起 MCP server 进程，**会话不跨进程**；多步必须写成单进程脚本（模板 `tmp\bridge_template.py`）。 |

### 1.8 双份（实为三份）安装 —— 隐患清单

| 场景 | `import vivado_mcp` 命中 |
|---|---|
| `cwd=D:/FPGA` + `PYTHONPATH=D:\vivado-mcp\site`（**桥的实际环境**，`mcp_ctl.py:23-26,31-39`） | ✅ `D:\vivado-mcp\site\vivado_mcp` 0.3.26（正确） |
| `cwd=D:\FPGA\vivado-mcp` | ⚠️ `D:\FPGA\vivado-mcp\vivado_mcp`（`sys.path[0]=''` 即 cwd，**影子覆盖**） |
| 不设 `PYTHONPATH`（venv 的 `_mcp_pilot_paths.pth` 生效） | 🚨 `C:\Users\***\Desktop\毕设\.mcp-pilot\site\vivado_mcp`（**含中文路径的旧副本**） |

- 三份源码 **byte-identical**（各 58 文件，`diff -rq` rc=0），所以眼下**无行为差异**；但版本号都是 0.3.26，**不能靠版本号区分副本，只能看 `__file__`**。
- 🚨 **最危险的一条**：任何客户端用 `venv\Scripts\python.exe -m vivado_mcp` 而**不显式设 `PYTHONPATH`**，会命中 `.mcp-pilot` 中文路径副本 → `_locate_server_script()` 按包 `__file__` 定位 tcl（`gui_session.py:272-300`）→ 中文路径经 GBK 解码坏 → `start_session` **静默失败**；而 `_check_ascii_paths()` 只查 `vivado_path`+cwd（`session_tools.py:112-136`），**不会告警**。

---

## 2. 复检脚本的 3 个缺陷（修复建议，未动手）

| # | 文件:行 | 缺陷 | 改法 |
|---|---|---|---|
| 1 | `tmp\live_tools.py:36` | `run_synthesis` 未传 `wait:False`，标签却叫 async；120 s 客户端超时 < 实测 137 s | 加 `"wait": False`，随后补 `get_run_progress` 轮询 + `run_tcl("open_run synth_1")`（`live_fixed` 已证明可行）；或保留 `wait=True` 但 read_timeout 提到 ≥600 |
| 2 | `tmp\live_tools.py:18,24,37-38` | `bad()` 仅 `tcl=True` 生效 → 2 个假 PASS | 拆成 `bad_text()`（`[ERROR]`/`ERROR:`，**所有调用生效**）+ `bad_tcl()`（额外含 `CRITICAL WARNING: [Common 17-`，仅 tcl 调用，且 `get_critical_warnings` 白名单） |
| 3 | `tmp\report_tools.py:32-35` | 给无 `report_file` 参数的工具传该参数 | 删掉这两个调用；离线套只测 `get_timing_report`（+ `get_cdc_report`，但本机无 fixture → 标 SKIP）；两个会话内工具移到套3 |
| 4 | `tmp\verify_all.py:26-41` | 非 `steps` 型结果只数 `is_error` | 加文本判据 `is_error or "[ERROR]" in text`；子脚本补 `sys.exit(1 if nf else 0)`（`recheck_v2.py:74-79`、`live_tools.py:44-46` 现在恒 0，`verify_all.py:58` 的 rc 判据其实是冗余的） |
| 5 | `mcp_ctl.py:91` | 退出码只看 `isError` → 桥吞错 | 加文本判据或 `--strict`；实测 `compare_xci` 打 `[ERROR]` 仍 `EXIT=0` |
| 6 | `README_迁移说明.md:3,13-16,55` | 「25/25 全绿」不实 | 改成：**真绿 20 + 套2 2 项误测待修 + 套3 修正版 17/17 + 已知不可用 2 项** |

> ⚠️ 注意（mcp-health 纠正）：**不能把原 `bad()` 无脑全量启用** —— 它含 `CRITICAL WARNING: [Common 17-` 标记，恰是 `get_critical_warnings` 的合法输出内容，全量启用会误伤该工具。

---

## 3. DSH 集成现状：**未挂载**

| 事实 | 证据 |
|---|---|
| 当前 GUI 用 **desktop** profile | 进程命令行：`DeepSeek Harness.exe ... C:\Users\***\.dsh\profiles\desktop`（PID 7936，监听 127.0.0.1:59976） |
| desktop profile **零 MCP server** | `~\.dsh\profiles\desktop\cordis.patch.yml`（196 行）grep `vivado|mcp` **无命中**；`package.json` 的 bundles 里也没有 mcp-client |
| 本会话工具列表零 `mcp__*` | 会话内可用的只有内置工具（win_bash/read/grep/…），无 `run_tcl`/`start_session` |
| web profile 有 MCP 条目，但**不是 vivado** | `~\.dsh\profiles\web\cordis.patch.yml:126-135` 是 `mcp-amd-doc-search`（`streamable-http`，AMD 官方文档检索） |
| 官方口径一致 | `D:\FPGA\AGENTS.md:141`（10-22）明写「`hw-ila-debug`/`hw-vio-debug` 依赖的 vivado-mcp MCP **未挂进当前会话**；走 CLI 桥或 batch Tcl」 |

**结论：现在只能用 CLI 桥**（`python D:\vivado-mcp\mcp_ctl.py list|call|session`）。
🚨 `hw-ila-debug` / `hw-vio-debug` 两个 SKILL.md（10-24 修订版）的「会话已挂 vivado-mcp（32 工具）」是**条件句被读成事实**，建议改成「本会话未挂，走 CLI 桥」。

### 3.1 如果要挂（给出配方，未执行）

`~\.dsh\profiles\desktop\cordis.patch.yml` 追加：

```yaml
- insert:
    - id: mcp-vivado
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: vivado
        transport: stdio
        command: 'D:\vivado-mcp\venv\Scripts\python.exe'
        args: ['-m', 'vivado_mcp']
        cwd: 'D:\FPGA'                       # 必须纯 ASCII
        env:
          PYTHONPATH: 'D:\vivado-mcp\site'   # 🚨 必须显式设，否则命中 .mcp-pilot 中文路径副本
          VIVADO_PATH: 'D:/Xilinx/Vivado/2023.1/bin/vivado.bat'
          PYTHONUTF8: '1'
        toolCallTimeoutMs: 1800000           # 🚨 默认仅 60000；run_synthesis 默认 wait=True 实测 137 s
        failOnStartupError: true
```

- 工具名会变成 `mcp__vivado__run_tcl` / `mcp__vivado__start_session` …（共 32 个）。
- 🚨 **`toolCallTimeoutMs` 默认 60000 ms —— 这正是本次复检假 FAIL 的同一个坑**：不提到 ≥1800000，`run_synthesis` / `run_implementation` 必在客户端超时。
- 改完需**重启 DeepSeek Harness**（desktop 宿主进程）才生效。

---

## 4. 近期工程：**实际未使用 vivado-mcp**（10-10 → 10-23）

### 4.1 决定性证据

| 证据 | 内容 |
|---|---|
| 命令行直证 | 167 个含 `Process ID:` 头的 Vivado 日志，**全部** `-mode batch -source xxx.tcl`。例：`prj/project_11/out/evidence_2026-10-22/R2_ilacap_vivado_20261022_164710.log` 头 `# Command line: vivado.exe -mode batch -source D:\FPGA\prj\project_11\out\r2_ilacap.tcl -notrace` |
| `tmp\` 时间空窗 | `D:\vivado-mcp\tmp\` 在 **10-08 19:34 → 10-24 00:14 零文件**（次新 `bit_args2.json` 10-08 19:34:56，下一个就是本次 `verify_all_20261024.log`） |
| 无 MCP 产物形态 | 全 `D:\FPGA` 无任何 `"schema_version"/vivado_timing/vivado_utilization/provenance` 的 JSON（MCP 结构化报告的指纹） |
| 报告可归因到 batch 脚本 | `out/` 下 10-16~10-19 的 `.rpt` 全部由 `scripts\build_v5_sweep2.tcl:31-40`、`build_debug.tcl:330-333` 现算写出 |
| PID 交叉核对 | 10-19 / 10-22 的 `.Xil` 目录 PID **全部**命中 batch 日志，无「无主 Vivado 进程」给 MCP 留位 |

### 4.2 时间线（10-10 起，全线 batch）

| 日期 | 动作 | 工具 |
|---|---|---|
| 10-10 14:18~14:28 | prj11 fork + 建工程 | `vivado -mode batch -source scripts/create_project.tcl` |
| 10-10 14:30 → 10-11 18:35 | B0/B1 构建 12 轮 | batch `build_debug.tcl` / `build_b1_resume*.tcl` |
| 10-12 → 10-13 | B3 构建 | batch |
| 10-14 → 10-16 | B3-1 离线仿真 + 构建（20+ 轮） | batch + xsim |
| 10-17 → 10-19 | R2 sweep / round3b/3c/3d | batch `build_v5_sweep2.tcl`（cwd=`D:/FPGA`） |
| 10-19 15:42/16:29 | **ILA 抓取** | batch `tools/r3c_cap.tcl` |
| 10-22 15:44 → 16:52 | JTAG 检查 + J3 固件 + ILA + S0–S11 验收 | xsct/vitis + batch `out/r2_ilacap.tcl` |
| **10-24 00:14–00:15** | **MCP 自检（唯一一次）** | `verify_all.py` → 32 工具握手、13-13 PASS |

### 4.3 四条坑逐条判定

| 坑 | 判定 | 依据 |
|---|---|---|
| (a) CLI 桥「会话不跨进程」 | **结构性存在**；窗口内**未踩**（因为没用 MCP） | `mcp_ctl.py` 每次 `stdio_client(SERVER)` 新进程；10-24 自检实际复现 `[ERROR] 会话 'default' 不存在` |
| (b) 路径漂移 `project_N → prj/project_N` 假失败 | **无**（窗口内全用新路径） | 日志/脚本/命令行零旧路径；旧路径只剩 `docs/调试记录/*` 历史件（`docs/README.md:7` 已声明保留） |
| (c) `is_error=False` 但文本 `[ERROR]` 误判 | **有（工具缺陷 + 未记账）** | `report_tools_result.json` 3 个调用里 2 个 `is_error:false` 而 text 是 `[ERROR] 会话不存在`；`mcp_ctl.py` 对这类返回 **0（假成功）**；`PITFALLS.md` 68 条、`AGENTS.md` **均无此条** |
| (d) 中文路径 GBK 坑复发 | **部分复发（踩红线但没爆）** | 4 次 batch 以 `C:/Users/***/Desktop/毕设` 为 cwd（PID 14244 / 17632 / 16916 / 12388）；均非编码失败（是 RTL 错 `Synth 8-2577` 与 Tcl 引号 bug），但违反「Vivado 子进程必须 ASCII cwd」红线 |

### 4.4 为什么「未使用」不算故障

- `AGENTS.md:141`（10-22）本来就写着 MCP 未挂 → **文档与磁盘一致，没有「声称用了」的假账**。
- 工程侧 batch Tcl 是**有意选择**：幂等脚本 + 日志落 evidence 目录，比经 MCP 长任务更可控（且 `run_synthesis` 每次 `reset_run` 全量重跑，不吃增量）。
- 代价：MCP 的 `get_timing_report` / `xdc_lint` / `parse_bit_header` 等**离线解析能力被闲置**，报告解析靠自研脚本。

---

## 5. 顺带发现的漂移与风险（非 MCP 故障）

1. **skill 文案**：`hw-ila-debug` / `hw-vio-debug` SKILL.md「会话已挂 vivado-mcp（32 工具）」与事实不符（未挂）。
2. **坑账本缺口**：建议补 **#69**（`is_error:false` + 文本 `[ERROR]` → CLI 桥假成功）与 **#70**（CLI 桥一进程一调用 ⇒ `get_utilization_report`/`get_io_report`/`run_synthesis` 在桥下不可直用）。
3. **写入纪律漂移**：`AGENTS.md:153` 规定原始日志复制到 C: 侧解析、不写回仓库，但 batch 以 `cwd=D:/FPGA` 运行把脏迹落仓库根：`iter_4/iter_5_CongestedCLBsAndNets.txt`(10-18/10-19)、`hs_err_pid32512.log`(10-15, JVM `EXCEPTION_ACCESS_VIOLATION`)、`.tmpCRC/`、`.Xil/`。
4. **归档日期错位**：10-22 16:39 的 ILA 抓取产物落在 `out/evidence_2026-10-19/`（文件名对、目录名错）；16:47 那批才进 `evidence_2026-10-22/`。
5. **文档双份分叉**：vault `C:\Users\***\Desktop\毕设`(10-23 03:08) vs 仓库镜像 `D:\FPGA\docs`(10-22 16:51)，`追踪_cross_短期待办` 25,760 B vs 25,687 B，`README.md` docs 版缺 8 行目录。
6. **不确定项（坦白）**：无法 100% 排除「某次开 GUI 手工点选却没落日志」；11 个 `.Xil` 目录 PID（10-12~10-15）未匹配到 batch 日志头（日志已归档/覆盖），但都不在 10-16~10-23。「2026-10-01 迁移」只有文档口径，无 mtime 硬证。

---

## 6. 建议（按优先级）

1. **不急着挂 MCP**：当前 batch 流水线是有效的。若要挂，按 §3.1 配方，**务必显式 `PYTHONPATH` + `toolCallTimeoutMs ≥ 1800000`**，否则 `start_session` 会静默失败、`run_synthesis` 会客户端超时。
2. **修复检脚本**（§2 四条），并把 `README_迁移说明.md` 的「25/25 全绿」改成真实账，防止下次误判。
3. **给 `mcp_ctl.py` 加文本级判据/`--strict`**，避免 CLI 用户把 `[ERROR]` 当成功。
4. **补坑账本 #69 / #70**，并在 `追踪_cross_短期待办_2026-10-10.md` 写明「10-10~10-23 = batch-only，MCP 仅 10-24 自检」，避免后续会话误以为 MCP 已在工程里验证过。
5. **清理三份安装隐患**：从 `D:\vivado-mcp\venv` 删掉 `_mcp_pilot_paths.pth`（或挪走 `D:\FPGA\vivado-mcp` 与 `.mcp-pilot` 副本），只保留 `D:\vivado-mcp\site` 一处。
6. 若确要让 MCP 进执行层，建议下一轮补测未触达的 11 个工具（`safe_tcl`/`run_implementation`/`verify_io_placement_tool`/`get_cdc_report` 需先造 CDC fixture）。

---

## 7. 证据索引

| 文件 | 内容 |
|---|---|
| `D:\vivado-mcp\tmp\verify_all_20261024.log` | 原复检全过程（25 项，含假红/假绿） |
| `D:\vivado-mcp\tmp\recheck_v2_result.json` / `report_tools_result.json` / `live_tools_result.json` | 三套逐项 JSON（00:14–00:16 覆盖旧结果） |
| `D:\vivado-mcp\tmp\live_fixed_20261024.py` / `.log` / `_result.json` | **修正版复测，17/17 全 PASS**（本轮新建） |
| `D:\vivado-mcp\tmp\list_20261024.txt` / `hc_args_*.json` | mcp-health 的 32 工具清单与补测参数（本轮新建） |
| `.vivado-scratch\scan_sessions2.mjs` / `extract_usage.mjs` | DSH 会话转录（zstd 多帧）解码与使用痕迹统计（本轮新建；全工作区 60 个会话转录，扣除本轮 3 个后，10-23 与 10-21 会话均 batch 命令主导、`mcp_ctl` 调用极少） |
| `D:\FPGA\AGENTS.md:141` / `:153` | MCP 未挂口径 / 日志不写回仓库纪律 |
| `prj/project_11/out/evidence_2026-10-22/R2_ilacap_vivado_20261022_164710.log:9` | 10-22 板验走 batch 的命令行直证 |

**复现命令**

```powershell
$env:PYTHONUTF8 = 1
$py = 'D:\vivado-mcp\venv\Scripts\python.exe'
# 32 工具握手
& $py 'D:\vivado-mcp\mcp_ctl.py' list
# 一键复检（2026-10-24 已修判据；三套 FAIL 均 0，总判据 PASS）
& $py 'D:\vivado-mcp\tmp\verify_all.py'
```

---

## §8 2026-10-24 修复与实装（本轮执行结果）

用户指令「修复并实装验证」，已全部落地并实测。

### 8.1 脚本修复（4 个文件，均有 `*.bak-20261024` 备份）

| 文件 | 改了什么 | 验证 |
|---|---|---|
| `D:\vivado-mcp\tmp\verify_all.py:39-69` | `count_fail()` 重写：非 steps 型除 `is_error` 外扫 `[ERROR]/ERROR:/MCPError`；返回 4 元组；总判据打印失败项 key 与 SKIP/豁免项 | 回归单测：旧 dict 型 `report_tools_result.json` 由 0/3 FAIL → **正确判 2/3 FAIL** |
| `tmp\live_tools.py:96-145` | `run_synthesis` 显式 `wait=False` 异步提交（1.3 s 返回）→ `get_run_progress` 15 s 轮询（上限 15 min）→ `open_run` → 4 个 report 工具 | 套3 **FAIL 0/18**，综合墙钟 106.5 s、polls=7 |
| `tmp\live_tools.py:53-60,68` | 判据拆分 `bad_text()`（全调用生效）/ `bad_tcl()`（仅 tcl）/ `mode="none"` 白名单（`get_critical_warnings`） | 无假 PASS |
| `tmp\report_tools.py:66-93` | 删除对 `get_utilization_report`/`get_io_report` 的非法 `report_file` 调用；`get_timing_report` 校验 `parse_status=="ok"`；`get_cdc_report` 无 fixture → SKIP | 套2 **FAIL 0/2**（1 PASS + 1 SKIP） |
| `D:\vivado-mcp\mcp_ctl.py:100-106` | 默认退出码加文本判据；新增 `--lax` 逃生口 | `compare_xci`(JSON .xci)：严格 **EXIT=2**（修复前 0）、`--lax` **EXIT=0** |

**全套复检终态**（`tmp\verify_all_fixed_20261024.log`，65 行）：

```
[PASS] 离线+会话核心: exit=0 FAIL=0/13
[PASS] 离线报告解析: exit=0 FAIL=0/2   跳过/豁免: get_cdc_report(report_file=?)(SKIP)
[PASS] 会话内工具:   exit=0 FAIL=0/18
==> 总体: PASS（vivado-mcp 可用）
```

> 严谨性插曲：首轮（run1）唯一 FAIL 是 `run_tcl(open_run synth_1)` —— `bad_tcl` 的 CRITICAL WARNING 标记被 prj9 `xdc/aurora_udp_bridge.xdc:92` 既有设计约束错（`Common 17-165 Too many positional options when parsing '双核'`）误伤。已把 `open_run` 改回文本级判据（设计告警由 `xdc_lint` + `get_critical_warnings` 覆盖），run1 日志留档 `tmp\verify_all_fixed_20261024_run1_fail.log`。

### 8.2 文档实装（6 个文件）

| 文件 | 改动 |
|---|---|
| `D:\vivado-mcp\README_迁移说明.md`（108 行） | 结论改真账（13 + 2 + 18）；删「25/25」；补 10-24 判据陷阱复盘、`get_utilization_report/get_io_report` 无 `report_file`、`--lax` |
| `D:\FPGA\PITFALLS.md` | 首行 `#1–#70`；新增 **#69**（`is_error=false` 但文本 `[ERROR]` ⇒ 桥假成功）、**#70**（一进程一调用 ⇒ 会话类工具桥下不可用） |
| `D:\FPGA\AGENTS.md` | §6b `:141` 挂载状态、`:142` amd_doc_search、`:188`/`:227` 坑账本索引续到 #70 |
| `.dsh\skills\hw-ila-debug\SKILL.md`、`hw-vio-debug\SKILL.md` | `:3` 修「已挂」不实表述；`:13` 现役安装改 `D:\vivado-mcp`；`:18` 补显式 `PYTHONPATH` 警告 |
| `.dsh\skills\{vivado-revision-control,vivado-rtl-elaboration-analysis,vivado-rtl-lint,vivado-simulate-rtl}\SKILL.md` | 同段旧路径 `D:\FPGA\vivado-mcp` → 现役 `D:\vivado-mcp`（并注明仓库副本不是运行实例） |
| `D:\FPGA\.gitignore` | 加 `*.bak-*`（备份不再污染 `git status`） |

### 8.3 MCP 挂载实装（`~\.dsh\profiles\desktop\cordis.patch.yml`）

新增 `mcp-vivado` 条目（stdio，`serverName: vivado`，`cwd=D:\FPGA`，显式 `PYTHONPATH=D:\vivado-mcp\site`，`toolCallTimeoutMs=1800000`，`failOnStartupError: false`，`reconnect.enabled: true`）。备份：`cordis.patch.yml.bak-mcp-vivado-20261024`。

**重启前已完成的三重验证**：

| 验证 | 方法 | 结果 |
|---|---|---|
| YAML 有效性 | `js-yaml` 解析 | 顶层数组 15 项、insert 条目 `mcp-vivado` 解析出的 config 与预期逐字段一致 |
| 握手 + 工具数 | 用配置里的 command/args/cwd/env 起 server | **32 工具**，`run_tcl`/`start_session`/`run_synthesis` 等关键工具齐全 |
| **挂载环境可启 Vivado** | 凭据擦洗后的最小 env（只留 PATH/系统变量 + 4 个配置变量）下 `start_session → run_tcl(version) → stop_session` | **PASS：Vivado 2023.1 6.4 s 起来，`version` 返回 `2023.1`** |

**schema 预检（本次新发现）**：宿主 `register()` 只对 `output.schema` 做子集校验（`assertSupportedJsonSchema(output.schema)`），MCP 的 `inputSchema` 原样透传；而 output 侧已有 try/catch 降级（`supportedOutputSchema`）。32 个工具里 `xdc_lint`/`xdc_auto_fix`/`query_waveform` 的 input schema 含 `anyOf`，但宿主支持的子集只列 `type/oneOf/properties/...`（不含 `anyOf`）——已确认 `anyOf` **既不参与注册校验、调用期也被 `checkValue` 忽略**（它只实现 `oneOf`）→ **不会导致挂载失败**，最坏情况是这 3 个工具的参数校验变宽松（服务端 pydantic 仍会兜底）。

### 8.4 生效与冒烟清单

- ⚠️ **必须重启 DeepSeek Harness 才生效**（profile 在启动时读取）；本会话（重启前）仍无 `mcp__vivado__*`，继续用 CLI 桥。
- 重启后冒烟顺序：① 工具清单应出现 32 个 `mcp__vivado__*`；② `mcp__vivado__list_sessions`（不启 Vivado）；③ `mcp__vivado__start_session` + `mcp__vivado__run_tcl('version -short')`；④ 重点试 `xdc_lint` / `query_waveform`（含 `anyOf` 的三个之一）；⑤ 跑 `run_synthesis(wait=False)` + `get_run_progress`（验证 30 min 超时配置）。
- 若某工具在 MCP 下异常，回退路径不变：`D:\vivado-mcp\mcp_ctl.py`（现在带严格退出码 + `--lax`）。

### 8.5 未做/待决

1. `D:\FPGA` 的改动**未 commit**（`.gitignore` / `AGENTS.md` / `PITFALLS.md` 三个 M），由用户决定提交时机。
2. `get_cdc_report` 仍缺 fixture（本机无 `report_cdc` 报告样本）→ 套2 保持 1 SKIP。
3. 32 工具里 **11 个未触达**（需硬件/长跑：`program_device`、`run_implementation`、`safe_tcl`、`set_wave_analog/zoom`、`verify_io_placement_tool`、`check_bitstream_readiness`、`generate_bitstream`、`get_next_suggestion`、`get_pre_commit_summary`、`get_cdc_report`）。
4. 10-22 的 ILA 产物目录错位（`evidence_2026-10-19/` 里的 10-22 文件）与 vault↔`D:\FPGA\docs` 文档分叉，本轮**未动**（属归档纪律，需用户确认后处理）。

---

## §9 重启后的挂载核验（2026-10-24 12:00 起）

**结论：挂载仍未生效 —— 32 个 `mcp__vivado__*` 工具没有出现在任何会话里。**

### 9.1 已排除的原因（逐项实测）

| 环节 | 验证方法 | 结果 |
|---|---|---|
| 配置语法 | `js-yaml` 解析 + `dsh --profile <副本> --dump-config` | ✅ 通过，`mcp-vivado` 行正常出现在合成树 |
| 运行时解析 | `dsh --dump-config-schema` 读 `x-cordis.entries` | ✅ `mcp-vivado` 的 `status: "schema"`（插件被成功 import，Config schema 已收集） |
| 服务端本身 | 用**宿主同一套 TS SDK**（`@modelcontextprotocol/client` v2.0.0 + `StdioClientTransport`，同 env/cwd）连 | ✅ connect OK，**32 工具**全部列出 |
| 输出 schema 合法性 | 用宿主真实 `assertSupportedJsonSchema` 校验 mcp-client 生成的 output schema | ✅ 两种形状都通过；`anyOf` 只存在于 3 个 input schema（不参与注册） |
| 是否有白名单/预设遮挡 | 读 `preset-standard` 等 4 个 agent preset 与 `tools` 行 | ✅ 无工具白名单；MCP 工具走全局 `ctx.tools` |
| 宿主是否为新进程 | `Get-Process` 启动时间 | ✅ 11:53:54 全新启动，配置文件 01:05 就已在位 |
| HMR 热重载 | 改 `cordis.patch.yml` 后观察 | ❌ HMR 未触发（该行 `disabled: !!js '!ctx.get("profileContext")'`，Electron 下大概率为假）→ 必须重启 |

### 9.2 关键反证：那些 `vivado_mcp` 进程不是 DSH 起的

排查中曾看到 4–6 个 `python -m vivado_mcp` 进程（且 PID 不断变化），一度疑似 DSH 在重连。**用父进程链定位后确认：全部属于 `ZCode.exe`**（另一个 AI 工具），命令行是
`C:\Users\***\Desktop\毕设\.mcp-pilot\venv\Scripts\python.exe -m vivado_mcp` —— 旧中文路径安装。

⇒ **DSH 宿主从未 spawn 过 `D:\vivado-mcp\venv` 的 server**。即问题在「插件行未被激活」，不在服务端。

### 9.3 附带发现：ZCode 的 vivado-mcp 配置是坏的，且正在崩溃重启循环

`C:\Users\***\.zcode\cli\config.json` → `mcp.servers.vivado`：

```json
{ "command": "C:\\Users\\***\\Desktop\\毕设\\.mcp-pilot\\venv\\Scripts\\python.exe",
  "args": ["-m", "vivado_mcp"], "cwd": "D:\\FPGA",
  "env": { "TEMP": "C:\\Users\\***\\Desktop\\毕设\\.vivado-scratch",
           "TMP":  "C:\\Users\\***\\Desktop\\毕设\\.vivado-scratch", ... } }
```

三重命中历史坑：① 安装路径含中文（`.mcp-pilot`）；② **TEMP/TMP 指向中文目录**（会复现「临时 tcl 经 GBK 解码坏掉」的坑 #1/#21）；③ 未显式设 `PYTHONPATH`（venv 的 `_mcp_pilot_paths.pth` 会把它引回中文路径副本）。
结果：server 反复崩溃 → ZCode 反复重启 → 系统里长期挂着 4–6 个僵尸 python 进程。
修法（3 行）：`command` 改 `D:\vivado-mcp\venv\Scripts\python.exe`；`TEMP`/`TMP` 改 `D:\vivado-mcp\tmp`；env 补 `"PYTHONPATH": "D:\\vivado-mcp\\site"`。

### 9.4 下一步（已就绪，待一次重启）

已把 config 的 `command/args` 临时换成**可观测包装器** `D:\vivado-mcp\mcp_probe_launch.py`（透明代理，本地实测仍能列出 32 工具），它会往 `D:\vivado-mcp\tmp\mcp_spawn_probe.log` 记录：是否被 spawn、argv、cwd、关键 env、child 的 stderr 与退出码。

- 重启后**若探针日志为空** ⇒ 证明宿主根本没实例化该插件行（问题在 Electron 宿主的行加载/激活），下一步需要宿主启动日志（从终端启动或加 `DSH` 诊断开关）。
- **若探针日志有内容** ⇒ 直接看 child stderr 与退出码，根因即可定位。
- 回退：把 `command` 换回 `D:\vivado-mcp\venv\Scripts\python.exe`、`args` 换回 `[-m, vivado_mcp]`（备份 `cordis.patch.yml.bak-before-probe-20261024`）。

### 9.5 根因（2026-10-24 12:20 定位）：插件被「版本兼容门禁」禁用

用隔离的 `DSH_HOME` + profile 副本引导后，宿主的 stderr 终于可见，每次启动都打印：

```
dsh: disabling profile plugin row "mcp-vivado": Plugin @deepseek-ai/dsh-mcp-client@0.1.7-rc.2
  is incompatible with dsh 0.2.1-rc.2: requirements {"@deepseek-ai/dsh-attachment":"0.1.7-rc.2",
  ... "dsh-system-prompt":"0.1.7-rc.2"}. Running it may cause crashes or data loss.
  ... Exact-version exemption: not active.
```

**机制**：`dsh-app-boot` 在挂载前逐个比对插件的 `engines`/peer 需求与运行时版本（`evaluatePluginCompatibility`）；
不兼容的行会被 **禁用**（不是报错退出），而 Electron 宿主把 stderr 吞掉，所以表现就是「配置对、插件也在，但工具永远不出现」。
配置面、解析面、服务端全部正常 —— 全部被这一道门禁挡住了。

**豁免的落盘位置**（读源码确认，非文档推测）：profile 目录下的独立文件 **`compatibility.json`**，
格式 `{"<包名>@<版本>": ["<DSH 精确版本>"]}`，与 `package.json`/`cordis.patch.yml` 完全解耦
（`PROFILE_COMPATIBILITY_FILENAME = "compatibility.json"`，读取失败时按「无豁免」处理，不会把 profile 弄坏）。

### 9.6 修复与干跑验证

1. 写入 `~/.dsh/profiles/desktop/compatibility.json`：
   ```json
   { "@deepseek-ai/dsh-mcp-client@0.1.7-rc.2": ["0.2.1-rc.2"] }
   ```
2. **隔离干跑**（`DSH_HOME` 指向临时 home + profile 副本，完全不碰在用实例）：
   - `disabling profile plugin row "mcp-vivado"` 出现次数 **0**（修复前每次启动 2 次）；
   - 探针日志出现 **2 次 SPAWNED**（MCP 的「探测进程 + 服务进程」，符合 dsh-mcp-client 文档）；
   - 两个 child 进程 **0 次退出、0 条 stderr** → 连接健康。
3. 隔离实例已全部关闭、临时 home 已删除（64990 端口 0 监听）。

### 9.7 ZCode 修复（用户要求，已完成并实测）

`C:\Users\***\.zcode\cli\config.json` 的 `mcp.servers.vivado` 已改（备份 `config.json.bak-20261024`）：

| 字段 | 旧 | 新 |
|---|---|---|
| command | `...\毕设\.mcp-pilot\venv\Scripts\python.exe`（中文路径） | `D:\vivado-mcp\venv\Scripts\python.exe` |
| TEMP/TMP | `C:\Users\***\Desktop\毕设\.vivado-scratch`（中文） | `D:\vivado-mcp\tmp` |
| PYTHONPATH | 未设 | `D:\vivado-mcp\site` |
| timeoutMs | 600000 | 1800000 |

**实测**（用新 env 起 server）：32 工具 → `start_session` PASS（Vivado 2023.1）→ `run_tcl` 返回 `2023.1` → `stop_session` OK。
旧配置的 4 个僵尸进程已清理（`vivado_mcp` 进程数归 0）。ZCode 需重启才会用新配置。

---

## §10 定论：现版本 DSH 的 MCP 官方入口 + 本次真正的障碍（2026-10-24 12:40）

用户质疑「旧版本能用 MCP、新版不行」不成立 —— **质疑成立，现版本 DSH 完全支持 MCP**。真正的障碍是两个与「版本能力」无关的东西。

### 10.1 现版本 DSH 挂 MCP 的官方方式（读安装包源码确认）

1. **配置面**：在 profile 的 patch 层里加一行 `@deepseek-ai/dsh-mcp-client` 插件（就是本报告 §3.1 的写法，来自安装包内该插件的 README「Minimal configuration」）。工具自动命名 `mcp__<serverName>__<rawName>`。
2. **运行时自带该桥**：安装包 `D:\dsh\resources\app.asar` 内**自带** `@deepseek-ai/dsh-mcp-client@0.2.1-rc.2`（与运行时同版本），另有 `dsh-mcp-resources@0.2.1-rc.2`。
3. **内置 profile 模板**：`acp` / `headless` / `sdk` / `sdk-minimal` / `web`（无独立 `mcp` 模板，MCP 是行级配置，不是独立 profile）。

### 10.2 真正的障碍 #1：解析到了 profile 里的旧副本

profile 的 `node_modules` 里躺着一份 **`@deepseek-ai/dsh-mcp-client@0.1.7-rc.2`**（作为 `dsh-experimental-computer-use-cua-driver-native` 的传递依赖被装进来的）。行解析走的是 **profile 目录**，于是命中这份旧副本，而不是安装包内的 0.2.1-rc.2。

### 10.3 真正的障碍 #2：0.2.1 运行时的兼容门禁把该行**静默禁用**

`dsh-app-boot` 的 `evaluatePluginCompatibility` 比对插件 peer 需求（全为 0.1.7-rc.2）与运行时（0.2.1-rc.2）→ 不匹配的行被 **disable**（不报错退出、不阻断启动），错误只打到 **stderr**；Electron 双击启动时 stderr 无人接收 ⇒ 表现就是「配置都在，工具永远不出现」。

### 10.4 官方修复：exact-version exemption（已完成且验证有效）

错误信息本身给的就是这条官方路径（`dsh plugin allow-version` / 插件管理器 / 手动写文件）：

`~/.dsh/profiles/desktop/compatibility.json`
```json
{ "@deepseek-ai/dsh-mcp-client@0.1.7-rc.2": ["0.2.1-rc.2"] }
```

**实机验证（2026-10-24 12:32 重启后）**：
- 探针日志 12:32:03/04 两次 SPAWNED，child 进程存活、0 stderr（探测进程 + 服务进程，符合插件 README 描述）；
- 新 agent 工具面 = **91 个 = 59 内置 + 32 个 `mcp__vivado__*`**；
- **端到端冒烟**：`list_sessions` → `start_session`(真 Vivado 2023.1 / `VMCP_READY`) → `run_tcl "version -short"` → `2023.1` → 故意跑 `get_property part` 得到结构化 `rc=1 + ERROR: [Coretcl 2-88]`（错误通路可信）→ `stop_session` 干净关闭。

### 10.5 重要行为：已存在的会话不会「长」出新工具

工具目录是**按会话快照**的。本次核查所用的长会话（00:13 创建）即使 MCP 已注册，工具面仍是 56 个；**新开的 agent/会话立刻是 91 个**（已用 subagent 实测）。
⇒ 你这边**新开一个对话**即可看到 32 个 `mcp__vivado__` 工具，不需要再重启。

### 10.6 收尾状态

- `cordis.patch.yml` 的 `command/args` 已从诊断包装器**恢复**为 `-m vivado_mcp`（下次重启生效；当前运行中的桥不受影响）；
- 包装器 `D:\vivado-mcp\mcp_probe_launch.py` 保留备用（透明代理，排障时把 args 指过去即可）；
- `compatibility.json` 建议长期保留，或在把 profile 内 `dsh-mcp-client` 升到 0.2.1-rc.2 后删除。
- 冒烟副产物提示：该机 `NoDefaultCurrentDirectoryInExePath` 策略会让 `launch_simulation`（spawn compile.bat）失败，与 MCP 无关；要跑 XSim 时先 `reg add "HKCU\Environment" /v NoDefaultCurrentDirectoryInExePath /d 0 /f` 并重开终端。
