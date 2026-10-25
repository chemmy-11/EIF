# 结论_cross_dsh-vivado 插件包分发（同门一键版）· 2026-10-24

> 执行：DSH Team（lead + `ps-skills` / `ps-docs` / `ps-installer` / `ps-doctor`），2026-10-24 16:15–17:0x（Asia/Shanghai）
> 需求来源：`任务书_dsh-vivado插件包分发_2026-10-24.md`；前序证据：`结论_cross_Vivado环境DSH规范化_2026-10-24.md`（预设三门禁已过）
> 交付形态：**已开源：`https://github.com/chemmy-11/dsh-vivado`（public，main @ `7ea435e`）**，本地工作副本 `D:\dsh-vivado\`
> 本地已装：**live desktop profile 已从旧手工 bundle 迁到本包并在真实会话中验证通过**（32 MCP / 98 总工具 / 新 persona / 自研技能可见），重启后更彻底
> 许可：自有内容 **MIT**（© 2026 chemmy-11）；第三方 carve-out 见 `NOTICE` §3.0；GitHub 已识别 `spdx_id=MIT`
> 徽章：powered-by-dsh 官方徽章 + Vivado 2023.1 tested + 2025.2+ unverified + MCP 32 + platform + MIT（README 顶部，6 个均 HTTP 200 实测）
> 包名：**`dsh-vivado`**（聚合包 = 会话预设 + MCP 工具 + 技能，不是「preset 包」；后续可继续加工具/技能）
> 规模：673 文件 / 1.84 MB（其中随包技能 645 文件 / 1.43 MB）；`D:\FPGA\dist\` 已撤除，EIF 仓库工作树干净
> 纪律：未打包 Vivado 本体/许可证；未改 `D:\vivado-mcp\site`；未在用 desktop profile 上安装（全部验收在隔离 `DSH_HOME`）；`D:\FPGA` 未 commit（提交命令见 §8）；未删任何项目文件。
> **2026-10-25 追加**：kit 升 **0.1.1** —— 按《实战问题与改进》落地 P0×3/技能×2/CI×1，并**解除对第三方 shell（`win_bash`）的依赖**；详见 §4.9，提交 `7ea435e`。

---

## 0. 一句话结论

| 交付 | 结论 | 一句话证据 |
|---|---|---|
| **T1 聚合包骨架 + 配置层** | ✅ 完成 | 渲染后 `cordis.patch.yml`：1 个 `- insert:` → `preset-vivado` 含 **22 条 shipped 行 + mcp-vivado**（v1 校验器 23 行全对）；两档 persona 各 ~4.1 KB |
| **T2 技能与知识库索引** | ✅ 完成 | 随包 **8 技能 / 645 文件**；`gen_skills_manifest.py --check` PASS；技能经 rank 300 `customSkillDirs` 挂载（dump-config 可验） |
| **T3 安装器 + doctor** | ✅ 完成 | `install.ps1`（687 行）/`uninstall.ps1`（382 行）/`doctor.ps1`（13 检查）；**Lead 独立验收 49/49 断言通过** |
| **T4 版本分档与授权** | ✅ 完成 | 两档 persona + `docs/version-matrix.md`（2023.1 全实测 / 2025.2+ 全未实测）；`NOTICE` 分 4 类来源；**4 个 MCP 补丁**对 pip-pristine 基线 4/4 可应用且逐字节还原 |
| **许可审查（追加轮）** | ✅ 完成 | 三个上游全部允许分发：AMD 技能 **MIT**、DSH 22 行 **MIT**（原以为「无主」）、vivado-mcp **Apache-2.0**；义务已逐条履行（`docs/licensing.md`） |
| **开源发布（追加轮）** | ✅ 完成 | 仓库转 **public** + 自有内容切 **MIT**（GitHub 识别 MIT）+ 徽章 6 个 + 技能注记脱敏；**匿名 HTTPS clone** 后可装、验收 49/49 |
| **中英双版 + 面向用户** | ✅ 完成 | `README.md`（中）/ `README.en.md`（英）互链；深层内容拆到 `docs/architecture.md`（160 行）与 `docs/troubleshooting.md`（159 行）；README 不再写给 agent 的施工说明 |
| **图标 + 显示元数据（追加轮）** | ✅ 完成 | `icon.png`（Vivado 标志按 dsh 配色重上色，512²，51 KB）+ `locale/{en,zh}.json` + `package.json` 顶层 `icon`；48/24 px 预渲染可辨认；**不属 MIT**（Vivado 标志归 AMD，仅作指称），已进 `NOTICE` §3.0 |
| **本地插件更新** | ✅ 完成 | 旧 `@local/dsh-vivado-preset` 已移除 → `dsh-vivado` 已装进 live desktop；真实会话实测 `MCP_COUNT=32 / TOTAL_TOOLS=98 / PERSONA_VERSION_TIER=YES / SKILL_WORKFLOW_DISCIPLINE=YES`（**未重启即已生效**） |

> 唯一需要用户做的事：**把 kit 装到自己的 profile 后重启宿主**（Electron 下 `dsh-hmr` 不生效）。真实会话口径实测：Vivado 预设会话 **97 工具 = 65 非 MCP + 32 MCP**，persona 含 `Vivado is GLOBALLY SERIAL`（§3.4，探针会话原文）。

---

## 1. 交付物清单（仓库 `chemmy-11/dsh-vivado`，本地 `D:\dsh-vivado\`）

| 路径 | 字节 | 作用 |
|---|---:|---|
| `package.json` | 517 | bundle 清单：`@local/dsh-vivado` 0.1.0，`dsh.bundle.patch` + `dsh.engines.dsh>=0.2.1-rc.2` |
| `cordis.patch.yml` | 渲染产物（gitignore） | 预设 patch；**由模板渲染，不手写**，不随仓库提交 |
| `config.example.yml` | 1266 | 8 键扁平配置（part / 路径 / 版本），安装器按探测结果写实际值 |
| `install.ps1` | 34900 | 一键安装（cli / manual / WhatIf / RenderOnly；幂等） |
| `uninstall.ps1` | 19196 | 卸载（restore-backup 或 surgical 两条分支；幂等） |
| `doctor.ps1` | 64933 | 13 项体检，`-Json` 机器可读；exit 0=无 FAIL |
| `lib/common.ps1` | 9186 | Lead 写的公共函数（config 解析 / DSH 定位 / 备份 / ASCII 判定） |
| `lib/install-helpers.ps1` | 43518 | 安装器私有 helper（staging 白名单、pnpm/CLI 调用、verify 四判据） |
| `lib/doctor-helpers.ps1` | 12629 | doctor 私有 helper（带超时的外部命令等） |
| `tools/render_patch.ps1` | 7686 | 渲染器：config + 模板 + persona 片段 → `cordis.patch.yml`（字面替换，自检残留占位符） |
| `tools/make_template.py` | 16849 | 模板生成器：从已实证 bundle 原样抽 22 行 + 断言（`--check` 自洽校验，无需源文件） |
| `tools/gen_skills_manifest.py` | 26760 | 技能清单生成/门禁（`--check` 逐字节） |
| `templates/preset.patch.yml.tmpl` | 9857 | 唯一模板（9 个占位符） |
| `templates/shipped-standard-22rows.yml` | 7378 | 溯源审计件（21 行逐字节 + persona 行以注释替代 + 原始 sha256 记录） |
| `templates/persona/{2023.1,2025.2plus}.frag.yml` | 4504 / 4561 | 版本分档 persona（整条 persona 行，10/12/12/14/16 缩进） |
| `skills/**` | 1 429 652 | 8 技能：AMD 6 件（MIT）+ `amd-doc-search` + `vivado-workflow-discipline`；含 `MANIFEST.json`、`NOTICE-skills.md` |
| `patches/vivado-mcp/` | 37 669 | 4 个 `.patch` + README（pristine 基线对照、应用/反查/升级流程、Apache-2.0 §4(b) 与 PR 优先） |
| `NOTICE` / `LICENSE` | 14632 / 4360 | 4 类来源与许可（AMD MIT / vivado-mcp Apache-2.0 / DSH 配置数据 / 自研）；自研部分「同门内部使用」+ public SPDX 留白 |
| `README.md` | 21454 | 陌生人视角：前置条件 → 一键装 → 必须重启 → 用法 → doctor → 卸载回退 → 排错（#69/#70/#72/#74/#75/#76） |
| `docs/install.md` | 19888 | 安装/卸载/回退详解 + A–H 实测矩阵 |
| `docs/doctor-checks.md` | 24453 | 13 项检查的判据、命令、阈值、修法、为什么有的只 WARN |
| `docs/version-matrix.md` | 16451 | 版本真值分档（实测 / 文档未实测 / 历史记录三档标记）+ 新机重探 checklist |
| `KIT-SPEC.md` | 9851 | 内部施工契约（**不进 staging**，`install-helpers.ps1:798` 排除清单） |

---

## 2. 关键契约（全部取证，不是猜）

| # | 事实 | 证据 |
|---|---|---|
| 2.1 | 配置型 bundle 合法：`package.json` 只需 `name`/`version`/`dsh.bundle.patch` | asar 内 `dsh-agent-preset/skills/cordis-plugin-development/references/mcp-bundle.md:3` |
| 2.2 | 技能根 rank 300 = `Config.customSkillDirs`（`includeDefaultRoots` 默认 true，`bundledSkillDir` 是 600） | asar 内 `dsh-skill-filesystem/README.md`「Roots and priority」+ `lib/index.js:31-42` 的 zod schema |
| 2.3 | **官方安装通路**：`dsh plugin --profile <p> add "link:<dir>"` = pnpm + reconcile（自动写 `dependencies` 与 `dsh.profile.bundles`） | `dsh plugin --help` 原文；实测装出 `+ @local/dsh-vivado 0.1.0`，随后 `--dump-config` 出现 `# == @local/dsh-vivado` |
| 2.4 | **卸载通路**：`dsh plugin ... remove <pkg>` 能清依赖与 bundle 名，但**残留 junction** | 实测：remove 后 `package.json` 无 `dsh-vivado`、dump 里 `preset-vivado` 0 次，但 `node_modules\@local\dsh-vivado` 仍是 `<JUNCTION>` → 卸载脚本必须显式 `[System.IO.Directory]::Delete($link,$false)` |
| 2.5 | **compatibility.json 的豁免值必须是运行时版本串**（`0.2.1-rc.2`），不是 exe `ProductVersion`（`0.2.1.0`） | `dsh.cmd --version` → `0.2.1-rc.2`；`(Get-Item 'DeepSeek Harness.exe').VersionInfo.ProductVersion` → `0.2.1.0`（FileVersion 才是 rc 串）；live 豁免键 `{"@deepseek-ai/dsh-mcp-client@0.1.7-rc.2": ["0.2.1-rc.2"]}` |
| 2.6 | **`--dump-config` 不校验 compatibility.json**（`{}` / 非法 JSON / 缺文件三种情况 dump 逐字节相同）⇒ 安装器的 dump 判据证明不了豁免，只能由 doctor check 12 直接读文件 | ps-installer 实测（报告 §4）；这解释了为什么要专门一项检查 |
| 2.7 | `vivado-mcp` = **Apache-2.0 0.3.26**（不是 MIT），上游 `github.com/mapleleavessssss-wq/vivado-mcp` | `vivado_mcp-0.3.26.dist-info/METADATA`：`License-Expression: Apache-2.0` / `Requires-Python: >=3.10` / `Project-URL` |
| 2.8 | 本地对 `vivado-mcp` 的改动是 **4 个文件**，基线可由 pip `RECORD`（base64url sha256）证明 | 见 §3.5：4 个 `.bak` 的 sha256 与 `RECORD` 逐一对齐 |
| 2.9 | `dsh` PATH 上的 CLI 可能是旧版（0.1.7-rc.2）而宿主是 0.2.1-rc.2 ⇒ 必须用 `<安装>\resources\runtime\cli\bin\dsh.cmd` | 前序结论 §2.2 + 安装器 `Find-DshCli` 的搜索顺序（进程路径/注册表/常见根，最后才考虑 PATH 之外的 fallback） |

---

## 3. 验收（每条都真跑过，命令与输出可复现）

### 3.1 Lead 独立验收：**49/49 断言通过**

> 2026-10-25 追加：矩阵已扩到 **50 条**（静态组新增"启动件在场且纯 ASCII"），最新结果见 §4.9。

脚本 `D:\FPGA\.tmp\kit-recon-2026-10-24\accept_all.py`（不复用队友测试，直接驱动交付件，探针 `DSH_HOME=C:\Users\***\dshprobe-accept`）。
**两轮都跑**：① 仓库工作副本；② **从 GitHub 全新 clone 出来的副本**（`--kit <clone>`）——两轮均 49/49，证明「推上去的东西」本身可装可用：

```
== static: template / renderer / skills / hygiene ==     8/8
== install (cli mode) + composition ==                  16/16
== uninstall (clean removal) ==                          7/7
== manual mode (no pnpm) ==                              4/4
== stranger perspective (part + project_root 各换一次) == 7/7
== doctor: clean run + 3 injected failures ==            5/5
=== ACCEPTANCE: 49/49 passed ===
```

其中关键行（原文）：

```
[PASS] dependency recorded as link: -- link:C:/Users/***/dshprobe-accept/bundles/dsh-vivado
[PASS] dump-config: customSkillDirs -> staged skills -- C:/Users/.../bundles/dsh-vivado/skills
[PASS] second install did not change package.json -- 50f2baabff72 vs 50f2baabff72
[PASS] -WhatIf exit 0 and changes nothing
[PASS] ~/.dsh/skills untouched by the installer -- before=['.secrets'] after=['.secrets']
[PASS] node_modules link removed
[PASS] dump-config: preset-vivado gone
[PASS] manual: preset composes
[PASS] stranger: persona carries the new part / new project root
[PASS] re-config: staged patch re-rendered with the new config -- xcku060=True xc7a35=False
[PASS] doctor exit 0 on a healthy machine -- FAIL=[] WARN=['license']
[PASS] doctor catches broken {ascii-paths,vivado-install,mcp-import}  (三条都 exit=1 且给出修法)
[PASS] doctor -Json is valid JSON with the 5 fields -- 13 checks
```

doctor 两套口供（ps-doctor 实跑，`reports/ps-doctor.md`）：

| 场景 | 结果 | 说明 |
|---|---|---|
| **裸 profile**（默认参数） | **9 PASS / 4 WARN / 0 FAIL，exit 0，4.2 s** | WARN = `license` + 3×「kit 还没装」；裸环境不该红 |
| **已装探针**（`-DshHome <tmp> -Profile probe`） | **12 PASS / 1 WARN / 0 FAIL，exit 0** | 唯一 WARN 仍是 `license`（本机无 `XILINXD_LICENSE_FILE`、`~/.Xilinx` 下无 `*.lic`） |
| `-Quick` | 1.2–1.7 s，跳过的项报 `WARN skipped by -Quick (would run: …)` | 跳项不冒充 PASS |

> `re-config` 那两条是**回归门禁**：我在验收中先发现「第二次 `-Config` 被忽略（staging 里的旧 config.yml 被复用）」这个 P0，ps-installer 已按「staging config 每次无条件重写 + `$sourceNeedsUpdate` 独立判断」修复，复验通过。

### 3.2 任务书验收 1：隔离安装 ✅

`dsh plugin add` 装到探针 profile 后 `--dump-config`：**exit 0 / stderr 0 B / 1800 行**（未装时 1517 行，+283）：

```
1518: # == @local/dsh-vivado
1519: - id: preset-vivado
1520:   name: '@deepseek-ai/dsh-agent-preset'
      ...
