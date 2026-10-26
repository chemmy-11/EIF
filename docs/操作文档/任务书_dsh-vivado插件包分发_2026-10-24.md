# 任务书：Vivado 工作流 DSH 插件包（同门一键分发）

> 交接自 2026-10-24 会话（Vivado 预设实测 + DSH 插件契约取证）。执行：**DSH，正常模式，产出可分发的 bundle + 安装器**。
> 本文只留决策与已取证事实；上一轮规范化的过程证据见 `结论_cross_Vivado环境DSH规范化_2026-10-24.md` 与 repo `PITFALLS.md #69–#76`。

## 目标

把「Vivado 预设 + AMD 官方技能 + 文档检索 + 已打补丁的 vivado-mcp」打成一个 **DSH bundle 插件包**，让同门**一条命令 + 重启**即可获得与主机同等的开发环境。

分发形态已定：**DSH bundle（非独立 CLI、非 zip 手抄）**。public 版的授权与开源协议规范**留到后续**，本轮只做同门可用版，但 NOISE 信息（来源/许可）当场写清。

## 可行性结论：**高（官方一等公民）**

三条硬依据（全部来自 app.asar 内第一方源码/文档，已实测解析）：

1. **配置型 bundle 是官方支持的形态**。`@deepseek-ai/dsh-agent-preset/skills/cordis-plugin-development/references/mcp-bundle.md` 原文：
   > "A configuration-only bundle's manifest needs a unique name, version, and `dsh.bundle.patch`, but no Host/Client entry files. Its patch … inserts the already installed `@deepseek-ai/dsh-mcp-client` with `serverName`, `transport`, …" / "**install the bundle through `plugin_manager`**"
   我们现役 `<vault>\.dsh\bundles\vivado-preset\` 就是这个形态的活例子（`package.json` 只有 `name/version/private/type/description/dsh.bundle.patch`）。
2. **包可以随包出货 `skills/` 并通过 `skill-filesystem` 挂载**。`@deepseek-ai/dsh-agent-preset/README.zh.md`：
   > "本包还随包出货创造模式通过 `skill-filesystem` 挂载的 `skills/` 目录"
   ⇒ 不必往同门的 `~/.dsh/skills` 写文件。
3. **技能根可配置**。`@deepseek-ai/dsh-skill-filesystem/README.zh.md` 根表：

   | Rank | 来源 | 路径 |
   |---|---|---|
   | 100 | `project-dsh` | `<projectRoot>/.dsh/skills` |
   | 200 | `project-agents` | `<projectRoot>/.agents/skills` |
   | 300 | `custom` | **`Config.customSkillDirs`** |
   | 400 | `user-dsh` | `<dshHome>/skills` |
   | 500 | `user-agents` | `<agentsHome>/skills` |
   | 600 | `bundled` | **`Config.bundledSkillDir`**（随包提供的根） |

   另有 `includeDefaultRoots`（false 时只留自身配置的根）与 `providerName`（默认 `filesystem`）。
   ⇒ 插件用 **rank 300 `customSkillDirs`** 显式挂自己的技能目录最稳，不会与项目的 rank 100/200 抢。

**结论**：技术上无阻断项；工作量集中在「参数化 + 补丁入版本库 + 安装器」。

## 已确认事实（勿再验证）

| 项 | 值 | 证据 |
|---|---|---|
| DSH | 0.2.1-rc.2，profile `~/.dsh/profiles/desktop`；Electron 独占，`dsh-hmr` **不生效** | 多次重启实证 |
| bundle 契约 | `package.json` 需 `name`/`version`/`dsh.bundle.patch`；patch 用 `- insert:` 行 | `<vault>\.dsh\bundles\vivado-preset\package.json` + `@linxin666/dsh-win-bash`（含 `dsh.engines: {dsh: ">=0.2.1-rc.2"}`） |
| 预设现役形态 | `preset-vivado` 一行（`@deepseek-ai/dsh-agent-preset`，`config.id: vivado`）+ 23 个 plugin 行（22 拷自 standard + `mcp-vivado`） | `<vault>\.dsh\bundles\vivado-preset\cordis.patch.yml` |
| 工具面实测 | 普通预设会话 **91**（59 内置 + 32 MCP）；Team 会话 97 | subagent / teammate 实测（2026-10-24） |
| 继承 | `spawn_teammate` 与 `subagent` **都继承**预设作用域（32 工具 + persona 原文一致） | 本轮实测 |
| AMD 6 技能 | 源 `vivado-ai-extension-2026.9.1.vsix` 内 `resources/plugin-bundled/skills/`，**MIT**（与 GitHub `Xilinx/ross-ai-assistant` 同源）；已装 `<vault>\.dsh\skills\`；安装脚本 `归档\.ross-recon\install_skills.py`（幂等，DST 指向项目级） | `归档\.ross-recon\安装记录.md` |
| AMD 技能基线 | 官方声明 **2026.1**；本机 2023.1；MANIFEST 里 6/7 为 `unverified`，仅 `vivado-rtl-elaboration-analysis` 有 2023.1 实证 | `<vault>\.dsh\skills\MANIFEST.json` |
| 现役 MCP | 第三方 vivado-mcp（32 工具），安装 `D:\vivado-mcp`（**不是我们的资产**）；本轮打了 3 个补丁（`max_lines`/`save_full_to`、`xdc_lint` 聚合+默认全量、`safe_tcl` 提示），**均未入版本库** | `D:\vivado-mcp\site\...\*.bak-mcp-20261024b` |
| asar 可自证 | 脚本 `D:\FPGA\.tmp\asar_get*.py` 可解析 `D:\dsh\resources\app.asar`（18309 文件，含全部第一方包 README/源码）⇒ 任何 DSH 契约疑问自行取证，不必猜 | 本轮实测（注意 `offset` 是字符串，需 `int()`） |
| 现有门禁 | `D:\FPGA\scripts\ci_check.py`：技能清单逐字节校验（`--check`）、SKILL.md 裸文件名必须存在（`artifacts:` 例外）、镜像门禁 8 条白名单 | repo commit `3ce44b8`/`fca7e3a`/`db579fc` |

## 开工前必须确认的 3 件事（各 ≤10 分钟）

1. **`plugin_manager` 在默认会话是否可用**：本预设里 `tool-plugin-manager` 是 `disabled: true`；安装动作必须走**默认会话**（或 `pnpm` 手改 profile 后重启）。确认后再定安装器形态。
2. **bundle 里 `skill-filesystem` 行的写法**：是"新增一行带 `customSkillDirs`"还是"覆盖已有行"。官方推荐路径 = 用 `plugin_manager` 装好后 `Config.listConfigs` 看实际 schema（勿手猜）。
3. **同门环境画像**：同一块 KU060？同一 Vivado 版本？不同则 persona 里的 `xcku060-ffva1156-2-i`、`Tcl 8.5.14`、`-noprogress 不存在` 必须**版本/器件分档**，不能写死。

## 四个交付

### T1 包骨架 + 配置层（最高优先）

- 目录（建议 `<repo>/dist/dsh-vivado-kit/`，或独立 repo；**不要**放在 vault 根）：
  ```
  package.json          # name/version/dsh.bundle.patch（+ 可选 dsh.engines）
  cordis.patch.yml      # - insert: preset-vivado 行 + skill-filesystem 行 + mcp-vivado 行
  skills/               # 随包技能（见 T2）
  config.example.yml    # 器件/路径/版本，由安装器写实际值
  install.ps1           # 一键：检查 → 装 bundle → 写 profile → 提示重启
  doctor.ps1            # 体检（见 T3）
  NOTICE / LICENSE / README.md
  ```
- **参数化**（替换现役预设里写死的值）：`part`、`project_root`、`vivado_path`、`vivado_version`、`temp_dir`（必须 ASCII）、`python`。
- persona 保留工程纪律（全局串行 / ASCII 路径 / 证据须带 `file:line` / `is_error=false` 但含 `[ERROR]` 仍算失败 #69 / 无损默认 #76），**版本相关真值改为按 `vivado_version` 分档注入**。

### T2 技能与知识库索引

- 挂载方式：优先 **rank 300 `customSkillDirs`** 指向 bundle 内 `skills/`；备选 `bundledSkillDir`(600)。**不要**写进同门的 `~/.dsh/skills`。
- 内容分两层：
  1. **AMD 官方 6 件**（MIT，随包 + `NOTICE` 记来源/版本/修改点）；
  2. **我们自己的纪律 skill**：从 `PITFALLS.md #69–#76` 抽通用条 + 工作流（先读工程 → `xdc_lint` → 复用既有综合结果 → 必要时才综合/实现），版本分档写清。
