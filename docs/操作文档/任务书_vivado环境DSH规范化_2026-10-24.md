# 任务书：Vivado 开发环境 DSH 规范化

> 交接自 2026-10-24 会话（vivado-mcp 核查）。执行：**DSH 创造模式**，产出 bundle patch。
> 背景与全部实测证据见 `结论_cross_vivado-mcp健康与使用核查_2026-10-24.md` §1–§10，本文只留决策所需。

## 目标

把 Vivado 开发环境收敛成三件套：**会话级预设（MCP + 纪律）** → **技能清单 + 门禁** → **文档单一事实源**。

## 已确认事实（勿再验证）

| 项 | 值 |
|---|---|
| 本机 / 官方基线 | Vivado **2023.1**（`xcku060-ffva1156-2-i`）/ AMD 技能与文档基线 **2026.1** → 冲突时以实测为准 |
| DSH | 运行时 **0.2.1-rc.2**；profile `~/.dsh/profiles/desktop`（Electron 独占，CLI 不可 dump，用副本） |
| vivado-mcp | 32 工具，现役 `D:\vivado-mcp`（**纯 ASCII**）；已挂载，工具名 `mcp__vivado__*` |
| 成本 | 32 个 MCP 工具定义 ≈ **8k tokens/请求**；9 个 skill 描述 ≈ 0.6k → **只做 MCP 会话化，不做 skill 作用域隔离** |
| 会话快照 | 工具目录按会话冻结；验证必须新开会话或派 subagent |

## 三个交付

### T1 Vivado 预设 `preset-vivado`（最高优先）

`@deepseek-ai/dsh-agent-preset` 一行：`id: vivado`，`plugins` = **精确复制 `preset-standard` 的 22 行**（从 `dsh --profile web --dump-config` 取，禁止手抄）+ Vivado 纪律版 persona（ASCII 路径 / 全局串行 / `cwd=D:\FPGA` / 结论须带证据 / 基线冲突以实测为准）+ `mcp-vivado` 行（照搬现 `cordis.patch.yml`，含 `toolCallTimeoutMs: 1800000`）。

**切之前必须实测三件事，任一不过就停手汇报：**

1. 预设内挂 `dsh-mcp-client` 能否过**激活审计**（import / 缺服务 / 服务全局泄漏任一命中即 reject 挂载）；
2. 该预设会话工具面 = **91**（59 内置 + 32 MCP），普通会话仍 56；
3. **`spawn_teammate` / `subagent` 是否继承预设作用域** —— 不继承则**放弃 preset、保持全局挂载**（用户主力是 Team 并行，砍掉队友工具是本末倒置）。

验证走隔离环境：复制 profile 到 `DSH_HOME=<临时目录>/profiles/<副本>` + junction `node_modules`，`DSH_HOME=… dsh --profile <副本> --no-open`，再派 subagent 枚举自己工具面。

### T2 技能清单 + 门禁（零风险，先做）

脚本从各 `SKILL.md` frontmatter 生成 `.dsh/skills/MANIFEST.json`（禁手写），字段含 `baseline: {amd_doc, tested_on}`。

接入 `D:\FPGA\scripts\ci_check.py` 五条校验：`name` == 目录名 · `version` 存在 · `references` 文件真实存在 · **描述/正文不得出现不存在的路径或工具名**（本次两个真实事故即此）· `baseline` 必填。

现状：6 份 SKILL.md 的路径与「已挂 32 工具」表述已修；**仍缺 baseline**（技能写 2026.1+，本机 2023.1）。

### T3 `agent.md` 收口（最后做，只加不改写）

顶部加场景**路由表**（场景 → 文件 / skill / 是否需 MCP）；「技能与文档现状」改成脚本生成的 `BEGIN:skills` 区块（源 = T2 的 MANIFEST）；镜像段挂 CI 门禁（vault ↔ `D:\FPGA\docs` diff 必须为空，现状已分叉）。**不动** `AGENTS.md` 与 `PITFALLS.md` 正文。

## 红线

- Vivado 全局串行：开工前 `tasklist | grep -i vivado` 为 0；同一时间只一个会话；非必要不跑综合/实现/仿真
- Vivado 相关 cwd / TEMP 必须纯 ASCII
- 改文件先备份 `*.bak-<日期>`；`D:\FPGA` **不 commit**；不改 `D:\vivado-mcp\site` 包源码；不删文件
- 结论须带 `文件:行号` 或命令输出；**MCP 返回 `is_error=false` 但文本含 `[ERROR]` 仍算失败**（坑 #69）
- 需重启宿主的改动，先给变更清单与回退方式再落地

## 省时坑（5 条）

1. 双击启动**看不到** MCP 报错（Electron 吞 stderr）→ 只能隔离 `DSH_HOME` 引导或终端启动
2. `dsh-hmr` 在 Electron 下不生效 → 改配置必须重启
3. profile 里的 `dsh-mcp-client@0.1.7-rc.2` 是传递依赖，**别删**；靠 `compatibility.json` 豁免
4. 机器上常驻的 `python -m vivado_mcp` 是 **ZCode** 的（已修），别当成 DSH 的
5. 工具不出现先查两件事：会话是否新建、兼容门禁是否把行 disable 了

## 可复用

`D:\vivado-mcp\tmp\verify_all.py`（判据已修，0 FAIL）· `tmp\mcp_probe_launch.py`（MCP spawn/stderr 探针）· `D:\FPGA\scripts\ci_check.py` · `AGENTS.md` §6a/§6b（现有地基）

## 验收

逐条 PASS/FAIL + 复现命令 + 关键输出；每处改动的备份路径与回退步骤；T1 若不采用须写清理由与现状。