1648:       customSkillDirs:
1649:         - C:/Users/***/dshprobe-home/bundles/dsh-vivado/skills
      ...
1780:       - id: mcp-vivado                     ← 缩进 6 格 = 在 preset 作用域内
```

### 3.3 任务书验收 2/3：陌生人视角 + 可卸载 ✅

- **陌生人**：`part: xc7a35tftg256-1` + `project_root: D:/fpga_work` → 安装 exit 0，渲染出的 persona 变 `part xc7a35tftg256-1; project root D:/fpga_work`，旧值 `xcku060` 计数 0。
- **可卸载**：`uninstall.ps1` → 依赖行/bundle 行删除、staging 目录删除、junction 删除、`--dump-config` 无 `preset-vivado`、**二次运行 exit 0（nothing to remove）**；ps-installer 另证「restore-backup 分支下 `package.json` 与 pristine **逐字节相同**」。

### 3.4 真实会话口径（探针会话，非推导）

`task_board` 卡片 `mode: vivado`（只读、零工具调用），会话 `session-8e0bf762…` 回答原文（`session_event_read seq=20`）：

```
MCP_COUNT=32
MCP_NAMES=check_bitstream_readiness,compare_xci,...,xdc_lint      ← 32 个，与 MANIFEST.tool_catalog 一致
TOTAL_TOOLS=97                                                     ← 65 非 MCP + 32 MCP
SKILLS=amd-doc-search,...,vivado-rtl-lint,vivado-simulate-rtl      ← 25 个（含本 kit 那 7 个技能）
PERSONA_VIVADO=YES                                                 ← 系统提示含 "Vivado is GLOBALLY SERIAL"
```

⇒ **任务书的 `91 = 59 + 32` 是旧 profile 口径，实测为 97**（结论 §2.3 已预告）。kit 的 22 条插件行与该预设**逐字节相同**，唯一增量是 persona 文本与 `skill-filesystem` 的 `customSkillDirs`（**+0 工具**），所以工具面不因换 kit 而变。

### 3.5 T4 补丁：对 pip-pristine 基线 4/4 可应用、逐字节还原

Lead 独立复算（`RECORD` 的 sha256 是 **base64url**，需先解码再比）：

| 文件 | pip RECORD（hex 前 16） | 哪个 `.bak` 才是 pristine | live 是否已改 |
|---|---|---|---|
| `analysis/xdc_linter.py` | `04cc9cad0a7a9877` | **`.bak-mcp-20261024`**（`…b` 是中间态） | 是 |
| `tools/cdc_tools.py` | `7976e4a71a219339` | `.bak-mcp-20261024b` | 是 |
| `tools/diagnostic_tools.py` | `c1277aa2ea624530` | **`.bak-mcp-20261024`**（`…b` 是中间态） | 是 |
| `tools/tcl_tools.py` | `478a8142afa0e032` | `.bak-mcp-20261024` | 是 |

用上述 pristine 副本 `git -c core.autocrlf=false apply -p1` 依次应用 4 个补丁：**4/4 成功**，且应用后与 live 文件 **4/4 `cmp` 逐字节相同**。⇒ 补丁可安全随包分发（Apache-2.0 §4(b)：只发补丁、不发改动后的源码；优先上游 PR）。

### 3.6 persona 两档 + 模板溯源

- 两档渲染 + `validate_patch.py`：**VALIDATE PASS**（2023.1 含 `8.5.14` / `-noprogress` / `1024`；2025.2plus 含 `NOT measured` / `Re-probe` / `unverified`；除 `{{model}}` 外 0 个未替换占位符；`{{model}}` 是 DSH 提示词占位符，故意保留）。
- `py tools/make_template.py --check` → PASS（模板/审计件行集一致、sha256 一致、9 个占位符集合固定、无个人路径）。
- 22 行溯源：审计件 21 行 + 模板 21 行与已实证 bundle 逐字节一致（persona 行是我们自己的文本，含作者机器绝对路径，**刻意不随包分发**，审计件里以注释替代并记录原始 sha256 `903077529fcf…`）。

---

## 4. 与任务书的偏离（都有实测依据，不是省事）

| # | 任务书写法 | 实际做法 | 为什么 |
|---|---|---|---|
| 1 | 验收「工具面 91（59+32）」 | 以 **97（65+32）** 为准，增量 32 才是稳定判据 | 探针会话实测；旧数字是旧 profile 口径（前序结论 §2.3 已说明） |
| 2 | 「本轮打了 3 个补丁」 | **4 个文件 / 4 个补丁** | pip RECORD 逐文件比对：`tcl_tools.py` 也被改（`safe_tcl` 提示 + `max_lines`）；`diagnostic_tools.py.bak-…b` 是中间态，被误当 pristine 会生成打不上的补丁 |
| 3 | vivado-mcp 未标许可 | **Apache-2.0**，NOTICE 单列 + §4(b) 义务 + PR 优先 | `METADATA` 的 `License-Expression` |
| 4 | doctor 检 Python ≥3.9 | **≥3.10** | `vivado-mcp` 0.3.26 `Requires-Python: >=3.10` |
| 5 | `install.ps1` 备份后缀 `bak-<日期>` | `Backup-KitFile -Suffix <YYYYMMDD>`（helper 内部已拼 `.bak-`） | 否则产出 `package.json.bak-bak-YYYYMMDD` |
| 6 | 「装 bundle 后改 profile」 | 走**官方 CLI**（`dsh plugin add/remove`）而不是手改 `package.json`/`cordis.patch.yml` | 官方 skill 明确要求；实测 CLI 会自己 reconcile `dsh.profile.bundles` |
| 7 | 「同门环境画像待确认」 | 全部参数化（part / project_root / vivado_path / vivado_version / python / site / cwd / temp_dir），并**两档 persona** | 陌生人视角实测：换 part 与 project_root 仍可装、persona 跟随变化 |
| 8 | 包名（任务书/首轮为 `dsh-vivado-kit`，行名 `preset-vivado`） | 聚合包名 **`dsh-vivado`**（预设只是其中一层，另有 32 个 MCP 工具与 8 个技能，后续还要加工具） | 用户 2026-10-24 裁决；顺带把「手动模式的 junction 路径」从硬编码 `node_modules\@local\<name>` 改成**按包名推导**（无 scope 时是 `node_modules\dsh-vivado`），否则 `-Mode manual` 装完解析不到包 |
| 9 | 仓库位置：`<repo>/dist/dsh-vivado-kit/` | **独立仓库** `chemmy-11/dsh-vivado`（private），`D:\FPGA\dist\` 已撤除 | 用户裁决「不 commit 到 EIF，新建仓库方便后续拓展与分发」；EIF 工作树回到干净状态 |

---

## 4.5 上游许可审查（2026-10-24 追加，用户要求先查「允不允许」）

**结论：三个上游全部允许本包分发**；义务都属于「保留版权与许可声明」一类，已逐条履行。完整审查（含命令）：`docs/licensing.md`。

| 上游 | 我们分发什么 | 许可（取证） | 允许 | 已履行 |
|---|---|---|---|---|
| **AMD 官方 6 技能** | `skills/` 里 6 个目录（逐字节 + 我们改的 7 文件） | **MIT** © 2026 AMD：`vsix :: extension/resources/plugin-bundled/LICENSE`；GitHub API `Xilinx/ross-ai-assistant` → `spdx_id=MIT` | ✅ | `NOTICE` §1.2/§1.3 + 附录 A |
| **DeepSeek Harness 的 22 条插件行** | 预设 patch 片段（配置数据，非代码） | **MIT** © 2026 DeepSeek：`app.asar` 顶层 `package.json` 与 `dsh-web-app/package.json` 均 `"license": "MIT"`，两处 `LICENSE` 文件均为 MIT 全文；安装目录**无** DSH 自身 EULA | ✅ | `NOTICE` §3.1 + **附录 C**（本轮补） |
| **vivado-mcp 0.3.26** | **只发 4 个 `.patch`**，不发源码 | **Apache-2.0**：`dist-info/METADATA` 的 `License-Expression`；GitHub `/license` → Apache-2.0 | ✅ | §4(a) 随包 `LICENSE-APACHE-2.0.txt`、§4(d) 上游无 NOTICE（已核对）、§4(b) 改文件标记指引（本轮补） |

关键边界（必须记下来）：同一 vsix 的**外层是专有 EULA**（`extension/LICENSE.txt`，§5.1 有保密/不转交限制），
但该协议 **§4.1** 明确「Additional Materials 不由本协议授权、而由随附的各自许可支配」，`plugin-bundled/**` 自带 MIT LICENSE
⇒ 技能子树按 MIT；§4.1 同时说 §6（免责）/§7（责任限制）/§9.3（管辖法）仍适用 ⇒ 已在 `NOTICE` §3.2 + `LICENSE` §4 写入无担保/无背书口径。

本轮补的三项义务：① `NOTICE` 附录 C 收录 DeepSeek MIT 通知（原先只写「属 DSH 宿主应用」= 等于没写许可）；
② 随包附 Apache-2.0 全文 `patches/vivado-mcp/LICENSE-APACHE-2.0.txt`（10 774 B，sha256 `77b29df2…`）；
③ 商标/无背书声明（`NOTICE` §3.2）。另修：`.gitattributes` 钉死 NOTICE/LICENSE 等无扩展名文件的 LF（本机 `core.autocrlf=true` 会改写）。

---

## 4.6 本地安装（live desktop profile）与升级流程 · 2026-10-24 追加

**结论：已把旧的 `@local/dsh-vivado-preset`（vault 里的手工 bundle）移除，改装本包，并在真实会话里验证生效。**

| 步骤 | 实际动作 | 证据 |
|---|---|---|
| 0 | 备份 live profile 四个文件 | `package.json.bak-before-kit-update-20261024` / `pnpm-lock.yaml…` / `compatibility.json…` / `cordis.patch.yml…` |
| 1 | **发现 CLI 护栏**：宿主运行期间 `dsh plugin --profile desktop …` 直接拒绝 | 原文 `error: profile "desktop" is managed exclusively by the Electron application`（有意保护，不是坏了） |
| 2 | 改走宿主内 `plugin_manager` | `remove_bundle @local/dsh-vivado-preset` → `application: applied`；`install_bundle C:\Users\***\.dsh\bundles\dsh-vivado` → `application: applied`、`dsh-vivado 0.1.0` |
| 3 | staging 用 `install.ps1 -RenderOnly` 准备（不碰 profile） | 渲染 `cordis.patch.yml` sha256 `f9ed94f7…`；staging 的 README/docs/NOTICE/LICENSE 与仓库逐字节相同 |
| 4 | **真实会话验证**（`mode: vivado` 探针卡片，零工具调用） | `MCP_COUNT=32`、`TOTAL_TOOLS=98`、`PERSONA_VERSION_TIER=YES`（新 persona 才有的措辞）、`PERSONA_DSH_VIVADO=YES`、`SKILL_WORKFLOW_DISCIPLINE=YES`（**只存在于本包 skills/ 的技能，证明 rank 300 挂载真生效**）、`SKILL_COUNT=26` |
| 5 | 生效状态 | 宿主内 `Config.listConfigs` 出现 `include:preset-vivado`（与 standard/ptc/minimal/cordis 并列）；profile `package.json` 只剩 `dsh-vivado`，bundle 列表 14 项 |

两条可复用的结论：

1. **`dsh plugin` 与 `plugin_manager` 的分工**：宿主关着 → 用 CLI（`install.ps1` 默认路径）；宿主开着 → 只能用宿主内 `plugin_manager`，
   但后者**不刷新 staging 的文档/脚本副本**，所以最终仍应关宿主跑一次 `install.ps1` 做干净更新。已写进 `docs/install.md` §1.5 与两份 README。
2. **旧手工 bundle 与本包声明同一个 preset 行 id（`preset-vivado`）**，同时装 = id 重复；迁移必须先移除旧的。已在 §1.5 明写。
   另：`pnpm remove` 之后 `node_modules/@local/<name>` 的 junction 会残留，必须显式 `[System.IO.Directory]::Delete($link,$false)` 清掉。

---

## 4.7 插件图标与显示元数据 · 2026-10-24 追加

用户要求：把 Vivado 官方标志按 dsh 插件图标的配色改成我们的插件图标，**实装并发布**。

**契约（读源码确认，不是猜）**：`@deepseek-ai/dsh-app-boot` 的 `readPluginMeta` / `iconOf` ——

| 显示项 | 来源 | 约束 |
|---|---|---|
| 标题/描述 | `locale/en.json` 的 `meta.title` / `meta.description`（`locale/zh.json` 同构） | 纯 JSON |
| 图标 | `package.json` **顶层 `icon`**（优先级高于 `exports["./icon"]`） | svg/png/jpeg/webp、≤256 KiB、必须留在包目录内；宿主转成 `data:` URL 交给前端 |
| 生效 | 宿主每次读包元数据，**与 patch 无关** | 重新 staging（`install.ps1 -RenderOnly`）即可 |

**做法**：把图一（Vivado 三平面标志）逐像素重上色——金色三档 `#E5E792 / #DADC56 / #8B8D09`
按亮度插值映射到 `#9BE7F7 / #5C86FF / #2B45B0`（取图二 dsh 插件图标的蓝/青族，主蓝邻域 `#658EFF`），
衬在 `#17181C` 深色圆角面板（r=112、细边框 `#3A3E46`，呼应图二的圆角深底）。产物 512×512 PNG / 51 KB，
按 48×48 与 24×24 预渲染检查过可辨认。

**徽章/文案**：`README ×2` 顶部居中图标；`package.json` 顶层 `icon`；`locale/{en,zh}.json` = "Vivado Workflow" / "Vivado 工作环境"；
`docs/architecture.md` §8.5 记录契约与换法；`NOTICE` §3.0 明确 **图标不属 MIT**（Vivado/Xilinx 标志的著作权与商标归 AMD，仅用于指称本包所服务的工具，若 AMD 提出异议将换成不含其标志的原创图形）。

**验证**：图标契约 4 项（相对路径/包内/媒体类型/≤256 KiB）PASS；staging 与仓库逐字节相同；公开仓库 `raw.githubusercontent.com/.../icon.png` → HTTP 200 / 51 952 B / `image/png`。
**未验证**：浏览器里的实际渲染（无浏览器控制）。插件页在「设置 → 插件」打开时读元数据；若看不到图标，重启宿主再开该页。

---

## 4.8 环境收身：本地只留一份（2026-10-24 晚）

用户裁决：本地只用 `dsh-vivado` 插件，避免与旧的手工 bundle/项目级技能互相遮蔽，也方便后续开发验证。

**归档（不删证据）**：`<vault>\归档\dsh-vivado_迁移归档_2026-10-24\`（697 文件 / 1.83 MiB，附 `README.md` 写明每项来源与回滚命令）

| 归档子目录 | 原位置 | 处置 |
|---|---|---|
| `old-bundle-vivado-preset/` | `<vault>\.dsh\bundles\vivado-preset\` | 已删；profile 早已解绑 |
| `vault-skills/` | `<vault>\.dsh\skills\<7 个技能目录>` | 已删；技能实体改由插件 rank 300 提供（脱敏版） |
| `profile-backups/` | `~\.dsh\profiles\desktop\*.bak-*`（14 个） | 已从 profile 目录移出 |
| `kit-dev-reports/` | `<vault>\.vivado-scratch\kit-2026-10-24\` | 已移出 |
| `dev-scratch/` | `D:\FPGA\.tmp\kit-recon-2026-10-24\` 的取证副本/图标草稿/探针 dump | 已移出（验收脚本正规迁进插件仓库 `dev/`） |
| `stray-files/` | vault 根两个 0 字节 `.sv` 残骸 | 已移出 |

**清理量**（逐项实测）：`.vivado-scratch` **112 MiB → 5.95 MiB**（8 个 PyInstaller `_MEI*` = 106 MiB）；
3 个探针家目录（`dshprobe-home/accept/collide`，各 ~350 MB）已删；`%TEMP%\dsh-vivado-dev`（新验收脚本的隔离 home）**763 MB 已删**；
`D:\FPGA\.tmp\kit-recon-2026-10-24` 已删（取证副本进归档）；vault `.dsh` 只剩 `skills\MANIFEST.json`；归档目录 2 053 文件 / 5.67 MiB（含 6 份队友报告）。

**顺带把验收脚本正规化进插件仓库**（`dev/`，4 文件 1 653 行，**不进安装包**）：`accept_all.py`（6 组 49 条断言）、
`make_probe_home.py`（隔离 `DSH_HOME`，源 profile 只读）、`validate_patch.py`、`dev/README.md`（含「不覆盖项」）。
实测：**全量 49/49 passed**、`--only install,uninstall` 25/25、live profile 指纹 UNCHANGED（脚本自带 `[GUARD]`）。
`lib/install-helpers.ps1` 的 staging `/XD` 已加 `dev`（staged 683 文件里确认没有 `dev/`）。

**门禁口径同步（EIF `78b8802`）**：`AGENTS.md` §六 资产表改为「8 个技能随 bundle 携带、仅 Vivado 预设会话可见」，
doc-search CLI 桥指向 `D:\dsh-vivado\skills\amd-doc-search\doc_search.py`；§十二 增 7a 说明「技能目录为空 ⇒ 检查 7–10 自动 SKIP，
MANIFEST 作为冻结快照保留，检查 12 仍有效」；`docs/agent.md` 重新脱敏镜像。`ci_check.py` → PASS（相等 76 / 豁免 8 / 未登记 0）。

**清理后实测**：`doctor.ps1` **12 PASS / 1 WARN（license）/ 0 FAIL**；profile 只剩 `dsh-vivado`（14 bundle 总数不变）；
`node_modules\@local\` 消失、只剩 `node_modules\dsh-vivado` 链接；Vivado 预设会话 persona 正常、**8 个技能全部来自包内**。

**✅ 收尾事故：0 个 MCP 工具 → 真因是「路径不存在」，已修并产品化**

清理期间出现：Vivado 预设会话里 persona 与 8 个技能正常，但 `mcp__vivado__*` 工具数为 **0**；
`doctor` 第 6/7/12 项全绿、`mcp_ctl.py list` 仍 32 行、宿主重启后依旧 0。

- **真因**：为了公开化把 `config.example.yml` 的示例路径改成 `D:/fpga_project`，后续 `install.ps1 -RenderOnly`
  用示例值重渲染了 staging ⇒ MCP 行的 `cwd` / `TEMP` / `TMP` 指向**不存在的目录** ⇒ stdio 子进程起不来，
  而该行是 `failOnStartupError: false` ⇒ **失败静默**，会话只剩「没有工具」一个症状。
  （我一开始把现象归因为「热重载后子进程不重启」，**是误判**：重启后仍为 0。）
- **修复**：把 staging `config.yml` 的三个路径改回真实目录 + 重渲染 → **`MCP_COUNT=32 / TOTAL_TOOLS=98 / 8 技能 / persona YES`**（探针会话实测）。
- **产品化防线**（插件仓库 `d680047`）：`install.ps1` 渲染前拦截不存在的 `project_root` / `vivado_mcp_cwd`
  （`temp_dir` 缺失自动创建，其余 FAIL 并给「改哪个键 / 怎么改 / 为什么」）；`doctor.ps1` 的 `ascii-paths`
  增加存在性判据；两者未显式 `-Config` 时**优先用 staging 的有效配置**（重装不再退回示例占位路径）；
  `docs/troubleshooting.md §2.11` 与 `docs/doctor-checks.md §5` 同步；`dev/` 夹具改为自建 `<work-dir>/project`。
  全量验收 **49/49 passed**（live profile 指纹 UNCHANGED）。

---

## 4.9 实战问题清单落地（2026-10-25，kit 0.1.1）

依据：`结论_cross_dsh-vivado实战问题与改进_2026-10-25.md`（16 条实测问题 / 13 条建议）。
本轮裁决变化：**不再适配第三方 shell 插件**（`@linxin666/dsh-win-bash` 已在本机禁用，别人环境也不一定有），
改为只用会话里真实存在的官方 `pwsh` / `bash`；`win_bash` 一类只作为可选加速件提及，缺失时不得改变计划。

| 改了什么 | 落到哪 | 验证 |
|---|---|---|
| persona 解除第三方 shell 依赖 + 启动矩阵 / 成功判据 / 脱离式长构建 / 操作→工具决策表 / 报告交叉核对 | `templates/persona/{2023.1,2025.2plus}.frag.yml`（两档同步） | 两档渲染 + `validate_patch.py --tier` PASS；新增 `PERSONA_FORBIDDEN` 断言禁止回退 |
| 三个运行辅助脚本 + 构建标记行 | `tools/vivado-probe.ps1`、`tools/vivado-run.ps1`、`tools/tcl-check.ps1`、`templates/build-markers.tcl` | 真机：probe `PROBE_RESULT=OK`；run(wait) `RUN_EXIT=0`；run(-Detach) 6 s 内 `BUILD_EXIT=0`；tcl-check 7/7 PASS |
| 包装器三处坑（WinPS 5.1 `ExitCode=$null` / 批处理缺 `call` / `%DATE%` GBK） | `lib/common.ps1` | 见问题清单 §9.3（含最小对照实验） |
| 32 工具清单与离线/会话依赖表 | 新增 `docs/tools.md` | 32 与 `doctor` 第 7 项一致 |
| EIF CI 第 5 项从"永久 SKIP"变真门禁 | `D:\FPGA\scripts\ci_check.py` | 本地 `py scripts\ci_check.py` **PASS**（顺带修掉 `git ls-files` 的 GBK 解码回退：2730 → 17969 的假数） |
| 工具链漂移会让 MCP 行静默消失 | `compatibility.json` 合并 `0.2.1-rc.3`（备份 `.bak-20261025`） | `doctor` 第 12 项 WARN → **PASS** |

新增/加强的断言：`dev/validate_patch.py` 的 `PERSONA_PHRASES` 扩到 9 个必需短语 + `PERSONA_FORBIDDEN`
（禁止 `is the shell for command work` / `fall back to \`win_bash\`` 回退）；`dev/accept_all.py` 静态组
8 → 9 条（启动件在场且纯 ASCII），矩阵 **49 → 50**。

验证汇总：`accept_all --only static` **9/9**；`install.ps1 -RenderOnly` 刷新 staging（688 文件，
patch sha256 `53e6888461d3`）后 `validate_patch` PASS；`doctor.ps1` **11 PASS / 2 WARN / 0 FAIL**
（WARN = 当前 shell cwd 是中文目录、未设 license 环境变量）。

仍未做：vivado-mcp 侧 4 条 P1（`run_tcl_file`、`background`、`include_paths=false`、`xdc_lint`
良性族分组）按"PR 优先、不做私有 fork"留待上游；`2025.2+` 档依旧零实测。

---

## 5. 未做 / 限制（如实登记）

| # | 事项 | 说明 |
|---|---|---|
| 1 | ~~kit 的 8 技能未在真实会话里数过~~ **已补测（§4.6）** | `vivado-workflow-discipline` 在 live 会话可见 ⇒ rank 300 挂载真实生效。仍**未**重启宿主（重启后更彻底）。此前已验证的是：`dump-config` 的 `customSkillDirs` 指向 staging、`skills/` 8 个 `SKILL.md` 的 `name==dir`、`MANIFEST --check` PASS，以及**同一批 7 个技能在真实 Vivado 预设会话里可见**（§3.4 `SKILLS=` 列表）。`vivado-workflow-discipline` 是本轮新增，仅在文件级验证 |
| 2 | 2025.2+ 档全部未实测 | `docs/version-matrix.md` 与 persona 里逐格标注「文档/未实测」，并给了新机重探 checklist（`puts [info patchlevel]`、`open_project -noprogress` 探测、`report_* -help`） |
| 3 | AMD 6 技能的**本机适配注记**里仍有作者机器绝对路径（`D:\vivado-mcp` 等） | 按「逐字节复制 + 不伪造 pristine」取舍；`skills/NOTICE-skills.md §1.3` 已声明，public 版前脱敏（LICENSE 待办已列） |
| 4 | `docs/version-matrix.md` / `docs/install.md` 的证据引用含作者本机路径 | 它们是「本机实测」证据，保留可复核性；不含账户名与 vault 中文路径（已 grep 确认） |
| 5 | compatibility.json 只能由 doctor 验证，安装器的 dump 判据证不了 | 见 §2.6；`docs/install.md` §4 已写明 |
| 6 | public 版正式 SPDX 审查 | **上游许可已逐项查清并履行**（§4.5）；剩下的是「我们自己内容的最终许可选择 + 技能注记脱敏 + 4 个补丁提上游 PR」，见 `docs/licensing.md` §4 的待办清单 |
| 7 | 已 public；剩余对外动作 | 4 个补丁提上游 PR（`patches/vivado-mcp/README.md` §6）、可选的工具化 SPDX 扫描（如 reuse/scancode）；这两项不影响现在的可用性与合规 |
| 8 | **行尾陷阱（已修，记下来）** | 首轮 MANIFEST 是在 CRLF 工作树上生成的；一旦 clone 到 LF（`.gitattributes` 生效）`source_hash` 就对不上、`--check` 立刻 FAIL。已用 `skills/** text eol=lf` 钉死 + 重生成 MANIFEST + 在**全新 clone** 上复跑门禁（现 PASS）。教训：**凡是对文件字节做哈希的门禁，必须在一个行尾确定的检出上生成** |

---

## 6. 回退（逐行，不依赖脚本）

```powershell
# ① 卸载（推荐）
powershell -ExecutionPolicy Bypass -File D:\dsh-vivado\uninstall.ps1 -Profile desktop
# ② 手工回退（脚本不可用时）——先看备份
dir "$env:USERPROFILE\.dsh\profiles\desktop\*.bak-*"
#   package.json.bak-YYYYMMDD 里删掉两处：dependencies 的 "@local/dsh-vivado" 行、dsh.profile.bundles 的末项
#   再删 junction 与 staging（顺序重要）：
cmd /c rmdir "%USERPROFILE%\.dsh\profiles\desktop\node_modules\@local\dsh-vivado"
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\bundles\dsh-vivado"
# ③ 重启宿主（必须）
```

kit 对系统**没有**其它写入：不改环境变量、不写注册表、不写 `~/.dsh/skills`、不装服务（Lead 验收里已断言 `~/.dsh/skills` 前后一致）。

---

## 7. 证据索引

| 文件 | 内容 |
|---|---|
| `D:\FPGA\.tmp\kit-recon-2026-10-24\accept_all.py` | Lead 的独立验收脚本（6 组 49 断言）；`--only <group>` 可单跑 |
| `…\make_probe_home.py` | 隔离 `DSH_HOME` 构造器（308 MB node_modules 全量复制 + pnpm 记账重定向，避免写穿 live profile） |
| `…\validate_patch.py` | 渲染产物结构校验（23 行 / persona 关键字 / customSkillDirs / mcp 环境 / 无残留占位符） |
| `…\make_template.py` 日志 / `templates/shipped-standard-22rows.yml` | 22 行溯源与 sha256 |
| `…\pkg_*.json` / `probe_dump_*.txt` | 安装前后 `package.json` 与 `--dump-config` 快照（1517 → 1800 行） |
| `<vault>\归档\dsh-vivado_迁移归档_2026-10-24\kit-dev-reports\reports\ps-skills.md` | 技能复制/清单/溯源全记录（含反例 6/6） |
| `…\kit-dev-reports\reports\ps-docs.md` | 许可/分档/补丁归档全记录（含 `git apply` 4/4 与 persona 双路径校验） |
| `…\kit-dev-reports\reports\ps-installer.md` | A–H 实测矩阵 + 4 条偏差 |
| `…\kit-dev-reports\reports\ps-doctor.md` | 13 项检查判据 + 3 个注入故障实测 |
| 探针会话 `session-8e0bf762-f1b0-4dd4-bc55-7bf2327f8a4a` | 旧 bundle 口径 97/32/25/persona=YES 的原文 |
| 探针会话 `session-8fca600b-0a9d-4c82-82f0-94d53c60ee13` | **本包**装进 live profile 后的口径：32 / 98 / 新 persona / `vivado-workflow-discipline` 可见（§4.6） |
| `https://github.com/chemmy-11/dsh-vivado` | **公开仓库**（public / MIT / 676 文件）：`14fefe5` → `352dfa9`（LF）→ `0a378ed`（MANIFEST）→ `00cc0d3`（许可审查）→ `1f46491`（公开版：MIT+脱敏+徽章）→ `bcd018a`（LICENSE 纯 MIT 文本）。`git ls-remote origin main` == 本地 HEAD |
| `C:\Users\***\dsh-vivado-public`（测试产物） | **匿名 HTTPS clone**（`git -c http.proxy= clone https://github.com/chemmy-11/dsh-vivado.git`）成功；在其上跑完整验收 **49/49** |
| `docs/licensing.md`（kit 内） | 许可审查全记录：结论表 / 逐上游事实与证据 / 外层 EULA §4.1 原文 / 残留风险 / 复核命令 |
| `C:\Users\***\dshprobe-home\`（**保留**，358 MB） | 已装好 kit 的隔离 `DSH_HOME`（profile `probe`），可用于你重启后的会话级复验：`DSH_HOME=C:\Users\***\dshprobe-home <DSH>\resources\runtime\cli\bin\dsh.cmd --profile probe --dump-config`；不需要时整个目录删掉即可 |
| `D:\FPGA\.tmp\kit-recon-2026-10-24\` | 取证/测试脚本与日志（`.tmp/` 已被 `.gitignore` 覆盖，不入库） |

---

## 8. 仓库与提交记录（已执行）

| # | commit | 内容 |
|---|---|---|
| 1 | `14fefe5` | `feat: dsh-vivado — Vivado 工作流 DSH 聚合包（会话预设 + 32 工具 MCP + 8 技能）`，674 文件 |
| 2 | `352dfa9` | `chore: pin skills/ checkouts to LF`（`source_hash` 门的行尾前提） |
| 3 | `0a378ed` | `fix(skills): regenerate MANIFEST after LF normalization`（门禁在 LF 检出上 PASS） |
| 4 | `00cc0d3` | `docs(licensing): 上游许可审查并补齐三项义务（DSH MIT 通知 / Apache-2.0 全文 / 商标声明）` |
| 5 | `1f46491` | `release: 公开版 —— 自有内容切 MIT、注记脱敏、徽章、可移植的模板生成器` |
| 6 | `bcd018a` | `fix(license): LICENSE 保持纯 MIT 文本（让 GitHub 识别为 MIT），carve-out 表移入 NOTICE §3.0` |
| 7 | `bac42d6` | `docs: 中英双版 README + 面向用户重写；深层内容拆到 docs/architecture.md 与 docs/troubleshooting.md` |
| 8 | `59f1fe4` | `docs: 补「更新/升级已装版本」流程` |
| 9 | `0fe9ad3` | `feat(icon): 插件图标 + 中英显示元数据（Vivado 标志按 dsh 配色重上色）` |
| 10 | `e1d7543` | `feat(dev): 端到端验收脚本搬进仓库 dev/ + 补「热重载后 MCP 子进程不重启」排错` |
| 11 | `7ea435e` | `feat: 按实战问题清单改进 —— 解除第三方 shell 依赖，补启动/长构建/Tcl 门禁三件套`（21 文件 / +1038 −38，kit 0.1.1；见 §4.9） |

- 仓库：`https://github.com/chemmy-11/dsh-vivado`（**public**，默认分支 `main`，license 被 GitHub 识别为 **MIT**，topics: dsh / dsh-bundle / vivado / fpga / amd / xilinx / mcp / agent-preset / agent-skills）
- 匿名可达性：`git clone https://github.com/chemmy-11/dsh-vivado.git`（无密钥）实测成功；README 6 个徽章 URL 均 HTTP 200
- 推送通道：SSH（`git@github.com:chemmy-11/dsh-vivado.git`，本机 HTTPS 到 github.com 不稳，SSH 始终可用）
- 校验：`git ls-remote origin main` = `0a378ed…` = 本地 `HEAD`；随后**从远端全新 clone** 到 `C:\Users\***\dsh-vivado-clone`（测试后已删），在其上复跑：
  `make_template.py --check` PASS、`gen_skills_manifest.py --check` PASS、`render_patch.ps1` + `validate_patch.py` PASS、`doctor.ps1` 裸环境 7 PASS/6 WARN/0 FAIL（exit 0）、已装探针 12 PASS/1 WARN/0 FAIL、**完整验收 49/49**。
- EIF 仓库（`D:\FPGA`）：未提交任何东西；`git status` 干净（`dist/` 已移出），`py scripts\ci_check.py` 仍 **PASS**。
  > 2026-10-25 更新：本轮在 EIF 提了一条 `fix(ci)`（`scripts/ci_check.py` 第 5 项改真门禁 + `git ls-files` 解码修复、
  > `AGENTS.md` 同步说明、两篇镜像文档随内容更新），此时 `git status` 干净、`ci_check.py` **PASS**；hash 见
  > `git -C D:\FPGA log -1`（文档不记录自身提交的 hash，避免改一次写一次的循环）。

> 下一轮拓展（加工具/技能）只需：往 `templates/preset.patch.yml.tmpl` 的插件行里加一条、或往 `skills/` 加目录，
> 然后 `py tools/gen_skills_manifest.py` 重生成清单 + 跑 `py tools/make_template.py --check` 与 `accept_all.py`。
