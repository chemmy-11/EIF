# dsh-vivado-team-link

**dsh-vivado 的可选协作插件**：把 PC1↔PC2 两台工作站做成"同等权限、靠约定协作"的组员对，而不是主机/受控端。

- 独立 bundle 片段，**默认不进入 Vivado 预设**，只有你显式安装才生效。
- **不改 dsh-vivado 的任何生成文件**（`cordis.patch.yml` / `install.ps1` / `packages/` / `patches/` / `skills/` / `tools/` / `templates/` / `config.yml`）；安装器会自证这一点（前后 SHA256 全量比对）。
- 与 kit 职责不重叠：仿真、构建、ILA 解析仍走 `mcp__vivado__*` + kit 技能；本插件只提供**协作层**（通道、口令、证据搬运、回退）。

## 1. 角色定位

| | PC1 | PC2 |
|---|---|---|
| 角色 | lead | 板 B 侧实物负责人 |
| 权限 | full access | **同等 full access**（不降权） |
| 管什么 | 优先级、共享仓提交、构建与烧录窗口、判据裁决 | 板 B 的烧录/串口/ILA/抓包/证据，板侧范围内自主行动，可提方案 |
| 不该做什么 | 不替 PC2 决定板侧细节 | 不擅自改共享仓判据、不抢构建窗口 |

跨机**只交换决策与证据**，不互相 micromanage。约束力来自口令与审计，不来自降权 —— 所以"约定"必须写在 `skills/prj-team-collab/SKILL.md` 里，并被两台机器同时加载。

## 2. 目录

```
team-link/                 # EIF 仓内路径（本插件不并入 dsh-vivado kit）
  plugin.json              # 本插件清单（可选安装、端口、写入范围、回滚方式）
  package.json             # DSH bundle 描述符（dsh.bundle.patch -> cordis.patch.yml）
  lib/
    index.js               # 宿主半边：导出 name / Config / apply，物化 config.json、把凭据写进 token 文件
    client.js              # 浏览器半边：GUI 配置卡片（手写 bundle，注册进 plugins.row.config；见 §4.7）
  cordis.patch.yml.tmpl    # 由 install.ps1 渲染成 cordis.patch.yml（注入两条：team-link + mcp-team-link）
  cordis.patch.yml         # 渲染产物（install 生成，uninstall -Purge 删除）
  install.ps1              # 注册 bundle + 拷 skill + 写配置 + kit 哈希自证
  uninstall.ps1            # 完整回滚（摘注册 / 删 skill / 可选清产物 / 复核哈希）
  server/
    team-link-a2a.mjs      # A2A：AgentCard + message/send + tasks/get（HTTP，Bearer）
    team-link-mcp.mjs      # MCP：list_roots / read_file / write_file / sha256_file / collab_status
                           #      双传输 —— stdio（DSH 插件用）+ http（跨机 + 自环用）
  client/
    a2a-selfloop.mjs       # A2A 自环验证
    mcp-selfloop.mjs       # MCP 自环验证（含越权与 SHA256 校验）
  tools/
    collab_status.ps1      # 通道/端口/时钟偏移/回退状态（通道断 -> 明确提示转 issue 轮询并写日志）
    pc1_pc2_ping.ps1       # 对端探测（含 192.168.1.x 网段守卫，防连错机器）
    evidence_pull.ps1      # 走 MCP 拉对端证据并本地复核 SHA256
    apply-selftest.mjs     # 宿主半边离线自测（在临时目录里跑 apply()，不碰真 state/）
  skills/
    prj-team-collab/SKILL.md   # 角色 / 发令回报格式 / 证据目录 / 硬件约定 / issue 回退
    team-link-setup/         # 装机与换网段（scripts/tl-state.ps1 诊断、tl-sync.ps1 同步地址）
    team-link-ops/           # 工作流（scripts/tl-recv.ps1 原子收件、tl-say 回复、tl-watch/tl-wait 兼容保留）
  templates/
    PC2_上线清单.md        # PC2 上线 checklist（本插件最终交付物之一）
    AgentCard.template.json
    daily-audit-issue.md
  state/                   # 生成物（.gitignore 忽略）
    config.example.json    #   schema v2 模板：进包，去作者机痕迹，roots 只有 state 一条
    config.json            #   生成物：install.ps1 首生成，此后由 lib/index.js 的 apply() 物化维护
    *.token                #   生成物：入站 a2a/mcp、出站 peer-a2a/peer-mcp（服务端启动时读）
  logs/                    # 运行日志（不进 git）
```

## 3. 安装 / 卸载 / 回滚

### 3.1 从哪里拿到它

本插件随 **EIF 仓库**分发（只服务 A 组 PC 协作，不并入 dsh-vivado kit）：

```powershell
# A) 推荐：clone 到 kit 的 optional 目录 —— 保留 kit 完整性自证
git clone --depth 1 https://github.com/chemmy-11/EIF.git $env:TEMP\EIF
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dsh\bundles\dsh-vivado\optional" | Out-Null
Copy-Item "$env:TEMP\EIF\team-link" "$env:USERPROFILE\.dsh\bundles\dsh-vivado\optional\team-link" -Recurse

# B) 就地运行（不复制）：installer 会打印 WARN 并**跳过 kit 哈希自证**，其余照常
git clone --depth 1 https://github.com/chemmy-11/EIF.git D:\EIF
powershell -NoProfile -File D:\EIF\team-link\install.ps1 -Profile desktop
```

> 布局说明：`install.ps1` 只有在 **`<kit>\optional\team-link`** 布局下才做 kit 全量 SHA256 自证；
> 其它位置会跳过该项并 WARN（因为此时「上层目录」不是 kit，硬哈希整盘既慢又无意义）。两种布局都能正常安装。


```powershell
# 安装（默认注册到 desktop profile；-RegisterMode Manual 为完全离线等价路径）
powershell -NoProfile -File install.ps1 -Profile desktop
powershell -NoProfile -File install.ps1 -Profile desktop -RegisterMode Manual   # 不调用 pnpm/dsh CLI

# 状态
powershell -NoProfile -File tools\collab_status.ps1

# 卸载（保留源码与日志，摘除注册与 skill）
powershell -NoProfile -File uninstall.ps1 -Profile desktop

# 卸载并清理生成物
powershell -NoProfile -File uninstall.ps1 -Profile desktop -Purge
```

安装器做了什么，按顺序：

