# 结论_cross_Vivado 环境 DSH 规范化验收 · 2026-10-24

> 执行：DSH Team（lead + `skills-manifest` + `ci-gate`），2026-10-24 12:59–14:00（Asia/Shanghai）
> 需求来源：`任务书_vivado环境DSH规范化_2026-10-24.md`；前置证据：`结论_cross_vivado-mcp健康与使用核查_2026-10-24.md` §1–§10
> 用户已裁决 5 条功能口径（本文 §1）；技术契约与判定细则：`.vivado-scratch/vivado-norm-2026-10-24/SPEC.md`
> 纪律：执行阶段 `D:\FPGA` 未 commit（按当时的红线），收尾按用户指示统一提交并推送（见 §5 第 6 项）；未删任何项目文件；未改 `D:\vivado-mcp\site` 源码；未跑综合/实现/仿真；Vivado 进程全程为 0。

---

## 0. 一句话结论

| 交付 | 结论 | 一句话证据 |
|---|---|---|
| **T1 Vivado 预设** | ✅ **采用**（三门禁全过） | 预设会话 **32** 个 `mcp__vivado__*` + **97** 工具；standard 会话 **0** 个 / 63 工具；**子 Agent 与 teammate 都拿到 32 个** |
| **T2 技能清单 + 门禁** | ✅ 完成 | `MANIFEST.json` 由生成器产出（禁手写）；`ci_check.py` 250→848 行，新增检查 7–12；反例 **37/37**；`=== CI: PASS ===` |
| **T3 `agent.md` 收口** | ✅ 完成 | 场景路由表 14 行 + `BEGIN:skills` 脚本区块 + 镜像门禁口径；vault 179 行 ↔ `docs/agent.md` 脱敏等价 |
| **镜像门禁（D1）** | ✅ 生效并实测抓到过真漂移 | docs 83 篇 = 归一相等 68 + 白名单 15（drift 9 / docs-only 6），**未登记 0** |

> 唯一必须由用户完成的动作：**重启 DeepSeek Harness**（profile 在启动时读取，`dsh-hmr` 在 Electron 下不生效）。重启后新会话创建时才会出现 `Vivado` 预设。

---

## 1. 用户裁决（2026-10-24 13:00，落地不得擅改）

| # | 议题 | 裁决 |
|---|---|---|
| D1 | T3 镜像门禁口径 | **脱敏归一 + 带理由白名单**（不是「零 diff」——那与 AGENTS.md 十二节「docs 是脱敏快照、禁止用 vault 覆盖」正面冲突） |
| D2 | T2 门禁运行位置 | **本地门禁**：vault 不存在时整段 `SKIP`，远程 GitHub CI 自动跳过 |
| D3 | T2 `baseline` 口径 | **双字段分工**：`amd_doc` 取技能自述；`tested_on` 只在**确有实测证据**时写 2023.1，否则 `null` + `unverified` + 证据出处 |
| D4 | T1 默认预设 | **默认 `standard`，Vivado 任务手动切 `Vivado`**；全局 `mcp-vivado` 行移除 |
| D5 | T1 落地协议 | **直接落地 + 事后回退**（不先等确认） |

---

## 2. T1 · `preset-vivado`（最高优先，已采用）

### 2.1 机制（读运行中安装包源码确认，不是猜的）

`dsh-agent-preset-registry` README 原文（`D:\dsh\resources\app.asar` 内，中文版同义）：

> 新建 preset 或覆盖内置 preset **都是 bundle 补丁**：插入一行 `@deepseek-ai/dsh-agent-preset`，或按该行 id 写覆盖补丁，再用 `plugin_manager` 安装到 profile；**创造模式**在对话中编写这类 bundle。
>
> 激活审计检查导入失败、缺失服务和向全局泄漏的服务。导入失败、激活失败和泄漏会**拒绝挂载**。
>
> Agent、**子 Agent** 和临时历史读取各自持有引用，最后一个引用释放后才销毁插件树。

⇒ 任务书说的「创造模式产出 bundle patch」是官方支持的路径，本文按它落地。

### 2.2 「禁止手抄」是怎么保证的