- 每个 skill 的 `baseline` 必须如实（`tested_on`/`status`/`evidence`），沿用现有 `gen_skills_manifest.py` 与 `--check` 门禁。
- 文档检索两条通路都要交代：
  - `amd-doc-search`（项目级 CLI 桥，`doc_search.py`）——**query 会外发 AMD**，NDA 项目要写明；
  - hosted `mcp-amd-doc-search`（web profile 已有配置样例）——作为可选件，让用户用自己的 entitlement。

### T3 安装器 + doctor

- `install.ps1`：幂等、可卸载；只改 profile（先备份 `*.bak-<日期>`）、不碰 `~/.dsh/skills`；结束时**明确提示「必须重启宿主」**（Electron 下 HMR 不生效）。
- `doctor.ps1` 至少检：Vivado 是否存在/版本、`vivado.bat` 路径、Python 与 `PYTHONUTF8`、part 是否在器件库、**cwd/TEMP/TMP 是否纯 ASCII**、`D:\vivado-mcp\site` 是否可 import、`mcp_ctl.py list` 是否 32 工具、license 是否可用。任一 FAIL 给一句可执行修法。

### T4 版本分档与授权说明

- 版本真值分档表（至少 2023.1 / 2025.2+ 两档）：Tcl 版本、`open_project -noprogress` 是否存在、`report_*` 参数差异、ILA `C_DATA_DEPTH` 最小合法值（#67：2023.1 是 1024）。
- `NOTICE`：AMD 技能来源 + MIT + 我们的改动清单；vivado-mcp 来自第三方（写明仓库/版本 + 我们的补丁清单）。
- public 版再补 SPDX/许可兼容性审查（本轮不做）。