1. 预检必需文件 + 解析 node(>=20)；
2. 对 **kit 全部文件（排除 `optional/`）** 记录 SHA256 基线 → `state/kit-manifest.before.sha256`；
3. 跑 `node server/team-link-mcp.mjs --selftest`，失败就中止，**绝不留下半装状态**；
4. 生成 `state/a2a.token`、`state/mcp.token`（首次生成后复用）；
5. 生成 `state/config.json`（角色、端口、授权根目录、对端占位、回退参数）；此后这份文件由宿主半边 `apply()` 物化维护（见 §4.4），install 只保证首版可用；
6. 渲染 `cordis.patch.yml`（**两条**：先 `team-link` 宿主插件，再 `mcp-team-link` stdio 客户端；顺序不能换，见 §4.2）；
7. 拷 `skills/prj-team-collab` → `<DshHome>\skills\prj-team-collab`，并记指纹；
7.1 建 `node_modules/@deepseek-ai/schemastery` junction（指向 profile 里的那份）——本插件按 `link:` 注册，`lib/index.js` 靠这个确定性锚点解析 schemastery；拿不到时 `Config` 降级为 `undefined`，插件仍按内置默认值启动（`node_modules/` 已进 `.gitignore`，不入仓）；
8. 注册 bundle：`dsh plugin --profile <p> add link:<bundleDir>`（= pnpm link: + 写入 `dsh.profile.bundles`），并校验"条目在 + node_modules 链接在"；
9. 重算 kit SHA256 → **必须与基线完全一致**，否则 FAIL 并让你看差异清单。

**生效需要重启宿主**（Electron 下 dsh-hmr 不生效）。重启后新会话里出现 `mcp__team_link__*` 工具与宿主工具 `team_link_setup`。

回滚语义：`uninstall.ps1` 摘除注册 → 校验并删除 skill 副本（若你改过 skill 文件，默认**不删**并提示，需 `-Force`）→ 残留检查 → 可选清产物 → 再次复核 kit 哈希。`-UnregisterMode Restore` 会用安装前备份整体还原 `package.json`（仅适用于"刚装就回滚"，否则会丢掉之后新装的插件）。

## 4. 设置与配置（**有 GUI 面板了**：设置 → 插件 → 本行 → 配置）

### 4.1 结论先行

配置有两个入口，改的是**同一份** profile 配置：

1. **设置里的一级分区（主入口）**：`设置 → PC 协作` —— 和「通用设置」「模型」「内置插件」**同级**，
   一次点击就到，不藏在插件页里。面板能改角色 / 机器名 / A2A·MCP 的 host 与 port / 对端名字与地址 /
   回退仓库与标签与轮询间隔 / 日志目录 / 授权根。**它不收 token 值**（原因见 §4.5），只显示 token 的引用名与文件路径。
2. **插件页里的行配置页（第二入口）**：`设置 → 插件 → 已安装的插件 → dsh-vivado-team-link → 行 team-link → 配置`。
   同一张表单，走的是宿主递 `form` 的 keyed slot。
3. **profile 配置项**（等价底稿）：`cordis.patch.yml` 的 `config:` 块。面板保存的也是这里 —— 宿主会把改动的字段
   写成一条 `- id: team-link` 的覆盖项，所以「GUI 改」与「手改 YAML」不会打架。

GUI 面板**不是宿主自动生成的**：DSH 0.2.2-rc.1 没有「按 Config Schema 自动渲染原生表单」这层 UI，面板只能由插件
自己占一个 keyed slot。四条证据（均已核对）：

| # | 证据 | 说明 |
|---|---|---|
| 1 | `@deepseek-ai/dsh-client-ui-settings/README.zh.md` 自述「**自身不渲染任何界面**」 | 设置分区本身不含任何按 schema 生成的控件 |
| 2 | 设置→插件的配置页是 **keyed slot `plugins.row.config`**；全 asar 只有 owner 侧的 `renderSlot` 与文档示例，**没有通用 occupant** | 宿主不会"看到一个 Config 就替你画表单" |
| 3 | `dsh-client-ui-settings-plugins/lib/client.js`：「插件配置页住在各自的伴生包里，本分区只拥有导航项和 tab 外壳」 | 面板必须由插件自己注册 |
| 4 | `@linxin666/*` 每个设置面板都是各包自带的 `*SettingsCard.tsx`（实例：`@linxin666/dsh-agents/src/client/AgentsSettingsCard.tsx`） | 现状是"谁有面板谁自己写" |

所以本插件自带 `lib/client.js`（**手写 bundle + `React.createElement`，无 JSX、无构建步骤**），
通过 `package.json` 的 `dsh.client` + `exports["./client"]` 交给宿主，注册进 `plugins.row.config`
（键 `<包名>#<行 id>` = `dsh-vivado-team-link#team-link`）。实现细节与踩过的坑见 §4.7。

旁证：**schemastery 3.19.0** 没有 secret / password 类型。所以即使哪天宿主开始自动渲染表单，
密文输入框在 schema 层也没有承载物 —— token 值永远不走配置。落地方式是：**配置项收非密参数**，
**宿主工具 `team_link_setup` 收 token 值**（值只进凭据存储，见 §4.5）。

### 4.2 两半结构：宿主插件 + MCP 客户端

`cordis.patch.yml` 从一行变**两行**（`install.ps1` 从模板渲染，`uninstall.ps1` 整体删除）：

| 顺序 | id | name | 职责 |
|---|---|---|---|
| 1 | `team-link` | `dsh-vivado-team-link`（本插件，`lib/index.js`） | 读 profile 配置 → **物化** `<bundle>/state/config.json`；再把凭据存储里的引用值写成 `state/*.token` |
| 2 | `mcp-team-link` | `@deepseek-ai/dsh-mcp-client` | stdio 挂 MCP 服务端；`serverName` 仍是 `team_link`，工具名仍是 `mcp__team_link__*` |

**顺序有意义**：`team-link` 先把 `config.json` 物化到磁盘，`mcp-team-link` 才读得到它（通过 `TEAM_LINK_CONFIG` 环境变量指过去）。顺序反了会让服务端在配置缺失/上一轮配置的情况下起（`failOnStartupError: false` 时表现为"静默没有工具"）。
`apply()` 内部也是按这个顺序做的：**同步**物化 `config.json` → 注册 `team_link_setup` → **异步（不 await）**同步 token 文件，不让 profile 启动等 IO。

### 4.3 Config 字段（全部非密）

字段落在 profile 里本插件那一行的 `config:` 块。`install.ps1` 渲染 `cordis.patch.yml` 时默认只写下面这些（值来自 `-Role` / `-A2aPort` / `-McpPort` 与 bundle 路径）：

```yaml
- insert:
    - id: team-link
      name: 'dsh-vivado-team-link'
      config:
        role: 'pc1'
        a2a:
          host: 127.0.0.1          # 跨机时改成实际网卡地址（WLAN / 第二网卡 / Tailscale，见 §6）
          port: 7310
          tokenFile: '<bundle>/state/a2a.token'
          tokenRef: TEAM_LINK_A2A_TOKEN
        mcp:
          host: 127.0.0.1
          port: 18790
          tokenFile: '<bundle>/state/mcp.token'
          tokenRef: TEAM_LINK_MCP_TOKEN
        peer:
          name: pc2
          a2a:
            tokenFile: '<bundle>/state/peer-a2a.token'
            tokenRef: TEAM_LINK_PEER_A2A_TOKEN
          mcp:
            tokenFile: '<bundle>/state/peer-mcp.token'
            tokenRef: TEAM_LINK_PEER_MCP_TOKEN
        # roots 故意不写：配置项不表态 -> 沿用 state\config.json 既有 roots（升级不丢根）
        # 要加根就解开并**写全**（一旦写就是整表替换）：
        # roots:
        #   - { id: state, path: '<bundle>/state', mode: rw }
        #   - { id: evidence, path: 'D:/your/evidence', mode: rw }
        logDir: logs
```