| 步骤 | 做法 | 证据 |
|---|---|---|
| 取 shipped 22 行 | 自写 asar 容器解析器 `extract_asar_file.py` 从安装包原样导出 `dsh-web-app/presets/standard.patch.yml`（128 行） | `size=6799` `sha256=0d398d2a6872a73a106cb3bd19303ecccf1637e1fcad4d0bf9d8a72d2c2c68f5` |
| 组装 | `build_vivado_preset_patch.py` 脚本拼装，**断言** persona 之后的 21 行与 shipped 逐字节一致 | 输出 `[PASS] persona 之后的 21 行与 shipped 逐字节一致；persona 已替换；mcp-vivado 已追加` |
| 结果 | 22 行（persona 改为 Vivado 纪律版）+ `mcp-vivado` 行 = **23 条顶层插件行** | `shipped 22 → [...21 行...]` / `产物 23 → [... + mcp-vivado]` |

> 顺带纠正一个环境陷阱：PATH 上的 `dsh` CLI 是 **0.1.7-rc.2**，运行中的 Electron 是 **0.2.1-rc.2**；用 `dsh --dump-config` 取到的是旧版树。正确入口是 **`D:\dsh\resources\runtime\cli\bin\dsh.cmd`**（内部 `ELECTRON_RUN_AS_NODE=1` 跑安装包里的 cli.js）。

### 2.3 三门禁（任务书要求「任一不过就停手」）

| 门禁 | 判据 | 实测 | 结论 |
|---|---|---|---|
| ① 激活审计 | 预设内挂 `dsh-mcp-client` 是否被 import/缺服务/全局泄漏拒挂 | `Config.listConfigs` 显示 `include:preset-vivado` **status=schema**，与出厂 4 个预设（standard/ptc/minimal/cordis）同级；隔离 profile 启动 stdout/stderr **零** `disabling`/`incompatible`/审计错误 | ✅ PASS |
| ② 会话工具面 | 预设会话应有 32 个 MCP，standard 会话应为 0 | 探针 A（`mode: vivado`）= **32 MCP + 65 非 MCP = 97**；探针 B（standard）= **0 MCP + 63 = 63** | ✅ PASS |
| ③ 子 Agent / 队友继承 | 不继承则放弃 preset | 子 Agent 答 **32 个**（逐名核对）；`spawn_teammate`（`probe-peer`）答 **32 个** | ✅ PASS → **采用预设** |

**探针 A 的 persona 证据**（证明会话真由预设组合，不是"看起来像"）：

```
"persona_vivado": true,
"persona_lines": [
  "- Vivado is GLOBALLY SERIAL. Before any Vivado invocation, `tasklist | grep -i vivado` must be empty; ...",
  "- Every Vivado-related cwd, TEMP and TMP must be pure ASCII. Project root is `D:\\FPGA`. ...",
  "- The official AMD skills and docs target baseline 2026.1 while this machine runs Vivado 2023.1 and part `xcku060-ffva1156-2-i`. ..."
]
```
探针 B 同字段为 `"persona_vivado": false` —— 对照成立。

> ⚠️ **任务书的 `91 = 59 + 32` / `56` 是旧 profile 口径**。本机现装 profile 的基线工具数是 **63（standard）**，所以预设会话是 **63 + 32 + 2（Team Lead 追加的队友工具）= 97**。**增量 32 与任务书一致**，绝对数不同属于正常演进，不要照抄旧数字做验收。

### 2.4 一个必须记下的方法学教训：启动日志证明不了激活审计

为了给门禁 ① 找"反面证据"，我做了**负对照**：在探测 profile 的预设里插一行 `name: '@local/definitely-not-installed-plugin'`（必不存在的包），再启动。

结果：**启动日志照样零报错**（9 行全是 info）。⇒ 结论：**Electron 宿主的 stdout/stderr 不承载预设激活审计的失败信息**，靠"日志没有 error"来宣布门禁通过是**假证据**。

所以门禁 ① 的判定改为「**真会话能组合成功**」——探针 A 真的按 `mode: vivado` 组出了会话并跑通了 persona + 32 工具，这才是硬证据。`probe`/负对照的原始产物见 `.vivado-scratch/vivado-norm-2026-10-24/`。

### 2.5 落地变更清单（profile）

