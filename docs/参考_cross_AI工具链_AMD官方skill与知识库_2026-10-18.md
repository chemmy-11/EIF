# AMD 官方 AI 技能与文档检索 — 本工程接入与使用参考

> 2026-10-18 建立。适用对象：在本仓库 / 文档目录工作的任何 Agent 与会话。
> 定位：**知识与流程层**的接入说明与调用参考；执行层仍是 `vivado-mcp`（32 工具）+ xsct + 自研脚本，不因本接入而改变。
> 规范约束以 `D:\FPGA\AGENTS.md` 为准（§6b 为本章的权威摘要，冲突时以 AGENTS.md 为准）。

## 1. 资产与作用域

| 资产 | 位置 | 作用域 | 状态 |
|---|---|---|---|
| 项目级 AI 技能（7 个） | `%USERPROFILE%\Desktop\毕设\.dsh\skills\` | **仅本工作区**（DSH 技能根 rank 100：`<projectRoot>/.dsh/skills`） | 已生效（`watch: true` 热加载，无需重启） |
| 官方文档检索（原生 MCP） | `%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml` 的 `mcp-amd-doc-search` 条目 | DSH **web profile 全局**（所有工作区） | 已配置，**重启 `dsh web` 后生效**；工具名 `mcp__amd_doc_search__vivado_doc_search` |
| 官方文档检索（项目桥） | `%USERPROFILE%\Desktop\毕设\.dsh\skills\amd-doc-search\doc_search.py` | **仅本工作区** | 已生效，无需重启 |
| 检索服务 | `https://ross.amd.com/mcp/doc-search` | AMD 托管、免 key、英文 | 实测可用（2026-10-18，服务版本 `AMD Doc Search 0.11.6`） |

**为什么项目级**：`~/.agents/skills` 是 DSH 的 user-agents 全局根（rank 500），装进去会让**所有工作区**的会话都加载这些技能描述；Vivado 技能只对本项目有意义，故放项目级 `.dsh/skills`（2026-10-18 用户定案，见坑账本 #63）。

**全局技能根现状**：`~/.agents/skills` 保留跨项目通用技能（markitdown / obsidian 等），**不含任何 Vivado / hw-* 技能**。

## 2. 调用形式

### 2.1 原生 MCP 工具（重启后）

模型在一次对话中发起 tool call，参数：

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `query` | string 必填 | — | 自然语言或精确命令名 |
| `limit` | int | 10 | 返回文档块数（1–50） |
| `alpha` | number | 0.8 | 0 = 关键词检索，1 = 语义；查精确 Tcl 命令时降到 0.3–0.5 |
| `family` | string[] | — | 器件系列（含 `Kintex UltraScale+`）；**提示性过滤** |
| `version` | string[] | — | 文档版本（含 `2023.1`）；**提示性过滤** |
| `tool` | string[] | — | `Vivado Design Suite` / `Vitis` / … |

返回：带 `DOC #` / `title` / `url`（`docs.amd.com` 或 `adaptivesupport.amd.com`）/ `version` 的文本块。

### 2.2 项目桥（当前可用，无需重启）

```powershell
$py = "%USERPROFILE%\AppData\Local\Python\pythoncore-3.14-64\python.exe"
$s  = "%USERPROFILE%\Desktop\毕设\.dsh\skills\amd-doc-search\doc_search.py"

& $py $s "incremental implementation compile UG904" --limit 3
& $py $s "ILA trigger setup" --family "Kintex UltraScale+" --limit 5
& $py $s "report_methodology" --version 2023.1 --alpha 0.5 --json
```

- 脚本内部走同一 MCP 协议（`initialize` → `tools/call`），与原生工具返回一致。
- 退出码：0 成功 / 1 协议或网络错误 / 2 服务端 `isError`。
- 单次约 3–4 s（公网）；不要高频连发。

## 3. 触发规则

**何时用**：需要 AMD/Xilinx 官方依据的问题——Vivado Tcl 命令/属性、UG901/UG903/UG906/UG949、时序/CDC/AXI/Aurora/MIG/DDR4、ILA/VIO、Answer Record 已知问题。

**何时不用**：
- 查正点原子板卡手册/例程、本项目调试记录/坑账本 → 直接读 `D:\FPGA\docs` 与 AGENTS.md；
- 涉密或未公开设计细节 → hosted 检索会把 query 发往 AMD；
- 需要完全离线 → 需 AMD entitlement 的本地 KB（当前不投入）。

**触发方式**：不是自动注入，是 Agent 的按需工具调用。提高触发率的三个做法：① 技能/规范里写清"何时用"（本工程已写入 AGENTS.md §6b 与技能描述）；② 用户显式要求（"用官方文档查 X"）；③ 系统提示强制项（小模型常不主动调工具）。

**引用纪律**：结论必须带来源 URL；检索不到写"未检索到"，禁止臆造；`family`/`version` 逐条核对（坑 #64）。

## 4. 技能盘点与 2023.1 适配