渲染模板**没写**、需要时手动补的三项：`fallback.repo`（回退轮询的仓库；首版 `config.json` 里通常已有，没写配置项时不会被覆盖）、`peer.a2aUrl` / `peer.mcpUrl`（跨机出站要用）、以及上面注释里的 `roots`（要改授权根才写）。

> **roots 的继承规则（升级不丢根）**：配置项没写 `roots`（或写了空数组）→ 沿用磁盘既有 `roots`；
> 写了**非空** `roots` → **整表替换**。所以升级时不要为了"补一条 state 根"把 `roots` 写进配置项 ——
> 那会把 `config.json` 里的 `evidence` / `delivery` 根一起顶掉。真写了就必须把要用的根全部列出来。

| 字段 | 默认值 | 说明 |
|---|---|---|
| `role` | `pc1` | `pc1` / `pc2` |
| `machine` | `role` 的大写（如 `PC1`） | 显示名，进日志与 `collab_status` 回显 |
| `a2a.host` | `127.0.0.1` | A2A 绑定地址；本轮默认不开外网监听 |
| `a2a.port` | `7310` | |
| `a2a.tokenFile` | `<bundle>/state/a2a.token` | 入站 token 文件（只有路径，没有值） |
| `a2a.tokenRef` | `TEAM_LINK_A2A_TOKEN` | 凭据存储里的引用名（见 §4.5） |
| `mcp.host` | `127.0.0.1` | |
| `mcp.port` | `18790` | |
| `mcp.tokenFile` | `<bundle>/state/mcp.token` | 入站 token 文件 |
| `mcp.tokenRef` | `TEAM_LINK_MCP_TOKEN` | |
| `peer.name` | `pc2` | 对端名字 |
| `peer.a2aUrl` | 空串 | 对端 A2A 地址（出站） |
| `peer.mcpUrl` | 空串 | 对端 MCP 地址（出站） |
| `peer.a2a.tokenFile` | `<bundle>/state/peer-a2a.token` | **对端**的 token，出站用 |
| `peer.a2a.tokenRef` | `TEAM_LINK_PEER_A2A_TOKEN` | |
| `peer.mcp.tokenFile` | `<bundle>/state/peer-mcp.token` | **对端**的 token，出站用 |
| `peer.mcp.tokenRef` | `TEAM_LINK_PEER_MCP_TOKEN` | |
| `roots[]` | 空数组 = 不表态（沿用磁盘既有；磁盘也没有才用 `[{ id: "state", path: "<bundle>/state", mode: "rw" }]`） | 授权根目录，元素为 `{ id, path, mode }`；`list_roots` 暴露的就是这份清单。**写了就整表替换** |
| `fallback.repo` | 空串（配置项不写则沿用 `config.json` 既有值） | 回退 issue 轮询的仓库 |
| `fallback.issueLabel` | `collab-audit` | |
| `fallback.pollSeconds` | `900` | |
| `logDir` | `logs` | 相对 `<bundle>` 或绝对路径 |

`config.json` 里还有一批 **Config 不拥有的键**，物化时**原样保留**、不由配置项覆盖：`version`、`a2a.path`、`a2a.agentCardPath`、`a2a.bindSelfLoop`、`mcp.path`、`peer.wlan`、`peer.tailscale`、`peer.note`、`fallback.mode`、`evidenceDir`。
（这也是"在配置项里少写几个字段"不会把 `config.json` 里的历史字段抹掉的原因。）

### 4.4 `apply(ctx, config)` 的确定行为

- **物化**：把配置写成 `<bundle>/state/config.json`（schema v2，`version` 恒为 `2`）。服务端与三个运维脚本（`tools/collab_status.ps1`、`tools/evidence_pull.ps1`、`tools/pc1_pc2_ping.ps1`）读的都是这**一个**文件。
- **以磁盘为底 + 三级优先级**：每个托管字段的取值顺序是 **配置项 → 磁盘既有值 → 默认值**。
  空串 / 缺省一律视为"配置项没表态"，落到磁盘值（这一条是回归保护：Config 里每个字段都带
  `.default()`，"没写"与"写了默认值"在 `apply()` 里无法区分，直接覆盖会把磁盘上手配的
  `fallback.repo` 冲成空串——曾经的 bug，`tools/apply-selftest.mjs` 场景 3 已锁）。
- **roots 的合并规则**（容易踩）：Config 里给了**非空** `roots` → **整表替换**；没给 → 沿用磁盘既有 `roots`；磁盘也没有 → 默认 `state` 一条。
- **可重建**：`config.json` 不存在 / 被删 → 下次 `apply()` 按默认值重建。
- **绝不 throw**：任何内部异常都降级为日志。物化失败会用**纯默认值兜底重建一次**，再失败就放弃物化、profile 照常启动。理由很直接——宿主插件抛异常会拖垮**整个 profile 启动**，一个协作层没有这个权力；宁可协作层静默退化，也不让 DSH 起不来。
- **token 物化**：见 §4.5，`apply()` 只写文件、不回显值；这一步是异步的（不 await），失败也不影响启动。

### 4.5 token 值怎么进来：凭据存储 → token 文件

值只走一条单向链路，配置与表单**永远只有路径和引用名**：

```
team_link_setup(action=set-token, value=…)
        └→ ~/.dsh/.credentials.yaml 的 refs: 段（键 = 引用名，形如 TEAM_LINK_A2A_TOKEN）
apply()  └→ ctx.get('credentials') 读引用 → 写 <tokenFile>（state/a2a.token 等，服务端启动时读）
```

- 引用未配置时，`apply()` **保持既有 token 文件不动**（不删、不清空）。所以 `install.ps1` 生成的自签 token 不会被物化冲掉。
- **`set-token` 当场落盘**：写进凭据存储后，同一次工具调用里就把值物化到 `<tokenFile>`（不必等重启才写文件）。但运行中的 A2A/MCP 服务是**启动时**读 token 的，要让新值在通道上生效**仍需重启宿主**。
- 四条 `refs:` 键默认是：`TEAM_LINK_A2A_TOKEN`、`TEAM_LINK_MCP_TOKEN`、`TEAM_LINK_PEER_A2A_TOKEN`、`TEAM_LINK_PEER_MCP_TOKEN`（名字可在 §4.3 的 `*.tokenRef` 里改；引用名须是 `[A-Za-z_][A-Za-z0-9_]*` 形状）。
- 部署不提供凭据存储时（`ctx.get('credentials')` 拿不到），`team_link_setup` 会报不可用并提示降级办法：把 token 手工放进 `state/*.token`。