| 文件 | 动作 | 说明 |
|---|---|---|
| `C:\Users\***\Desktop\毕设\.dsh\bundles\vivado-preset\package.json` | **新建** | `@local/dsh-vivado-preset`，`dsh.bundle.patch=./cordis.patch.yml` |
| `…\.dsh\bundles\vivado-preset\cordis.patch.yml` | **新建**（175 行） | `preset-vivado` 声明（22 行原样 + 纪律 persona + `mcp-vivado` 行 + 三条硬约束注释） |
| `~\.dsh\profiles\desktop\package.json` | 改 2 处 | `dependencies` 加 `@local/dsh-vivado-preset: link:…`；`dsh.profile.bundles` 末尾追加同名 |
| `~\.dsh\profiles\desktop\pnpm-lock.yaml` | 由 pnpm 改 | `plugin_manager install_bundle` 自动维护（3.9 s，`application: applied`） |
| `~\.dsh\profiles\desktop\cordis.patch.yml` | **删** 全局 `mcp-vivado` insert 段（29 行）→ 换 8 行指针注释 | 现役唯一配置源 = bundle；注释里写明为什么挪、怎么回退 |

**重启前的合成树复验**（拿当前 desktop profile 的副本 + junction `node_modules`，`DSH_HOME=<临时> dsh.cmd --profile postcheck --dump-config`）：

```
1518: # == @local/dsh-vivado-preset
1519: - id: preset-vivado
1522:    id: vivado
1523:    name: Vivado
1719:      - id: mcp-vivado          ← 在 preset 作用域内，config 完整（toolCallTimeoutMs 1800000 等）
```
启动该副本：**零** `disabling profile plugin row`、**零** `target matches no row`、**零** error。rc=0。

### 2.6 回退（T1，4 步）

```powershell
cd C:\Users\***\.dsh\profiles\desktop
Copy-Item cordis.patch.yml.bak-preset-t1-20261024 cordis.patch.yml -Force   # ① 恢复全局 mcp-vivado 段
Copy-Item package.json.bak-preset-t1-20261024     package.json -Force      # ② 去掉 bundle 依赖/挂载
# ③ plugin_manager: remove_bundle '@local/dsh-vivado-preset'（或直接留 ② 的状态）
# ④ 重启 DeepSeek Harness
```
> `cordis.patch.yml.bak-preset-t1-20261024` = 装 T1 之前的原文件（含全局 mcp-vivado 段）。

---

## 3. T2 · 技能清单 + 门禁（零风险，先做）

### 3.1 `MANIFEST.json`（脚本生成，禁手写）

| 项 | 值 |
|---|---|
| 生成器 | `D:\FPGA\scripts\gen_skills_manifest.py`（新增）；`py scripts/gen_skills_manifest.py` |
| 产物 | `C:\Users\***\Desktop\毕设\.dsh\skills\MANIFEST.json`（8723 B，7 条技能） |
| `source_hash` | `f3c39b9ac2804b0fb8675eb24dc88f5d244b16d2852ad81040aa7e484c6ead11` |
| `tool_catalog` | **32** 个 `mcp__vivado__*`（从真 MCP server 探测，非写死） |
| 幂等 | 连跑两次字节一致（`49fce770…`）；hash 由 `ci-gate`、`skills-manifest` 各自独立复算 MATCH |

### 3.2 baseline 真账（D3：不许把没跑过写成跑过）

| 技能 | version | amd_doc | tested_on | status |
|---|---|---|---|---|
| `amd-doc-search` | 1.0.0（**本轮补**，原缺） | unspecified | — | ⚠️ unverified |
| `hw-ila-debug` | 1.2.2 | 2026.1 | — | ⚠️ unverified |
| `hw-vio-debug` | 1.2.2 | 2026.1 | — | ⚠️ unverified |
| `vivado-revision-control` | 1.0.0 | 2026.1 | — | ⚠️ unverified |
| **`vivado-rtl-elaboration-analysis`** | 1.0.0 | 2026.1 | **2023.1** | ✅ **verified** |
| `vivado-rtl-lint` | 1.0.0 | 2026.1 | — | ⚠️ unverified |
| `vivado-simulate-rtl` | 1.0.0 | 2025.2, 2026.1 | — | ⚠️ unverified |