| 技能 | 主要用途 | 判定 | 2023.1 适配要点 |
|---|---|---|---|
| `vivado-rtl-elaboration-analysis` | 综合 elaboration 日志分析 + 560 个 `[Synth 8-XXX]` 修复卡 | A（纯知识可直接用） | 无版本依赖；MCP 模式映射 `run_tcl` |
| `vivado-rtl-lint` | `synth_design -lint` + 20 个规则修复模板 | B（约 0.5 天） | 2023.1 走 `.rpt` + 自带 parser（官方已覆盖 <2026.1 分支） |
| `vivado-revision-control` | 工程导出/交接/重建（208 KB helper Tcl） | B（约 0.5–1 天） | 官方声明兼容 2023.2+，本工程 2023.1 需实测 |
| `vivado-simulate-rtl` | XSim 排错签名/覆盖率/波形/SAIF | B（约 0.5–1 天） | 只取 XSim 相关；第三方仿真器段不适用 |
| `hw-ila-debug` / `hw-vio-debug` | 上板 ILA/VIO 操作手册 + 属性表 | B（约 0.5–1 天） | HW Manager Tcl 2023.1 大多可用；TSM 高级触发待实测 |
| `amd-doc-search` | 官方文档检索桥 | A | 无版本依赖 |

**不安装**：`vivado-timing-methodology-checks`（声明 2026.1+、2023.1 检查集不全）、`vivado-ip-configurator`（依赖 2026.1 原生 API 与会话日志绑定）——需要时只取 `references/` 当知识。

## 5. 实测记录（2026-10-18）

- 文档检索：3 次查询全部命中（UG904 增量实现、ILA 触发、`report_methodology`），单次 2.9–4.2 s；服务版本 `AMD Doc Search 0.11.6`；返回 URL 形如 `https://docs.amd.com/r/2023.1-English/ug904-vivado-implementation/...`。
- 技能冒烟：`prj11\out\r2j_synth.log` **只读副本** → `parse_elab_messages.py` 解析 **452 条**（WARNING 268 / INFO 184），与日志正则计数 452 **差 0**；Top ID `8-6014`(100)、`8-7129`(100)、`8-6157`(75)。
- 发现并修复跨盘 bug（坑 #62）：首次运行因 `os.path.relpath` 跨盘 `ValueError` 在 3 行处崩溃，打补丁后 452/452。
- 对 prj11 构建零影响：测试只读日志 + C: 侧脚本，未启动/终止任何 Vivado 或 MCP 会话；期间构建轮次切换由另一 DSH 会话按其任务主动收尾。

## 6. 2023.1 待实测清单（按优先级）

1. `synth_design -lint -file` 在 2023.1 的输出格式（`.rpt` ASCII 表）→ `parse_lint_report.py` 覆盖率（用最小工程验证）。
2. `report_methodology -json` 是否支持；不支持改用 `write_json_report.tcl` 的 `get_methodology_violations + list_property` fallback。
3. `detect_project_flow` / `export_all_sources` / `generate_build_script`（revision-control）在 2023.1 的可用性；`write_bd_tcl`/`write_ip_tcl` 参数差异。
4. `get_hw_ilas` / `CONTROL.TSM_FILE` / `STATIC.*`（hw-ila）在 2023.1 的属性集；Vivado 与 hw_server 版本一致。
5. `exec python3` 在 Vivado Tcl 中命中 WindowsApps 别名 → 一律改用 host python 全路径。
6. 官方 skill 的 `allowed-tools` 只是提示，不被任何客户端强制；权限仍由本工程审批/沙箱决定。

## 7. 排障

| 现象 | 处理 |
|---|---|
| 文档检索超时 / HTTP 4xx | 重试一次；仍失败改用 `web_fetch` 直读 `https://docs.amd.com` 对应 UG 页面 |
| 桥脚本 401/403 | 不应发生（服务免 key）；检查代理/防火墙是否拦 `ross.amd.com` |
| 技能改了不生效 | DSH 技能根 `watch: true` 应热加载；若未生效，确认文件在 `.dsh/skills/<name>/SKILL.md` 且目录名 = frontmatter `name` |
| 重启后原生工具未出现 | 检查 `~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-amd-doc-search` 条目与 DSH 启动日志；工具名固定 `mcp__amd_doc_search__vivado_doc_search` |
| 解析脚本崩 `ValueError: path is on mount` | 坑 #62：加 `try/except` 或用同盘输出 |

## 8. 回滚

```powershell
# 移除项目级技能（仅本项目）
Remove-Item -Recurse -Force "$env:USERPROFILE\Desktop\毕设\.dsh\skills\amd-doc-search"
# 移除原生 MCP 配置：编辑 cordis.patch.yml 删除 mcp-amd-doc-search 的 insert 段，
# 或用备份 cordis.patch.yml.bak-before-amd-doc-search-* 还原
```

## 9. 参考

- 官方仓库：<https://github.com/Xilinx/ross-ai-assistant>（MIT；技能包 = `skills/` 目录，Agent Skills 标准）
- 安装包：`vivado-ai-extension-2026.9.1.vsix`（内含 Vivado MCP server 二进制 + 50 个技能 + `amd-doc-search` 注册；**本项目未安装该扩展**）
- 对照结论：官方 Vivado MCP（14 工具）与本工程第三方 `vivado-mcp`（32 工具）**不混用**——后者覆盖结构化报告/离线解析/流程/波形，是执行层；官方工具名由技能注记映射（评估与兼容矩阵见会话报告，2026-10-18）。