`team_link_setup` 用法（**这是模型工具调用，不是 PowerShell 命令**）：

```
team_link_setup { action: "status" }
team_link_setup { action: "set-token", token: "a2a",      value: "<本机自签的 32 字节 hex>" }
team_link_setup { action: "set-token", token: "peer-a2a", value: "<对端交给你的 hex>" }
team_link_setup { action: "clear-token", token: "peer-mcp" }
```

| 参数 | 取值 |
|---|---|
| `action` | `status` / `set-token` / `clear-token` |
| `token` | `a2a` / `mcp`（本机**入站**，校验来客）· `peer-a2a` / `peer-mcp`（对端**出站**，调用对端） |
| `value` | 仅 `set-token` 用；不能为空、不能含换行；只进凭据存储，**工具永不返回值** |

行为约定：

- **只说布尔事实**：`status` 逐槽位报 `credential=configured|absent`、`file=present(<N>B)|MISSING`，外加 `config.json=present|MISSING`、`凭据存储=available|unavailable`；**没有任何一档会回显 token 值**。
- `clear-token` 只删引用，**保留**既有 token 文件（由人决定要不要删）。
- 任何一层都**不打印 token 值**，只报存在性：
  - `tools/collab_status.ps1` 会多打一行 `token : a2a=present(65B) mcp=present(65B) peer-a2a=MISSING peer-mcp=MISSING`
    （只看文件长度，**不读内容**；`-Json` 时同一信息在 `tokens` 字段里）；
  - `team_link_setup { action: "status" }` 给出同一组布尔事实，外加凭据存储 side 的 `configured/absent`。

### 4.6 为什么是"配置项 + 工具"而不是"表单"

非密参数走配置项、密文走凭据存储，是本版本唯一能落地的组合：宿主没有自动表单（§4.1 的四条证据），schemastery 3.19.0 也没有 secret 类型；硬把明文 token 塞进 `config:`，等于同时污染 profile 配置、`*.bak-*` 备份和卸载回滚链。`team_link_setup` 对标 `task_board_github_setup`：值只进凭据存储，工具自己绝不返回值。

### 4.7 GUI：一级分区 + 行配置页，怎么做的、踩过什么坑

`lib/client.js` 是一个**手写的客户端 bundle**（不引入构建链）：

```js
window.__ModuleLoader__.load({
  id: 'dsh-vivado-team-link',
  factory: (require) => {
    const React = require('react')            // 平台冻结模块表里的 react
    // …注册卡片…
    return { apply, inject: ['slots', 'configForms'] }
  },
})
```

**两个入口、一份实现**：

- **一级分区** `settings.section`：`{ name, id: 'team-link', order: 20, label: 'PC 协作' }`。
  order 与「通用设置」0 /「模型」10 /「内置插件」15 同一序列，所以它就是一个**一级导航项**。
  一级分区**拿不到**宿主递来的表单对象，必须自己 `ctx.configForms.get(<entryId>)` 取 ——
  官方页面（模型 / 网页搜索）也是这么干的。entryId 就是本行的 id `team-link`；为稳妥起见
  按 `team-link` → `<包名>#team-link` → `include:team-link` → `<包名>` 依次在 `configForms.describe()`
  的 namespaces 里找第一个命中的。
- **行配置页** `plugins.row.config`（键 `<包名>#<行 id>`）：宿主直接把 `form` 当 prop 递进来。
  两个入口渲染的是同一个 `TeamLinkForm`，只是「怎么拿到 form」不同。

要点（每条都是实测结论，不是推测）：

- **声明**：`package.json` 的 `dsh.client: { platform: 'web' }` + `exports["./client"]`。宿主的
  `dsh-client-modules` 据此把它编进启动图（`/plugins/??…,dsh-vivado-team-link/client.js&rev=…`）。
  缺了 `lib/client.js` 会让该行**激活失败**并报"缺构建产物"。
- **占位**：`ctx.slots.inject('plugins.row.config', …)` → `ctx.slots.register({ name, key }, Card)`，
  key 必须是 `<包名>#<行 id>`（本插件 `dsh-vivado-team-link#team-link`）。注册成功后，行标题变成
  可点按钮（`aria-label="配置 <包名>"`），点进去就是本卡片。
- **props**：`{ view, form }`。`view === 'summary'` 渲染列表摘要；`view === 'page'` 渲染整页。
  `form.state = { status, value, base, user, revision, writable }`，
  `form.mutate(ops, revision)`，`ops` 形如 `{ op: 'set', path: ['a2a','port'], value: 7311 }`（原子提交，冲突返回 `false`）。
- **宿主只 serve `.volatile()` 字段**：`form.state.value` 里只有标了 volatile 的字段。这条坑过一次 ——
  `tokenRef/tokenFile` 一开始没标，卡片里永远显示"未设引用名"。现在 Config 里除 `fallback.mode` 外全部 volatile。
- **绝不裸调 `ctx.get('远程服务')`**：未 inject 的服务会**抛错**，而 slot 里的异常会把整张卡片崩掉
  （实测报错 `cannot get property "remote.credentials" without inject`，面板全白）。所以卡片
  **不读凭据状态** —— 那个"已配置/未配置"徽章要 `remote.credentials` 这种非必需服务，不值得为它赌面板挂不挂载；
  权威状态请用 `team_link_setup {action:"status"}`（只报存在性、不返回值）。
- **保存后要有反应**：宿主对 volatile 字段只发 `loader/volatile-update`（**不重挂插件**），
  所以 `lib/index.js` 订阅了这条事件并重新物化 `state/config.json`；否则卡片改了、config.json 还停在启动那一刻。
- **roots 的特殊语义**：框里空 = 本配置项没声明 roots → 沿用 `state/config.json` 既有授权根（不会被清空）；
  框里非空 = **整表替换**。卡片会按当前状态把这句话显示出来，避免"以为删了其实没删"。

> 怎么在不重启 Electron 宿主的前提下验 UI：用一个临时 profile 起第二个宿主，
> `dsh --profile <临时名> --from-default-profile web --dump-config` 建 profile → 手工 junction +
> `dsh.profile.bundles` 加一条（等价 `-RegisterMode Manual`）→ `dsh --profile <临时名> --no-open --host 127.0.0.1 --port <端口>`
> → 用启动行打印的 `?token=…` URL 打开。验完删 profile、删 junction。**改客户端文件只需刷页面**
> （bundle URL 带文件元数据算出的 rev），改 `lib/index.js` / `Config` 才需要重启宿主。

## 5. 通道与端口