**唯一 verified 是真跑出来的**：`parse_elab_messages.py` 喂真 2023.1 日志 → `Parsed 67 elaboration messages`（WARNING 29 / INFO 38），exit 0，CSV 68 行；日志头自证 `****** Vivado v2023.1 (64-bit)`（`D:\FPGA\prj\project_1\project_1.runs\synth_1\runme.log:7`）。
**主动拒掉的两个「凑整齐」机会**：`vivado-rtl-lint` 全盘无真实 lint 报告（`.rpt` 只有 utilization）→ 只验脚本可执行，**不计** verified；`amd-doc-search` 实跑成功但**不调 Vivado** → `tested_on` 留 null（否则「在 2023.1 上」是伪造）。

### 3.3 `ci_check.py` 五条校验 + 镜像门禁 + 区块门禁（250 → 848 行）

| 检查 | 判据 | 状态 |
|---|---|---|
| 7 技能清单一致性 | `name==dir` / `version` 非空 / `baseline` 四键 / `status` 合法 / `verified` 必须带 `tested_on`+`evidence` / `source_hash` 现算匹配 / 磁盘目录集合一致 | ✅ |
| 8 references 真实存在 | 扫 SKILL.md 的 md 链接 + 反引号 `references/|scripts/|examples/` 路径；占位符跳过 | ✅（实判 79 条全存在，跳过 7 条占位） |
| 9 绝对路径存在 | 只查 SKILL.md 的 Windows 绝对路径（先剥 URL） | ✅（9 条 distinct 全存在；`s://` 3 处假阳性已消） |
| 10 工具名可解析 | `mcp__vivado__X` 必须在 catalog；AMD 原名必须**同行** `→` 给出本机工具名 | ✅（6 技能合规；`vivado_doc_search` 经裁决豁免） |
| 11 镜像门禁 | 归一（**两侧** `***→***`、去 BOM、CRLF→LF）后比对 + 白名单 | ✅ 68 相等 + 15 白名单 + 0 未登记 |
| 12 生成区块一致性 | `render_agent_skills_block.py --check`（agent.md 区块 ↔ MANIFEST；docs 脱敏等价） | ✅ |

**反例验证 37/37**：技能类 17、镜像类 9、真实数据对照 5、区块类 6 —— 含「抽掉 W5 / README / FMC 引脚表 / AI-Infra 报告 任一条白名单 → 恰好 FAIL 并点名该文件」这类真实数据对照。

**检查 12 的真反例（Lead 亲手做，非声称）**：把 vault `agent.md` 区块里 `hw-ila-debug` 的版本从 `1.2.2` 改成 `9.9.9` → 重跑 `ci_check.py` 立刻抓到 **2 类**问题并给处置：

```
[1] 镜像门禁：docs/ 有 1 个文件与 vault 不一致…:
    agent.md   [kind=drift：归一后仍与 vault 不一致，未登记]
[2] 技能区块过期：vault agent.md 的 `BEGIN:skills` 区块 / docs/agent.md 脱敏镜像与 MANIFEST 不一致
    （render_agent_skills_block.py --check rc=1）。处置：跑 py D:\FPGA\scripts\render_agent_skills_block.py --write
=== CI: FAIL ===
```
跑一次 `render_agent_skills_block.py --write` 即自愈，重跑 `ci_check.py` 回到 `EXIT=0 / PASS`（已实测）。

**最终真跑**：
```
$ cd /d/FPGA && py scripts/ci_check.py
仓库体检：16388 个已跟踪文件
  [提示] 镜像门禁：docs/ 共 83 篇 .md；归一后与 vault 相等 68 篇；白名单豁免 15 篇（drift 9、docs-only 6）；未登记不一致 0 篇
  [跳过] tclsh 不可用，跳过 Tcl 语法检查
=== CI: PASS（全部检查通过）===   EXIT=0
```

### 3.4 白名单 15 条的真实构成（不是「历史遗留」四个字）

> **2026-10-24 二次收口（本节数字已过期，特此更正，原文保留作当时快照）**：当天第二轮把其中 **7 条纯目录改名漂移**按最小编辑 resync 进 `docs/`（每处 `AI-Infra系统设计/`→`GSnFPipe系统设计与指导文档/`，改后与 vault **逐字节相等**，字节差恰为 N×15）并删除登记；`追踪_cross_短期待办_2026-10-10.md` 经复算**不是改名**（docs 侧有意去链接，目标未镜像，强改会引入 2 个断链）⇒ 保留豁免并重写 reason。**现白名单 8 条**（drift 2 = `README.md` + `追踪…`；docs-only 6），门禁提示为「相等 **75** / 豁免 **8**」。下面 15 条的分析（为何不是垃圾桶、如何复核 reason）仍然成立。