## 红线

- **不打包 Vivado 本体与其许可证**；不代签任何 AMD 协议。
- **不改第三方源码当私有分支**：3 个 MCP 补丁要么**上游 PR**，要么以 patch 文件形式随包并在 `doctor` 里报「版本/补丁是否就位」。
- 安装器**只动自己的 bundle 与 profile 的 bundle 列表**，不覆盖用户已有的 plugin 行；改 profile 前先备份，且给出逐行回退命令。
- **必须重启宿主**才生效——不许在文档里假装热更新。
- 结论 / 文档一律带证据（`file:line` 或命令原文）；不要把「本机实测」写成「官方保证」。

## 省时坑（本轮已验证过的）

1. **`dsh-hmr` 在 Electron 下不生效** → 改配置必重启；「一键」= 一条命令 + 重启。
2. **预设会话里 `plugin-manager` 被 disabled** → 安装必须在默认会话做，否则工具不存在。
3. **`projectRoot` = 最近含 `.git` 的祖先**（无 `.git` 用 cwd）→ 别指望 rank 100 命中你的技能目录，用 rank 300 显式挂。
4. **`profile` 是 Electron 独占，CLI 不能 `--dump-config`** → 验证要走隔离副本：`DSH_HOME=<临时目录>/profiles/<副本>` + junction `node_modules`。
5. **`asar` 解析**：`offset` 在 JSON 里是字符串，必须 `int()`；数据区起点 = `8 + header_size`。
6. **`pwsh` 在预设会话不可用**（patch 层 `replacePwsh` 实测无效，已回退，坑 #71）→ 安装器用 `powershell.exe`（5.1）写，别依赖 `pwsh`。
7. **AMD 技能是 2026.1 基线** → 分发时 `baseline` 必须标 `unverified`，否则等于虚假陈述。
8. **`amd-doc-search` 外发 query** → NDA 项目要么禁用、要么走本地 KB。

## 可复用

| 资产 | 位置 |
|---|---|
| 现役预设 bundle（可直接改造成分发版） | `<vault>\.dsh\bundles\vivado-preset\` |
| AMD 技能安装器（幂等） | `<vault>\归档\.ross-recon\install_skills.py` |
| asar 解析探针 | `<vault>\归档\.ross-recon\asar_probe.py`（解析 `D:\dsh\resources\app.asar`，可抽任意第一方包 README/源码） |
| MCP 健康检查 | `D:\vivado-mcp\tmp\verify_all.py`、`mcp_probe_launch.py` |
| 技能清单/镜像门禁 | `D:\FPGA\scripts\ci_check.py`、`gen_skills_manifest.py` |
| DSH 第一方 bundle 开发指南 | asar 内 `@deepseek-ai/dsh-agent-preset/skills/cordis-plugin-development/`（`SKILL.md` + `references/mcp-bundle.md` + `templates/`） |

## 验收

1. **隔离安装**：在 `DSH_HOME=<临时目录>` 副本 profile 里跑 `install.ps1`，新开会话验证：
   - 工具面 **91**（59 + 32），persona 原文含新纪律；
   - 技能可见：AMD 6 件 + 自研纪律 skill，且 `baseline` 如实；
   - `start_session` 可用、`xdc_lint` **默认全量**（25 引脚样例给 25 条）、`get_cdc_report` 默认全量。
2. **陌生人视角**：路径全部改成本机之外的值仍能装（至少 `part` 与 `project_root` 各换一次）。
3. **可卸载**：删 bundle + 还原 profile 备份后，无残留目录、无残留技能。
4. **doctor**：故意造 3 个坏条件（TEMP 含中文 / Vivado 路径错 / MCP 路径错），每条都要被抓到并给出修法。

## 交付纪律

- 每步带 `file:line` 或命令原文；改动前备份 `*.bak-<日期>`；`D:\FPGA` 与 dist 目录的提交分开记，别混进既有 commit。
- 先做 T1 + T3 的最小闭环（能装、能体检、能跑 `start_session`），再补 T2 技能内容与 T4 文档。