| 通道 | 端口 | 默认绑定 | 认证 | 用途 |
|---|---|---|---|---|
| A2A | 7310 | 127.0.0.1 | AgentCard 公开；`POST /` 必须 `Authorization: Bearer` | 发令/回报、任务状态、证据交换的"喊话" |
| MCP | 18790 | 127.0.0.1 | `Authorization: Bearer` | 授权目录内的文件读写与 SHA256 校验 |
| MCP (stdio) | 无 | — | 进程内 | DSH 挂载 `mcp__team_link__*`，本机零端口 |

端口来自 `state/config.json` 的 `a2a.port` / `mcp.port`（默认值见 §4.3），不是写死的。

### 5.1 跨机：必须**显式**放开（v0.3.1 起）

默认仍然只绑 `127.0.0.1`。要把通道开到 LAN，**两个条件同时满足**才真的绑非回环：

```powershell
# 1) 先看本机该用哪个地址（WLAN / 第二网卡 / Tailscale）
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }

# 2) 启动时给 --host + --allow-lan（两个缺一不可）
node server\team-link-a2a.mjs --http --host 10.x.x.x --allow-lan --port 7310 --config state\config.json
node server\team-link-mcp.mjs --http --host 10.x.x.x --allow-lan --port 18790 --config state\config.json

# 等价写法：只要环境变量就够（便于放进启动脚本）
$env:TEAM_LINK_ALLOW_LAN = "1"
```

三道保险（代码里硬编码，绕不过去）：

| 输入 | 结果 |
|---|---|
| `host` 是回环 / `localhost` / `::1` | 绑 `127.0.0.1`（正常） |
| `host` 非回环但**没给** `--allow-lan` | **拒绝**，回落 `127.0.0.1` 并写 warn（日志里有原因） |
| `host` = `0.0.0.0` | **拒绝**（会暴露所有网卡），回落 `127.0.0.1` |
| `host` = `192.168.1.*` | **拒绝**（两板私有链路，同 IP/同 MAC，会打错板且不报错），回落 `127.0.0.1` |

防火墙：Windows 三个配置档默认拦入站，跨机要一条入站规则（管理员）。只放对端一个地址，例如：

```powershell
New-NetFirewallRule -DisplayName "team-link from <对端IP>" -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort 7310,18790 -RemoteAddress <对端IP>/32
# 回滚
Remove-NetFirewallRule -DisplayName "team-link from <对端IP>"
```

不开 LAN 也能干活：**stdio 通道 + issue 轮询**完全不需要端口，单机四项验收与协作纪律都照常。

## 6. 网络与安全（硬约束）

- **PC↔PC 不能走 `192.168.1.x`**：那是两块板各自私有的板卡链路，且两块板同 IP / 同 MAC，从 PC 侧连过去会命中"错误的那块板"，症状是"烧错了板/ILA 抓不到"而不是报错。
- 跨机只走：WLAN、第二网卡、Tailscale（三者任选其一并固定，别混）。
- 18790 / 7310 **只在内网**，且**强制 Token**（Bearer）。Token 是 32 字节随机 hex，**不进 git / 不进 issue / 不进聊天记录**；权威副本在 DSH 凭据存储的 `refs:` 段，运行时物化到 `state/*.token`（§4.5）。
- **入站与出站 token 分离（schema v2）**：
  | 方向 | 用哪个文件 | 内容归属 |
  |---|---|---|
  | 入站（校验来客） | `state/a2a.token`、`state/mcp.token` | **自己的**，本机生成 |
  | 出站（调用对端） | `state/peer-a2a.token`、`state/peer-mcp.token` | **对端的**，由对方线下交付 |
  因此两端**不需要共享同一份凭据**，任一边都可单边换 token 而不断开另一方向。未放对端 token 时 `evidence_pull` 会回落到自己的 `mcp.token`（兼容 v1 的共享 token 部署）。
- AgentCard 对外是公开的（A2A 规范要求），因此**不要在 AgentCard 里放路径、Token、板卡凭据**。
- 授权目录由 `state/config.json` 的 `roots` 定义；`list_roots` 暴露的就是这份清单，服务端拒绝绝对路径、`..` 段、以及 realpath 后跳出 root 的请求。

## 7. 什么时候该退回 issue

协作层是加速器，不是唯一真相源。出现下列任一情况，**立刻转 issue 轮询**（`collab_status.ps1` 会打印 `[FALLBACK]` 行并写日志）：

- 两条通道任一不可用（对端离线、重启中、防火墙改了、Token 不一致）；
- 对端 IP / 角色 / 判据有争议，通道上讲不清；
- 需要一条"可被第三方复核"的决策记录（烧录窗口裁决、判据变更、回滚决定）；
- 对端 AgentCard 报告的机器身份与预期不符（防连错机器）。

回退动作固定三步：① `tools/collab_status.ps1` 留证；② 在共享仓开/更 issue（用 `templates/daily-audit-issue.md` 的格式）；③ 通道恢复后用 `tools/evidence_pull.ps1` 把通道期间产生的证据补齐并复核 SHA256。

## 8. 单机验证（PC2 未上线也能全过）

```powershell
node client\a2a-selfloop.mjs --config state\config.json     # 需先起 A2A 服务
node client\mcp-selfloop.mjs --config state\config.json     # 需先起 MCP http 服务
powershell -NoProfile -File tools\collab_status.ps1          # 通道断开时须打印 [FALLBACK]
```

四项判据见 `templates/PC2_上线清单.md` 的"单机验证"小节与本仓交付记录。

## 9. 已知风险

- **从仓重装 kit 会替换整个 staging 目录（含 `optional/`）**：dsh-vivado 的 `install.ps1` 会把 kit 重新 stage 到 `<DshHome>\bundles\dsh-vivado`，这是**整目录替换**，不是增量合并——`optional/team-link/` 里的本地改动会被一起换掉。所以**开发一律在仓里做，部署副本只当运行目标**；部署副本上换完 kit 需重新跑本插件的 `install.ps1`（`state/` 里的 token 与配置若没被带走需重新生成，随后由 `apply()` 按 profile 配置物化/重建，见 §4.4）。
- **GUI 面板改的是 profile 配置，不是运行中的服务**：卡片保存后宿主会立刻重物化 `state/config.json`（`apply()` 订阅了 `loader/volatile-update`），但 A2A/MCP 两个服务是**启动时**读端口与 token 的 —— 改完要重启宿主才在通道上生效。凡是说"存了就生效"都是错的。
- **GUI 卡片不读凭据状态**（§4.7）：`remote.credentials` 是非必需服务，未 inject 就取会抛错并崩掉整张卡片，所以"token 配没配"请用 `team_link_setup {action:"status"}` 查。
- `-RegisterMode Cli` 依赖 `dsh` CLI 与 pnpm 在工作目录内解析 link:；离线或 pnpm 异常时用 `-RegisterMode Manual`（等价于手工 junction + `dsh.profile.bundles` 条目）。
- 端口冲突：7310/18790 被占用时 A2A/MCP 起不来，`collab_status.ps1` 会如实报不可用而不是假装正常。
- 中文路径：所有 `config.json` 路径建议 ASCII（与 kit 对 Vivado 的要求一致），至少 `state/` 与证据目录保持 ASCII。