- **vault 目录改名类 = 8 个文件 / 10 处 wiki 链接**：`GSnFPipe系统设计与指导文档/` ↔ docs `AI-Infra系统设计/`，8 个文件全部「仅此差异、其余逐行相同」。另 `README.md` 里 2 处同名引用（该文件整篇结构不同，仓库侧 2026-10-17 重建过）→ **全库合计 12 处目录名引用**。
- ~~真内容漂移 1 条~~ → **已销账（2026-10-24 用户指示后执行）**：`操作文档/阶段三_prj10_W5随机读上板验证单_2026-10-07.md` 原来 docs 停在 10-07 原文（vault 已于 10-09/10-10 更新遗留条）。已按 vault 新版**重新脱敏同步进 docs/** 并**删除该白名单条目**（16→15，drift 10→9），归一后两版逐字节相等。备份 `…/W5…md.bak-20261024` 已移出 `docs/` 存到 `.vivado-scratch/`。
- **docs-only 6 条**：4 条是同内容换名/换位（`导览_…2026-10-22`→vault `汇报/`、`汇报_…需求对齐`→`汇报/`、`规划_cross_AI-Infra系统设计报告`→`GSnFPipe系统设计与指导文档/…`、`里程碑_prj1_M1`→`归档/…`，实测归一后 diff=0）；2 条是**仓库侧原创**（`参考_cross_FMC_4SFP_GTH引脚表`、`阶段一_prj1_Vivado2026.1交接`，vault 全库无对应）。

### 3.5 对 SPEC 的 4 处偏离（全部有实测依据，Lead 已批准）

| # | 偏离 | 为什么（实测） |
|---|---|---|
| 1 | 脱敏归一改为**两侧对称**替换 `***→***` | 只替换 vault 侧会假 FAIL：docs 里另有 5 篇自身含 `***`，其中 4 篇与 vault **逐字节相同**（`复现_prj9_指南`、`上板操作优先级清单`、`W4两级内存联调`、`B2软核J3上板验证单`） |
| 2 | `README.md` 进白名单而非豁免 | SPEC+D1 优先；这样 5 个子目录 `README.md` 仍受门禁（当前均字节相同） |
| 3 | 检查 10-2 从「至少一行 `→`」收紧为「**同一行**含 AMD 原名且在 `→` 右侧给本机工具名」 | 反例实测：只删 `vivado-rtl-lint` 的映射行不会 FAIL —— 它 `:18` 说明行有 `→` 且右侧偶然出现 `start_session`，白送通过 |
| 4 | `vivado_doc_search` 从「必须映射」名单豁免 | 它是**另一个 server** 的工具（`mcp__amd_doc_search__vivado_doc_search`，要重启 `dsh web` 才有），`mcp_vivado` 里本就没有对应物；技能已写「实际调用 `doc_search.py`」。判据原意是「防调不存在的工具名」，不是「每个 AMD 名词必须有 MCP 同义词」 |

---

## 4. T3 · `agent.md` 收口（只加不改写）

| 改动 | 内容 |
|---|---|
| 顶部**场景路由表**（14 行） | 场景 → 文件/skill → **是否需要 vivado-mcp**；含「忘了切预设先查预设」 |
| 新增「★ Vivado 会话预设」小节 | 32 工具不再全局挂载、默认 standard 没有、bundle 在哪、改它要重启 |
| 「技能清单」改为 `BEGIN:skills` 生成区块 | 源 = MANIFEST；渲染器 `D:\FPGA\scripts\render_agent_skills_block.py`；`--check` 已进 CI（检查 12） |
| 镜像口径段改为「CI 门禁（第 11 项）」 | 说明归一规则、白名单机制、现状 68/15/0、白名单不许写空话 |
| **未动** | `AGENTS.md` 与 `PITFALLS.md` 正文（按任务书红线） |

### 4.1 镜像同步是脚本一步到位的

`render_agent_skills_block.py --write` 做两件事：① 刷新 vault `agent.md` 的区块；② **把 vault `agent.md` 按 `***→***` 脱敏写成 `D:\FPGA\docs\agent.md`**（落实 AGENTS.md 十二节「同步后必须重新脱敏」，杜绝手工复制带来的泄露风险）。

```
$ py D:\FPGA\scripts\render_agent_skills_block.py --check
[PASS] agent.md 的 BEGIN:skills 区块与 MANIFEST 一致
[PASS] docs/agent.md 与 vault agent.md 脱敏等价     rc=0
```

> 一个**真实闭环事故**（好证据）：我改完 vault `agent.md` 后没同步 docs，`ci-gate` 的镜像门禁立刻 `FAIL` 并点名 `agent.md`；补跑渲染器后恢复 PASS（现 68 相等 / 0 未登记） —— 门禁确实在工作，不是我口头声称它工作。

### 4.2 两条运维注意（实测踩到的）

1. **`--write` 不要与 `ci_check.py` 并发跑**。渲染是「先写 vault、再写 docs」两步，两文件 mtime 差 1 ms；CI 恰好跨在窗口上会读到「vault 新版 + docs 旧版」→ 正确报 FAIL。实测复现过一次，写完复跑即 PASS（不是缺陷，是判据正常工作）。
2. **`docs/` 里不放备份**。渲染器早期版本会把 `docs/agent.md.bak-<日期>` 写进 `docs/`，污染「已发布快照」目录（文件计数 16388→16389）。已改为**不备份镜像侧**——`docs/agent.md` 是 100% 派生物（= `sanitize(vault agent.md)`）且在 git 里，备份 vault 侧即可。

---

## 5. 未做 / 需你决定

| # | 事项 | 说明 |
|---|---|---|
| 1 | **重启宿主** | 唯一必做动作。重启后新建会话才会有 `Vivado` 预设。✅ **`AGENTS.md` 已按用户 2026-10-24 指示回改**：§6b 的 `mcp__vivado__*` 现状行改为「预设携带、默认标准会话无工具」，并新增「Vivado 会话预设」一行；§十二 补检查 7–12 并把「只提示」改成门禁口径（备份 `AGENTS.md.bak-20261024b`） |
| 2 | ~~`W5随机读上板验证单` 真内容漂移~~ | ✅ **已执行**：重新脱敏同步进 `docs/` + 删除该白名单条目（见 §3.4） |
| 3 | 远程 CI 不校验技能 | 按 D2 技能留在 vault、远程 ubuntu 够不到 → 检查 7–12 在 GitHub Actions 里是 SKIP（只剩检查 1–6 真跑）。要真跑就得把技能同步进仓库（D2 的 B 方案） |
| 4 | 11 个 MCP 工具仍未触达 | 与上一轮相同（需硬件/长跑）：`program_device`、`run_implementation`、`safe_tcl`、`set_wave_analog/zoom`、`verify_io_placement_tool`、`check_bitstream_readiness`、`generate_bitstream`、`get_next_suggestion`、`get_pre_commit_summary`、`get_cdc_report` |
| 5 | `ci_check.py` 的既有告警 | 运行时 stderr 有一条 `Exception in thread Thread-1 … UnicodeDecodeError: 'gbk' codec`（来自 `tracked_files()` 的 `subprocess.run(text=True)`）。**改动前就存在**、不影响退出码与判据，未顺手改（不在本轮范围）。真实影响：它让 `tracked_files()` 退回 `rglob` 全盘扫描，所以「16388 个已跟踪文件」**远大于 git 真实跟踪数**——检查 1–6 实际也扫了未跟踪文件 |
| 6 | ~~`D:\FPGA` 未 commit~~ | ✅ **已提交并推送（2026-10-24 13:41，用户指示「整理工作树并推送」）**：两个提交 `3f2165e`（规范化）+ `0ef954f`（prj11 10-22 证据归档），`dd256f3..0ef954f master -> master`，**远程 GitHub Actions CI #114 = success**，本地 HEAD == 远端 master，工作树干净 |

---

## 6. 备份清单（每处改动都可回退）

| 文件 | 备份 |
|---|---|
| `~\.dsh\profiles\desktop\cordis.patch.yml` | `.bak-preset-t1-20261024`（T1 前）、`.bak-t1-cleanup-20261024`（清理前） |
| `~\.dsh\profiles\desktop\package.json` | `.bak-preset-t1-20261024` |
| `D:\FPGA\scripts\ci_check.py` | `.bak-20261024`（10002 B 原文件） |
| `D:\FPGA\docs\agent.md` | `.bak-20261024` |
| `C:\Users\***\Desktop\毕设\agent.md` | `.bak-20261024` |
| 7 × `SKILL.md` | `SKILL.md.bak-20261024` / `…-20261024b`；`amd-doc-search` 另有 `.bak-20261024c` |
| `D:\FPGA\AGENTS.md` | `.bak-20261024b`（本轮改 §6b/§十二 之前） |
| `D:\FPGA\docs\操作文档\阶段三_prj10_W5…md` | `.bak-20261024`（同步前的 docs 旧版，已移出 docs/ 存 `.vivado-scratch/vivado-norm-2026-10-24/`） |

## 7. 复现命令

```powershell
$env:PYTHONUTF8 = 1
cd D:\FPGA
py scripts\gen_skills_manifest.py                 # 重生成 MANIFEST（禁手写）
py scripts\render_agent_skills_block.py --check    # 校验 agent.md 区块 + 镜像脱敏等价
py scripts\ci_check.py                             # 全套门禁（只认退出码 0）
# T1 三道门禁复跑：派一张 mode=vivado 的 task_board 卡片，让它数自己工具清单里的 mcp__vivado__*，
# 并让它的 subagent / teammate 各答一次（模板见 .vivado-scratch\vivado-norm-2026-10-24\probe_A.json）
```

## 8. 证据索引

| 文件 | 内容 |
|---|---|
| `.vivado-scratch\vivado-norm-2026-10-24\SPEC.md` | 本轮技术契约（判定细则、写作用域、红线） |
| `…\shipped_standard.patch.yml` | 从 `app.asar` 原样导出的出厂 `standard` 预设（sha256 `0d398d2a…`） |
| `…\build_vivado_preset_patch.py` / `extract_asar_file.py` / `make_probe_profile.py` | 组装与隔离探测脚本 |
| `…\probe_A.json` / `probe_B.json` | 门禁 ②③ 的原始测量（含 persona 逐字摘录、子 Agent/队友原话） |
| `…\report_T2A.md` / `report_T2B.md` | 两个队友的完整交付报告（baseline 依据、白名单逐条理由、31 个反例） |
| `D:\FPGA\scripts\mirror_allowlist.json` | 镜像白名单 15 条（每条带 kind/reason/since） |

---

## 9. 提交与推送记录（2026-10-24 13:38–13:42，用户指示「整理工作树并推送」）

工作树整理口径：**规范化成果**与**历史遗留证据**分两个提交，避免把「改规范」和「补归档」混成一锅。

| # | 提交 | 内容 | 规模 |
|---|---|---|---|
| 1 | `3f2165e` `ci+docs: Vivado 环境 DSH 规范化（会话预设 / 技能清单门禁 / 镜像门禁）` | 新增 `scripts/gen_skills_manifest.py` / `render_agent_skills_block.py` / `mirror_allowlist.json`；改 `scripts/ci_check.py`（+619/−21）、`AGENTS.md`（+20/−8）、`docs/agent.md`、`docs/操作文档/…W5…md`、`.gitignore`、`PITFALLS.md` | 9 files, +1191/−34 |
| 2 | `0ef954f` `prj11: 补归档 2026-10-22 上板验证 ILA CSV（S0–S11 验收证据）` | `evidence_2026-10-22/` 与 `evidence_2026-10-19/` 里 8 个未跟踪 ILA CSV（10-22 两次抓取） | 8 files, +12304 |

- 推送：`dd256f3..0ef954f  master -> master`（SSH 通道）。
- **远程 CI：GitHub Actions run #114 = `completed/success`**（<https://github.com/chemmy-11/EIF/actions/runs/40067217203>）—— 远程只跑检查 1–6，7–12 因无 vault 自动 SKIP，与设计一致。
- 提交后校验：`git status` 干净；本地 `HEAD` == `git ls-remote origin master` = `0ef954f49…`。
- 未入库但有意的：`*.recomposed.jsonl`、运行日志、`*.bak-*`（.gitignore 覆盖）、以及未跟踪的 `evidence_2026-10-22/*.log`。
- 遗留待你定：`evidence_2026-10-19/` 里那 4 个 10-22 抓取的 CSV 是**已知目录错位**（结论 §5.4/§8.5），本轮按原样归档、未移动；要归位我再做一次 `git mv`。