## 10. 版本


0.3.5 —— **把 setup 的「起服务」并进 ops 开工流程（`tl-boot` 一条命令）**：

- **问题**：DSH 重启后 LAN 服务不自启，而「加载了 team-link-ops 技能」并不包含「起服务」这一步——
  它只写在 team-link-setup 里。交接 prompt 一漏，就出现「两边都以为通道好、其实本机没监听」，
  对端发来的消息全部没人接（2026-11-24 实测：PC1 重启 DSH 后未恢复 start-lan）。
- **新增 `skills/team-link-ops/scripts/tl-boot.ps1`**：一条命令四步——① `config.json` 的 host vs 当前 WLAN
  ② 没监听/绑错地址就 `start-lan -Stop` 再起、等 ≤15s 复验 ③ 本机 AgentCard 200 + 对端 `pc1_pc2_ping`
  ④ `tl-pin` 钉选本会话。**幂等**：已监听直接跳过，不打断正在跑的任务。
  退出码 `0`=就绪 / `2`=服务没起 / `3`=钉选失败 / `4`=地址或配置不一致（属 setup）；
  开关 `-CheckOnly` / `-NoPin` / `-Force` / `-SkipPeer`。
- **技能**：`team-link-ops` §1.1 重写为「开工 / 重启后先跑 tl-boot」，§8 故障表把「本机通道 DOWN」
  指向它；`team-link-setup` 顶部加一句「日常开工不需要本技能，只有 tl-boot exit 4 才进来」。
- **职责边界不变**：改地址/改端口仍是 setup 的 `tl-sync.ps1 -Apply`；tl-boot 只按**现有配置**把服务拉起来，
  遇到地址不一致不改配置、直接报 ④。

0.3.4 —— **投送会话钉选（「消息投进了别的会话」的根治）**：

- **问题**：收件箱桥按「最近活跃的根会话」挑投递目标。PC1 同时开着几个会话时，对端消息会投给
  「刚说过话」的那个，在等消息的任务会话反而收不到（2026-11-24 实测：PC2 的 TEAM-REPORT 投进
  `session-3960517d`，`session-20c4d817` 收不到）。
- **新增 `skills/team-link-ops/scripts/tl-pin.ps1`**：把当前会话（`$env:DSH_SESSION_ID`，宿主已注入）
  写进 `state/pinned-session.json`，幂等；`-Show` / `-Clear` / `-SessionId` / `-Json` 齐备，
  退出码 0=已钉 / 3=未钉 / 4=拿不到会话 id / 1=写盘失败。
- **桥改为钉选优先**（`lib/index.js` 的 `pickTarget`）：有钉选只投钉选会话（`pin: hit`）；
  钉选会话不在 `agents.list()` 里才回退最近活跃（`pin: miss`）；没钉选记 `pin: none`。
  三种状态各只记一行，诊断日志 `state/inbox-bridge.log` 可复核投递理由。
- **新增 `lib/pin.js`**：钉选文件的读写与匹配做成纯函数（匹配键 `agent.id`，实测与
  `DSH_SESSION_ID` 同值），坏文件一律当「没钉选」，绝不抛错。
- **技能**：`team-link-setup` §0.1 与 `team-link-ops` §1.1 都把「加载即钉选」写成第一动作；
  `tl-state.ps1` 只读回显当前钉选；故障表补「消息投进别的会话 → 在本会话重钉」。
- **可判定「重启有没有加载到新版」**：桥首行诊断改为 `start: v=<version> agents=… list=…`
  （宿主只在启动时加载插件代码，版本号让「改完没重启」不再靠猜）。
- **自测**：`tools/pin-selftest.mjs`（15 项）——纯函数 8 项 + 真桥 7 项（把 `lib/` 拷到临时目录、
  import 真的 `apply()`、用伪 agents 跑 tick），覆盖无钉选/命中/失效回退三条路径。

0.3.3 —— **收件模型重做（「PC1 收不到 PC2 消息」的根治）**：

- **新增 `skills/team-link-ops/scripts/tl-recv.ps1`**：一条命令完成「找新消息 → 打印正文 → 记 delivered」，
  按 **task id 账本**（`state/ops-ledger.json`）记账而非文件修改时间，从结构上消除三类缺陷：
  游标竞态（处理期间到达的消息被 `-Advance` 一起跳过）、看一眼即算已读、备份还原后历史消息整体复活。
  退出码重排：**0=有消息（对端不通只加一行 WARN）**、3=无消息、2=无消息且本机服务没监听。
  两态账本：`delivered` 超过 10 分钟未 `done` 会带「未确认完成」重报，agent 被打断不丢。
- **宿主半边加收件箱桥**（`lib/index.js` 的 `startInboxBridge`）：把落盘的新任务推进 agent 收件箱
  （`ctx.agents.list()` + `agent.inbox.prepend('next-step', …)`），使 agent **不必等轮次**即可被唤醒。
  message 形状按候选依次试探、第一个不抛错的锁定；全部失败自我停用并记原因；`TEAM_LINK_NO_INBOX_BRIDGE=1` 可关。
- **服务端**：任务落盘改**原子写**（tmp + rename，避免读方看到半截 JSON）；初始状态由 `completed` 改为
  **`submitted`**（已收下、未处理），不再把「服务端回执」谎报成「已办」。
- **安装器**：新增 `tools/version-check.ps1` 并在注册前预检——`dsh-mcp-client` 的精确钉版与 dsh 运行时不符时
  **中止注册**并打印升级命令（不兼容的行在 nightly 上会让整个宿主起不来）。判据用卸载器 exe 的 `ProductVersion`。
- **技能**：`team-link-ops` 重写——主流程改为 `tl-recv`；**删除「连续 3 轮没消息就收尾」**（它会让 agent 在
  对端正常干活时主动停止收听）；补宿主 `pwsh` 超时契约、静默两分（通道问题 vs 正常工作）、PowerShell 变量名大小写陷阱。
- 其余：`tl-watch` 摘要改取 `history[0]` 正文（不再显示无信息的 `[ack]`）；`tl-say` 措辞改为「已落盘（不代表对端 agent 已读）」；
  `plugin.json` 的 `provides.skills` 补全为 3 个、`requires.dsh` 收紧为 `>=0.2.2-rc.5`。

0.3.2 —— **工具修复（交付可见性）**：① `tools/start-lan.ps1` 修"启动后脚本不返回"—— 根因是 Windows `bInheritHandles=TRUE`，即使把 stdout/stderr 全重定向，子进程仍继承父进程 stdout 管道的写句柄，调用方读管道等 EOF 就永远等；唯一有效做法是"启动器本身不被句柄继承"（`Start-Process` **不带任何 `-Redirect*` 开关** → 走 ShellExecuteEx，重定向交给 `cmd /c start "" /b ... > log 2>&1`），实测三种重定向变体均 HUNG>15s、该方案 0.56s 返回；同时新增 `-PidFile`、`-Stop` 加 pid 复用安全阀、日志目录跟随 `cfg.logDir`。② `tools/pc1_pc2_ping.ps1 -UseMcp` 不再固定探 7310：端口优先级改为「显式 `-Port` > 目标 URL 的显式端口 > 该通道配置端口」，并修掉 `http://host/mcp` 的 `$uri.Port` 会返回 80（`IsDefaultPort=true`）被误当显式端口的老坑；打印里加"探测端口取自哪一项"便于对账。③ 同文件 `peer.name` 比较口径：卡片名是 `team-link-<role>`、配置只写角色名，字面比较必然误报 WARN（等于这条告警永远叫狼来了）→ 剥前缀后再比，真不一致仍 WARN。实测：本机卡片 + `peer.name=pc1` 不 WARN、改成 `pc9` 仍 WARN。
0.3.1 —— **跨机可用 + 交付修复**：① A2A/MCP 服务端新增显式 LAN 开关（`--host <ip>` + `--allow-lan`，或 `TEAM_LINK_ALLOW_LAN=1`），默认仍只绑回环，`0.0.0.0` 与 `192.168.1.*` 一律拒绝（见 §5.1）；② `VERSION` 改为从 `package.json` 读（此前写死 `0.1.0`，AgentCard/initialize 的版本串与包版本对不上，跨机核对时误导）；③ 修 `client\a2a-selfloop.mjs` 在 Windows 上的退出竞态 —— 四项全 PASS 却因 `process.exit` 与 undici 句柄关闭撞车而 abort（`UV_HANDLE_CLOSING`，退出码变负），改为设 `exitCode` 让事件循环自然收尾 + unref 兜底，连跑 5/5 稳定 exit 0；④ **`.gitignore` 修 `state/` 误伤**：整目录忽略导致 `state\config.example.json` 从未入库、交付包缺它，干净安装会卡在 `install.ps1` 的 0/9 预检（PC2 实测踩到，现场重建才装上）—— 改为 `state/*` + 逐条 `!` 放行模板。
0.3.0 —— **GUI 版**：新增 `lib/client.js`（手写客户端 bundle，零构建）。面板有两个入口、同一张表单：**设置里的一级分区**（`settings.section`，id `team-link`、order 20、label「PC 协作」，与「通用设置」「模型」「内置插件」同级，一次点击就到）与**插件页的行配置页**（keyed slot `plugins.row.config`，键 `dsh-vivado-team-link#team-link`）；一级分区拿不到宿主递来的 form，自己用 `ctx.configForms` 按 entry id 取。Config 里除 `fallback.mode` 外全部字段标 `.volatile()`（宿主只 serve volatile 字段），`apply()` 订阅 `loader/volatile-update` 在面板保存后立即重物化 `config.json`。面板能改角色/地址/端口/对端/回退/日志目录/授权根，**不收也不显示 token 值**。

0.2.0 —— **宿主半边落地版**：`cordis.patch.yml` 从一行变两行（`team-link` + `mcp-team-link`）、配置项进 profile、token 值走凭据存储、宿主工具 `team_link_setup` 上线；GUI 配置面板仍未做（§4.1 / §4.7）。
版本号以 `package.json` / `plugin.json` 为准；清单字段见 `plugin.json` 的 `provides` / `writes` / `rollback`。

## 11. 兼容性基线（DSH 0.2.2-rc.5 + dsh-vivado 0.2.4）

以下结论是本插件在 **DSH 0.2.2-rc.3** 下的实测结果，不是推测。换 DSH 版本后请重跑本节第 4 条的命令。

| 面 | rc.3 下的状态 | 判据（怎么验的） |
|---|---|---|
| MCP 半区（`mcp__team_link__*`） | **可用** | `collab_status` / `list_roots` 实测返回正确 JSON；`compatibility.json` 已把 `@deepseek-ai/dsh-mcp-client@0.1.7-rc.2` 豁免到 `0.2.2-rc.3` |
| 客户端半区加载 | **可用** | rc.3 的批量加载器 `/plugins/??…,dsh-vivado-team-link/client.js` 返回 200，且本包在批内 |
| 包装契约 | **未变** | rc.3 内置 bundle 仍用 `window.__ModuleLoader__.load({id,factory:require=>…})`（批内 45 次），`export default` 为 0 次 |
| 槽位名 | **未变** | `settings.section`（29 次）与 `plugins.row.config`（9 次）在 rc.3 内置 bundle 中仍存在 |
| 客户端 `inject` | **一致** | rc.3 内置客户端声明 `inject=[…,'configForms',…]`；本包为 `['slots','configForms']`，两者都存在于 rc.3 |
| 宿主 `inject` | **本轮修复** | 见下条 |
| MCP 客户端版本 | **rc5 起必须 ≥ 0.2.2-rc.5** | 见 §11.0：旧版 `0.1.7-rc.2` 的 peer 钉在 0.1.7，rc5 下被兼容性 gate 拒，`mcp__team_link__*` 会整个消失 |


### 11.0 rc5 必做：升级 `@deepseek-ai/dsh-mcp-client`（否则工具面直接消失）

**症状**：DSH 升到 0.2.2-rc.5 后，设置里插件行还在，但 `mcp__team_link__*` 五个工具**全部不见**，`team_link` 命名空间也不出现在工具目录里。

**根因**：本插件的 MCP 行按包名 `@deepseek-ai/dsh-mcp-client` 解析。profile 里装的是 `0.1.7-rc.2`，它的 peerDependencies 把 `@deepseek-ai/dsh-tools` 等钉在 `0.1.7-rc.2`，与 rc5 运行时不符。DSH 的兼容性 gate 因此拒绝挂载该行，只有**逐版本精确豁免**（`profiles/<p>/compatibility.json`）能放行，而豁免清单只写到 `0.2.2-rc.3`。

**修法（推荐：升级，不再靠豁免）**：

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json,pnpm-lock.yaml,compatibility.json -Destination . -ErrorAction SilentlyContinue  # 先自行备份
pnpm add "@deepseek-ai/dsh-mcp-client@0.2.2-rc.5"
# 期望：installed=0.2.2-rc.5；其 peer 与运行时同版本 → 无需豁免
```

**临时应急（不推荐，仅当无法联网升级）**：把 `0.2.2-rc.5` 追加进 `compatibility.json` 里 `@deepseek-ai/dsh-mcp-client@0.1.7-rc.2` 的数组。这是接受版本错配风险。

**改完必须重启宿主**（宿主插件与服务都是启动时建立）。

> 同一 gate 也会拒其它钉死 `0.1.7-rc.2` 的插件（如 `dsh-computer-use` / `dsh-experimental-computer-use-cua-driver-native`）。它们与本插件无关，但会让你以为“插件都正常”时缺东西——排查时先看这一条。
### 11.1 本轮修掉的真实缺陷：宿主半区缺 `inject`，`team_link_setup` 从未注册

- 症状：`mcp__team_link__*` 正常，但 README §4.5 说的 token 输入工具 `team_link_setup` **根本不存在**，所以「凭据存储 → token 文件」那条路在真实部署里是死的。
- 根因：宿主只给**声明了 inject** 的插件注入 `ctx.tools`（对照本机 `dsh-mcp-client` 的 `inject=['tools']`、`dsh-client-ui-browser-view` 的 `['webServer','tools']`）。原 `lib/index.js` 只导出 `name/Config/apply`，`ctx.tools` 恒为 `undefined`，`registerSetupTool()` 走自己的降级分支只记一条 warn。
- 为什么一直没被发现：`tools/apply-selftest.mjs` **自己伪造了 `ctx.tools`**，所以 45/45 全绿 —— 测试替身补齐了运行时没有的东西，属典型假 PASS。
- 修法：① `lib/index.js` 增加 `export const inject = ['tools']`（凭据存储**故意**不进 inject，它缺席时应降级为「只配路径」）；② 自测改为**按平台规则**给服务：只有 `plugin2.inject` 含 `tools` 才塞 `ctx.tools`，并新增一条断言 `宿主 inject 声明含 tools`。
- 已做负向对照：临时注释掉 `inject` 导出行 → 自测 3 条 FAIL、退出码 1；还原 → 46/46 PASS。

### 11.2 rc.3 的一处行为变化（不影响功能，但要知道）

rc.3 会把工具命名空间分页挂起：新会话里 `team_link` 可能先处于未激活状态，此时工具不在线上。
取用方式：`tool_activate({ namespace: 'team_link' })`（我们实测即生效），或按工具名直接调用让宿主自动激活。

### 11.3 换 DSH 版本后的复核清单

```powershell
node tools\apply-selftest.mjs                                   # 期望 46/46 PASS，退出码 0
node --input-type=module -e "const m = await import('file:///<本目录>/lib/index.js'); console.log(Object.keys(m), m.inject)"
#   期望 exports=Config,apply,inject,name 且 inject=["tools"]
powershell -NoProfile -File install.ps1 -Profile desktop -Role pc1   # 期望 PASS kit 未改动
```
GUI 侧：设置里应出现一级分区「PC 协作」（`settings.section`，id `team-link`，order 20），以及插件页该行的配置页（key `dsh-vivado-team-link#team-link`）。

### 11.4 已知限制：`team_link_setup` 在 rc5 下不注册（2026-11-19 确认，暂不修）

- **现象**：插件行正常、`mcp__team_link__*` 五个工具正常，但宿主工具 `team_link_setup`（token 值的唯一输入入口）不出现在会话工具目录里。
- **已排除**：包解析（从 profile 目录 `import('dsh-vivado-team-link')` 得到 `Config,apply,inject,name` 且 `inject=['tools']`）、行配置（`- id: team-link` 块完整、无 `disabled`）、工具名不匹配。
- **未定性**：rc5 里 `ctx.tools` 是否仍注入到本插件；或 `tools.register(definition)` 是否新增了形状要求（`browser-view` 内部要求 `output:{schema,render}`，但那可能是它自己的包装类而非平台契约）。宿主侧告警走 `ctx.logger`，本机拿不到宿主 console，**必须先有文件日志才能定性**。
- **影响面**：只影响 `set-token` / `clear-token`。**token 文件在位即可正常协作**——把对端 token 直接放进 `state/peer-*.token`（交付说明里的「方式 B」），双向认证与证据搬运都不受影响。
- **要修的话**：给宿主半区加 `logs/host-plugin.log` 文件日志 + 注册形状兼容（先按现有形状注册，捕获 `TypeError` 后带 `output:{schema,render}` 重试），一次宿主重启即可定性。

## 12. 两个配套 skill（`team-link-setup` / `team-link-ops`）

`install.ps1` 会遍历 `skills/` 下**每个带 SKILL.md 的子目录**并拷到 `<DshHome>\skills\`（不再是写死一个）；卸载时按 `state/skill-manifest.sha256` 里的 `<skill>/<相对路径>` 逐项清理。

| skill | 什么时候用 | 给的命令 |
|---|---|---|
| `team-link-setup` | 换网段、换机器、第一次装、或「配置看着对但连不上」 | `scripts/tl-state.ps1`（只读诊断，直接说还缺哪几步）、`scripts/tl-sync.ps1 -Apply`（把地址同步到 profile 与 state/config.json 两处，带备份与回读校验） |
| `team-link-ops` | 收件、回复、等任务、通道降级 | `scripts/tl-recv.ps1 -TimeoutSec 240`（**原子收件**：一次调用完成「找新消息 → 打印正文 → 记 delivered」，退出码 0=有消息 / 3=无消息 / 2=服务没监听；另有 `-Done`/`-Fail`/`-Baseline`） |

### 12.1 地址这件事只有一处权威

| # | 位置 | 谁改 | 生效时机 |
|---|---|---|---|
| ① | profile `cordis.patch.yml` 的 `team-link` 块 `host:` | GUI 面板 / `tl-sync.ps1` | **宿主**下次启动 |
| ② | `state/config.json` 的 `a2a.host`/`mcp.host` | 宿主 `apply()` 从 ① 物化 / `tl-sync.ps1` | 宿主启动后 |
| ③ | LAN 服务的实际 bind | `tools/start-lan.ps1` 启动那一刻 | 服务启动时 |
| ④ | 对端记录的你的地址 | 对端自己 | 对端重启后 |

所以「只在 UI 里改 IP」只做了 ①：还要**重启宿主**（①→②）、**重起服务**（③）、**通知对端**（④）。这些步骤 `tl-state.ps1` 会逐条指出，不需要记。

### 12.2 两侧都用 goal 模式（DSH 自动化任务已弃用）

| | PC1（主导） | PC2（执行） |
|---|---|---|
| 靠什么产生轮次 | goal 自动续轮 | goal 自动续轮 |
| 每轮动作 | `tl-recv -TimeoutSec 240` → 有消息就处理并 `tl-say` 回复 → `tl-recv -Done` | 同左 |
| 唤醒提前量 | 宿主半边 `inbox bridge` 把落盘消息推进 agent 收件箱（无需等轮次） | 同左 |

**DSH 自动化任务已弃用**：实测不稳定（漏投、重复投递），且调度器的投递目标是「一个已存在的会话」
（`~/.dsh/storages/schedule.json` 里 `target.kind` 只出现过 `session`），指向正在跑长任务的会话会中途插话。
已配置的请到 GUI「自动化任务」停掉。

`maxGoalRounds` 建 goal 时给够；**不要因为「几轮没消息」就结束 goal 或置 `blocked`**（判据见 skill `team-link-ops` §3）。
