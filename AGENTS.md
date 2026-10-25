# AGENTS.md — EIF 工程指令与规范（开发层，工作区 D:\FPGA）

> 本文件是开发 Agent 的**常驻指令 + 工程规范汇总**（2026-09-18 重构为规范手册）。
> 你对工程状态的实测结论即事实源。**多会话协同由用户自行编排**（按需加载知识库管理技能），旧三层协作契约（Reasonian/Reasonix/中控）已于 2026-09-20 废弃，`毕设\Agent 协作\` 仅作历史归档。
> 工程进度总览看 `README.md`；本文件管**怎么干活**。
> 会话若从 vault（`C:\Users\15266\Desktop\毕设\`）启动，先读其根目录 `agent.md`（会话入口，本文件的镜像+双目录协议）；规范冲突时以本文件为准。

## 目录（30 秒导航）

- [§一 角色与红线](#一角色与红线)（硬红线：代劳边界 / git 可追溯 / ASCII 路径）· [§二 事实源与第一性原则](#二事实源与第一性原则本工程最高规范)（可信度排序）· [§三 硬件事实卡](#三硬件事实卡实测定论勿凭记忆改写)（器件/引脚/时钟实测定论）
- [§四 工程结构与脚本规范](#四工程结构与脚本规范)（目录约定 + Tcl 四件套）· [§五 RTL/设计规范](#五rtl设计规范)（CDC 三合法形式 / XDC 受限 Tcl）· [§六 调试方法论](#六调试方法论按代价升序)（判别实验→ILA→网表解剖→延迟扫描）
- [§6a 结论依据等级](#6a-结论依据等级2026-10-16-增补源于退役桥②读引擎两轮误判复盘)（**L0–L4：归因结论必须标注依据等级，低于 L2 只能称假说**）
- [§6b AI 技能与官方文档检索](#6b-ai-技能与官方文档检索2026-10-18-增补)（**项目级 skill 作用域 / 官方文档检索调用与引用纪律 / 官方文档在事实源中的位置**，2026-10-18 新增）
- [§七 验证判据规范](#七验证判据规范)（链路/通路/数据三层判据）· [§八 git 与文档规范](#八git-与文档规范)（提交前缀 / 命名规范 / 两类文档分放）
- [§九 坑账本 #1–#64](#九correction坑账本踩过的坑--规范的来源)（**踩坑实录 = 规范的来源，排障先查这里**）
- [§十 当前工程状态](#十当前工程状态一屏速览内部详表见本节附录)（**一屏速览：现在做到哪、下一步是什么**）
- [§十一 跨目录约定](#十一跨目录约定) · [§十二 CI 与远程仓库规范](#十二ci-与远程仓库规范)（**CI 6 项静态检查 + 6 项本地专用门禁各防什么、本地怎么跑、新增文件自检清单**）

## 一、角色与红线

### 协同方式

用户通过不同会话按需协同，无固定分工。本文件对任何在本仓库工作的 Agent 生效；文档目录（`C:\Users\15266\Desktop\毕设\`）入口为其根 `agent.md`。

### 硬红线
1. **每步标注「为什么」**——工程优先：改动说明写清依据（契约/实证/官方例程出处），不允许只给结论。
2. **物理层：经允许可代劳**——烧录/ILA 抓取与判读/串口/JTAG 的工具链 = **本仓库 `vivado-mcp/`**（运行时实装 `D:\vivado-mcp`，见坑账本 #21）+ xsct，2026-10 实证可全程远程；**经用户允许后代劳上板验证**，插拔光纤/电源、开关机、示波器等物理接触仍归用户，未经允许不主动上板。**推荐协作 agent 采用同一工具链**（本仓库副本即为此保留，配置法见 vivado-mcp 文档）。
3. **改动可追溯**：一切改动走 git，提交信息写清意图与证据；位流/日志不入库（.gitignore）。
4. **工程路径全英文**：Vivado 对中文路径乱码（GBK 实证）。vault 文档中文没问题，Vivado Tcl 引用的路径必须 ASCII。
5. ** vault 与工程目录双向开放**：改 vault 文档可以，但 vault 为权威版本、工程内只放脱敏快照。

## 二、事实源与第一性原则（本工程最高规范）

板级参数与设计的可信度排序，**只允许从高向低采信**：

```
官方例程/官方 XDC（正点原子 KU060例程 39/50/53/55 号等）
  > 已上板验证过的 prj（prj6 网口栈 / prj8 数据级桥 M2 判据全过版）
    > 板卡手册/引脚表（KU_IO.xdc，GBK 编码）
      > AI 生成的开发文档（仅参考，不可作为实现依据）
```

**两轴采信规则（2026-10-18 增补；AMD 官方文档/知识库接入后生效）**

- **知识/工具语义轴**（Tcl 命令与属性、UG/PG 文档、IP 参数含义、协议/AXI/Aurora/MIG 规则、时序方法学、工具报错解释）：**AMD 官方文档/官方知识库 = 最高权威**，高于个人经验、AI 记忆与其它项目笔记。引用必须带 `docs.amd.com` / `adaptivesupport.amd.com` URL。
- **工程事实/判据轴**（本板引脚、时序、IP 实例配置、板上行为、判据与实测）：**本项目实测优先于官方文档**。官方文档与实测冲突时：先做版本/器件/IP 实例对齐核验；仍冲突 ⇒ 以实测为准，记录里并列「官方口径 vs 本项目实测」并写明版本/器件差异。
- 引用官方文档的结论必须给**两件套**：① 官方依据 URL（并逐条核对返回块 `family:`/`version:`，坑 #64）② 本项目落点（**Vivado 2023.1** / 器件 `xcku060-ffva1156-2-i` / 对应 IP·BD 实例与参数 / 在本工程的验证动作或实测证据）。缺一不得写成「判定/根因」。

推论：
- 任何引脚/时序/IP 参数**先查官方例程 XDC 与已验证 prj 的 XDC**，IP 参数语义/版本差异查 AMD 官方文档（带 URL），找不到再问用户，最后才看 AI 文档。
- **官方 RTL 文件保持原样**（磁盘上的官方栈/Aurora 例程文件永不改）。修复手法二选一：
  ① **同名模块顶替**：新写 `xxx_fix.v`（module 名与官方一致），把官方文件从 fileset 移除、fix 加入（官方文件留在盘上）——prj8 `rgmii_rx_fix2.v` 即此法；
  ② **派生新文件**：复制官方文件→改模块名→只在派生版上动刀（`aurora_64b66b_0_support_ext.v` 即此法）。
- 判别实验优先：**怀疑实现层时先烧官方位流对照**（prj8 用官方 39 位流 ping 6/6 一举排除硬件，定位到实现层）。

## 三、硬件事实卡（实测定论，勿凭记忆改写）

| 项 | 事实 | 证据来源 |
|---|---|---|
| 器件 | `xcku060-ffva1156-2-i`（非 CIV）| 丝印+实现通过 |
| 系统时钟 | 100MHz 差分 AK17/AK16 | KU_IO.xdc |
| 复位 | AC34 低有效 LVCMOS18 | KU_IO.xdc |
| 网口 | GE1 RGMII（YT8531），栈时钟 eth_rxc 125M | 官方 39 XDC |
| ⚠️ RGMII RX | 2023.1 吸收官方 BUFIO→IDDRE1 挂全局钟，须 `rgmii_rx_fix2.v`（IDELAY **1250ps**+IDELAYCTRL） | prj8 网表解剖+延迟扫描 |
| Aurora 参考钟 | MGTREFCLK1_226（T6/T5）156.25MHz | IBERT 实测 |
| 光口映射 | **A=Y11=X1Y11 · B=Y9=X1Y9 · C=Y10=X1Y10 · D=Y8=X1Y8**（Quad X1Y2） | 官方 55 号 XDC 注释 + GT LOC 双证 |
| 光口控制脚 | A: tx_dis=AF12 rs0=AF13 rs1=AE13；B: AH12/AH11/AG11；C: J25/M26/M25；D: H26/G27/H27 | 官方 55 号 XDC |
| 光模块 | 须 10G SFP+（线速率 10G，RS0=RS1=1 高速档，tx_disable=0） | Aurora xci C_LINE_RATE=10 |
| LED | T22=观测（粘滞 rx）· T23=channel_up/link_ok（链路硬门控指示） | 各工程 XDC |
| JTAG | 调试烧录用 Digilent USB-JTAG（210512180081）；串口 FT2232H-B **COM5**（2026-10 实测；COM7 为旧误记） | hw_server 实测 |
| PC 侧 | NIC 192.168.1.102/24 静态 ↔ 板 192.168.1.10（MAC 00:11:22:33:44:55） | prj6 起 |
| Python | `C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe`，**须 `PYTHONUTF8=1`**（GBK 控制台打 ✓ 会崩） | udp_verify 实证 |

## 四、工程结构与脚本规范

```
D:\FPGA\prj\project_N\
├── rtl/            # 设计 RTL（官方栈按子目录分 arp/ icmp/ udp/ gmii_to_rgmii/）
├── shared_logic/   # Aurora 例程共享逻辑（派生文件也放这，命名 *_ext/_shared）
├── ip/             # 只存 .xci（import_ip + generate_target 重新生成，产物不入 git）
├── xdc/            # 引脚+时钟组约束（引脚注释必须写来源）
├── scripts/        # Tcl 四件套 + py（见下）
├── out/            # 位流（gitignore）
└── docs/           # 工程级文档（设计说明/PROGRESS）
```

**脚本四件套（幂等，逐个可重跑）**：
1. `create_project.tcl`——建工程：`add_files` glob → `import_ip`（勿用 read_ip，prj7 实测路径漂移）→ `generate_target all`。
2. `build_debug.tcl`——综合+ILA 插入+实现+出流：输出 `TIMING:`（WNS）与 `DBG_BUILD_DONE:` 标记行供日志抓取。
3. `program_board.tcl`——hw_server 烧录（成功标记 `PROGRAM_OK`）。
4. `board_test_*.ps1`——一键「烧录→ping→udp_verify」判据跑。

**规范**：日志落文件再 Select-String（勿管道直取——回显行会污染）；`create_project -force` 前先杀残留 vivado 进程（锁 runs 目录是实坑）；python 一律 `PYTHONUTF8=1`；**`.ps1` 一律带 UTF-8 BOM**（本机 shell 是 PS 5.1，读无 BOM 的中文脚本按 CP936 解码必报语法错——见坑账本 #17/#18）。

## 五、RTL/设计规范

1. **CDC 只有三种合法形式**：帧泵式格雷指针异步 FIFO、2FF 同步器（打拍≥2）、4 相握手邮箱。新跨域路径必须三选一。
2. **mark_debug 探针标注时钟域**，ILAs 挂同名域——跨域采样探针曾是 WNS=-2.6ns 的元凶（prj8 首轮实证）。
   B 通道（user_clk_b 域）探针绝不能挂 A 域（user_clk）ILA。
3. **互不相关时钟必须声明时钟组**：`set_clock_groups -asynchronous`（eth_rxc / gt_refclk 派生 / init_clk 三组），否则跨域路径被假同步分析重罚。
4. **XDC 只用受限 Tcl**：不能 `if/foreach/puts`（实测整段丢弃，CRITICAL WARNING [Designutils 20-1307]）。参数化约束改在 Tcl 脚本里生成。
5. **判据无旁路原则**：数据通路必须被链路状态硬门控（`aurora_rst=~sys_rst_n|~channel_up`）——链路没起来板子对外静默，判据通过 ⇔ 数据真的穿过了链路。
6. **一个 quad 只允许一个 GT_COMMON**：多 Aurora 同 quad 时，第一个实例的 support 引出 refclk+QPLL 四件套（`_ext`），兄弟实例用无 common 的 `_shared` 版；各实例私有 MMCM 时钟模块与复位逻辑。
7. **Aurora 核端口方向**：`gt_pll_lock` 是核的**状态输出口**（外部 assign 驱动它 = MDRV-1）；外部锁定状态只走 `gt_qplllock_quad1_in`。
8. IP 参数不确定时**只设置有把握的**——set_property 遇到不存在的参数名是致命错（fifo_generator 实坑）。

## 六、调试方法论（按代价升序）

1. **判别实验**：换已知好的位流（官方例程）对照，先分「硬件 vs 实现」。
2. **ILA 单会话三段式**：同一 Vivado batch 会话内 arm → 起流量（ping）→ upload → CSV。arming 易失，**不能跨会话**。触发探针名要与 probes.ltx 一致；`TRIGGER_POSITION` 属性不被接受（省略或 catch）。
3. **网表解剖**：`open_checkpoint` 两份 dcp 对比元件/位置/绑定（prj8 定位 BUFIO 被吸收即此法）。
4. **延迟扫描**：时序边缘问题时改一个参数出一流（IDELAY 500→1250ps 即收敛过程），每次记录 ping 通过率。
5. 每轮调试落**调试记录**（现象→假设→实验→证据→结论五要素），入 vault `调试记录/`（2026-10-01 起记录类独立成目录，见第八节）。

### 6a. 结论依据等级（2026-10-16 增补，源于退役桥②读引擎两轮误判复盘）

**背景**：10-16 两轮退役尝试的根因判定先后被推翻（"驻留服务长 guard 卡死软核"→实测 DMA 静止；"判定为软核侧、非位流"→ELF 对照只做了单侧）。误判共性：**把"与现象相容的假说"当成了"已证实的结论"写进文档**。本节为对策——任何归因性结论**必须标注依据等级**，低于 L2 的只能称假说。

| 等级 | 名称 | 判定条件 | 允许的用途 |
|---|---|---|---|
| **L4** | 定案 | 唯一相容解释 + 对照实验闭环 + 修复后复验通过 | 写入记录/结论，作为后续设计输入 |
| **L3** | 板证实 | 板上实测直接观测到机制本身（非推论），且排除了全部已知替代解释 | 写入记录，标注"未修复复验" |
| **L2** | 对照成立 | ≥2 个方向的对照实验（正交变量各做了 ±），结果方向一致 | 写入记录，**必须标注"待复验/待穷尽"** |
| **L1** | 相容假说 | 与现有全部观测相容，但未做对照或只做了单侧对照 | **只允许出现在"假设"栏**；禁止写成"判定/根因/定位" |
| **L0** | 猜测 | 无实测依据（例程直觉 / AI 文档 / 记忆） | 禁止写入记录；只允许作为下一步实验的候选 |

**硬规则**：
1. **归因三禁**：禁止在只有单侧对照时写「判定为 X 侧」「根因是 X」；禁止把"排除 A"写成"证明 B"（排除法只收敛候选集，不产生新结论）；禁止用同一实验同时支持两个互斥假说。
2. **对照完整性**：归因"软核/位流"这类二分时，**两侧都必须跑**（ELF 对照 + 位流对照矩阵），缺一侧就是 L1。
3. **判据未触发 ≠ 判据通过**：实验因时序竞争没跑到判据（如 'E' 轮 `served=0`），结论只能是"判据未取得"，不得写成"通路正常/异常"。
4. **工具链静默失效自检**（Vitis 增量构建不重编、PowerShell `>` 重定向改编码——均 10-16 实证）：改 ELF/重编译后**必须核对产物 hash 变化**；用 `git show` 取文件**禁止走 PowerShell 重定向**（用 `git checkout <commit> -- <path>`）；关键实验前对产物指纹做一次硬校验。
5. **时基校准**：涉及延时/速率的代码（如 `busy_ms`）上线前必须用可观测事件（LED/串口时间戳/ILA）标定一次真实时长——10-16 实证 `busy_ms(1)` 实为 **≈0.15ms（比设计快 6.6×；早期「慢 25×」为未实测误判，已被 M-B 推翻，见坑 #51）**，所有依赖它标定的轮询周期/超时阈值按 6.6× 重标。
6. **记录写法**：记录类文档的结论行必须带等级标注（如"`[L1-假设]`"），复核/复盘时按等级倒序清理——先审 L0/L1 是否伪装成了结论。

### 6b. AI 技能与官方文档检索（2026-10-18 增补）

**背景**：2026-10-18 接入 AMD 官方 Ross 技能包（Vivado：elaboration 日志分析 / RTL lint / 时序方法学 / 工程交接 / 仿真排错 / ILA·VIO 手册）与官方文档检索（hosted `amd-doc-search`）。二者是**知识与流程层**；执行层仍是本仓库 `vivado-mcp/`（32 工具，**2026-10-24 起经会话预设 `Vivado` 随会话挂载**，见下表）+ xsct + 自研脚本——**装了技能不等于多出 Vivado 工具**。

| 资产 | 位置 | 作用域 | 现状 |
|---|---|---|---|
| **Vivado 会话预设（`Vivado` 纪律 + 32 个 `mcp__vivado__*`）** | profile `~/.dsh/profiles/desktop`；bundle 源码 `<vault>\.dsh\bundles\vivado-preset\` | DSH desktop profile，**按会话选择** | **2026-10-24 新建**：建会话时选 `Vivado` 预设才挂这 32 个工具（默认 `standard` 会话一个都没有，每请求省 ≈8k tokens 工具定义）；预设内含全局串行/ASCII 路径/证据纪律 persona；改它需重启宿主（`dsh-hmr` 在 Electron 下不生效） |
| AI 技能（8 个：6 官方 AMD + `amd-doc-search` + `vivado-workflow-discipline`） | 仓库 `D:\dsh-vivado\skills\`；安装后 staging `~/.dsh/bundles/dsh-vivado/skills\` | **仅 `Vivado` 预设会话**（rank 300 `customSkillDirs`） | **2026-10-24 迁出 vault**：与 32 工具同一来源、同一仓库维护，不再走项目级 rank 100；vault `.dsh\skills\` 只保留 `MANIFEST.json` 快照（供门禁检查 12），旧副本已归档 `<vault>\归档\dsh-vivado_迁移归档_2026-10-24\`。**注意**：`hw-ila-debug`/`hw-vio-debug` 依赖的 `vivado-mcp`（32 工具，`mcp__vivado__*`，stdio，`toolCallTimeoutMs=1800000` 等三条硬约束写在上行的 bundle 里）——**2026-10-24 起不再全局挂载**，改由 `Vivado` 预设携带：**新会话选该预设才有工具**；没选预设时仍走 CLI 桥 `D:\vivado-mcp\mcp_ctl.py` 或 Vivado batch Tcl（两技能文首「本机适配注记」同口径） |
| 官方文档检索（原生 MCP） | `~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-amd-doc-search` 条目 | DSH **web profile 全局**（所有工作区；重启 `dsh web` 后生效） | **已配置但当前进程未加载**（会话工具清单无 `mcp__amd_doc_search`）；重启后生效，工具名 `mcp__amd_doc_search__vivado_doc_search`。**desktop profile 亦未配置该条目，仅 web profile 有** |
| 官方文档检索（CLI 桥，随包发布） | `D:\dsh-vivado\skills\amd-doc-search\doc_search.py`（或 staging 同名路径） | 任意会话可直接跑 | 生效：`py <该路径> "<query>"`（stdlib 直连 AMD 服务，无需重启）；`Vivado` 预设会话里也可直接让 agent 用该技能 |
| 服务端点 | `https://ross.amd.com/mcp/doc-search` | AMD 托管、免 key、英文；`version` 含 2023.1、`family` 含 Kintex UltraScale+；**query 会发往 AMD**（官方称不存 query 文本）；NDA/EA/项目私有资料不在索引内 | — |

**使用纪律**：

1. **先检索再回答**：凡需 AMD/Xilinx 官方依据（Vivado Tcl 命令/属性、UG901/UG903/UG906/UG949、AXI/Aurora/MIG、ILA 等），先调文档检索；结论必须带 `docs.amd.com` / `adaptivesupport.amd.com` URL。检索不到就写"未检索到"，**禁止臆造**命令/参数/约束。
2. **权重与工程绑定（硬规则）**：AMD 官方文档/知识库在**知识/工具语义轴**上是**最高权威**（Tcl 命令属性、IP 参数含义、协议规则、时序方法学、报错解释一律以官方文档为准）；但**工程事实/判据轴以本项目实测为准**（本板引脚/时序、IP 实例参数、板上行为、判据结果），冲突处理见 §二「两轴采信规则」。引用必须给**两件套**：① 带 `docs.amd.com`/`adaptivesupport.amd.com` URL，逐条核对返回块 `family:`/`version:`（坑 #64）；② 本项目落点——Vivado **2023.1**（官方基线 2026.1，版本差异必须说明）、器件 `xcku060-ffva1156-2-i`、对应 IP/BD 实例与参数、以及"在本工程怎么验证"的动作或实测证据。**严禁**把官方示例/默认参数/新版行为直接当本工程结论；低于 L2 的只能称假说（§6a）。
3. **过滤参数是提示性、不是硬过滤**：`family`/`version` 参数不保证返回结果都被限定，必须逐条核对返回块里的 `family:`/`version:` 字段（坑 #64）。
4. **技能步骤要映射工具**：官方 skill 正文写的是官方 MCP 工具名（`vivadoExecute`/`vivado_start`/`vivado_doc_search` 等）；本工程一律按技能顶部「本机适配注记」映射到 `run_tcl`/`start_session`/`mcp_ctl.py` CLI 桥，**不得假设官方 MCP 已装**。
5. **只读分析不占 Vivado**：解析历史 `runme.log`/`vivado.log`、lint/时序报告等只读任务**不启动 Vivado、不抢全局串行锁**；要启 Vivado 的步骤仍受红线 #2 / 坑 #21 约束。原始日志一律**复制到 C: 侧副本**再解析，不写回 `D:\FPGA`。
6. **版本基线**：官方基线 Vivado 2026.1，本工程 2023.1；技能内版本假设须先核对，2023.1 待实测项见下方细节文档。
7. **外发边界**：hosted 检索逐次外发 query；涉密/未公开设计细节禁用；完全离线需 AMD entitlement 的本地 KB（当前不投入）。

**细节文档**：[参考文档](docs/参考_cross_AI工具链_AMD官方skill与知识库_2026-10-18.md)（技能清单、调用示例、兼容性矩阵、2023.1 待实测、排障与回滚）。

## 七、验证判据规范

**三层证明力**（每层通过才算闭环）：
| 层 | 命令 | 通过标准 | 证明 |
|---|---|---|---|
| 链路 | 看 T23 | 常亮 | channel_up（硬门控前提）|
| 通路 | `ping 192.168.1.10 -n 20` | 0% 丢包 全 <1ms | ARP+ICMP 穿 Aurora 往返 |
| 数据 | `$env:PYTHONUTF8=1; python scripts\udp_verify.py [次数]` | **回显一致 12/12** | payload 逐字节原样返回 |
| 佐证 | Wireshark 抓 `udp.port==1234` | 请求/回显成对且 payload 相同 | 帧级眼见为实 |

`udp_verify.py` 的 12 个长度（26~33/40/63/100/200）是刻意选的——**覆盖帧长%8 全部余数类**，专压打包/解包尾部处理。跑前关闭占用 1234 端口的程序。

## 八、git 与文档规范

- **每个里程碑一提交**，信息含：改了什么/为什么/WNS/判据结果。多行信息写临时文件 `git commit -F`，提交后删。
- 提交语义前缀：`project_N:`（工程主线）/ `project_N fix:`（修根因）/ `docs:`（文档）。
- vault 文档快照入 `docs/操作文档/` 须脱敏（用户名→`***`，人名→`前辈`）；命名 `[阶段]_prj标识_概要_YYYY-MM-DD`。vault（Obsidian 知识库）已于 09-19 同步采用本规范，类别扩展：汇报/规划/追踪/结论/复现；重命名文件 frontmatter 加 `alias: 旧名` 保旧链接可达；新旧名映射见 `docs/README.md`。豁免：`README.md`、`agent.md`（vault 会话入口镜像，冲突以本文件为准并回改镜像）、非 Markdown 数据文件。
- **文档两大类分开放（2026-10-01 起；vault 与 `docs/` 同构）**：
  · `操作文档/` = **操作开发类**——读它是为了"照着做"：实操单 / 实施单（开工草案）/ 开工开发文档 / 前置清单 / 上板验证单 / 作战卡 / 演示文档；`操作文档/挂起/` 为状态轴收纳区。
  · `调试记录/` = **调试记录类**——读它是为了"看结果/看证据"：调试记录 / 执行记录 / 测试报告 / 独立复核 / 断点核查 / 复现记录。
  · 混合型**以主导内容归类**（证据为主 → 调试记录，步骤为主 → 操作文档）。记录类 frontmatter `type` 词表见 `docs/调试记录/README.md`。
  · **移动/重命名必须同步修正全库引用**（vault wiki 链接 + `docs/` 镜像 + 工程 README），并在提交信息里注明处数；记录类**只增不改历史结论**，订正用"补记"小节并保留原数字与出处。
- 工程状态变化 → 更新本文件「当前工程状态」+ README「当前推进」，并向用户报告一句。
- **文档分工（2026-10-20 定）**：`README.md`=对外门面（工程血缘/快速开始）；`AGENTS.md`=AI 规范权威（§一–§十二）；`docs/README.md`=文档全量索引；vault `agent.md`=会话入口（只放指针，不复制规范正文）。
- **可维护性纪律（2026-10-20 增补）**：单行 ≤800 字符（超长行破坏 diff/检索/阅读；长历史写记录，不堆状态节）；§十 只保留一个「当前状态」块，历史一律用指针。
- **坑账本维护（2026-10-20 拆分）**：全文 `PITFALLS.md`（仓库根）；新增坑只在表尾追加并保持编号连续；`AGENTS.md §九` 只维护索引，不复制正文。

## 九、Correction（坑账本索引；全文见仓库根 `PITFALLS.md`）

> 踩过的坑 = 规范的来源。**#1–#76 的完整「坑 / 根因与修法」已移至 `PITFALLS.md`（2026-10-20 拆分，2026-10-24 续至 #76）**；本节只保留编号+主题索引（长标题截断，全文以 `PITFALLS.md` 为准）。
> 维护：新增坑只在 `PITFALLS.md` 表尾追加（编号连续、不重排、不删旧条），并在此索引加一行。

| # | 主题 | # | 主题 |
|---|---|---|---|
| 1 | 中文路径 Tcl 报 File not found | 35 | BD 模块引用的 OOC 综合 DCP 缓存不随 RTL 变更失效 |
| 2 | XDC 里写 if/foreach 被整段丢弃 | 36 | SmartConnect 的 M01 AXI4-Lite 写转换 × 自研 Lite 从机… |
| 3 | 帧尾总丢 1 字节（FCS 坏） | 37 | AXI 测试 BFM 的两个经典竞态（2026-10-10，两版各踩一次）：①"单拍 va… |
| 4 | 回显帧中段断裂 | 38 | 握手电平请求在 2FF 往返窗口内会被重复执行 |
| 5 | RX 字节「只 1→0」子集损伤 | 39 | axi_interconnect M01 读路径"休眠边界后首笔读重投递上一笔数据"（落后… |
| 6 | PLIDC-10 / REQP-1816 / 1817 | 40 | vivado 批处理抓 ILA 三连坑 |
| 7 | WNS=-2.6ns 假路径罚分 | 41 | Vitis `app create` 不幂等 |
| 8 | MDRV-1 QPLL1LOCK 多驱动 | 42 | Vitis `app build` TCF 通道 reset 后静默空转 |
| 9 | create_project -force 失败 | 43 | 负向对照必须核对"FAIL 的原因是注入的缺陷本身" |
| 10 | fifo_generator set_property 致命错 | 44 | UART 打印行中穿插 AXI 读 = TX 行中后段字节损坏（板上物理层现象）——202… |
| 11 | hw_ila 属性拒绝 | 45 | Git Bash 里 `python` 是 WindowsApps 别名坏壳：静默退出码 … |
| 12 | python 打印 ✓ 崩溃 | 46 | `git ls-files` 默认转义非 ASCII 文件名 ⇒ 以它为输入的一切检查对中… |
| 13 | IBERT 与 Aurora 抢 GT | 47 | 宽归约锥（popcount/校验和）可触发综合器静默误优化——"测量仪器说谎"形态 |
| 14 | 位流断电即失 | 48 | 中断的 xvlog 写坏共享 `xsim.dir` work 库 ⇒ 之后同目录一切 xv… |
| 15 | 真光链路 25 帧后全灭 | 49 | xsct `fpga` 命令 TCF 中途失败（一晚 ×2，均在长时间多轮烧录/stop/… |
| 16 | 文档被截断丢失（README 19 行/待办剩头 20 行） | 50 | Vitis `app build` 增量失效三连（2026-10-16 实证，prj11 … |
| 17 | `.ps1` 在 PS 5.1 下报一堆语法错（不是代码坏了） | 51 | `busy_ms` 型纯软件延时的时基必须在板上标定一次再信（2026-10-16 实证，… |
| 18 | 改完 `.ps1` 后 BOM 又被剥掉 | 52 | 二分归因只做单侧对照 = 必然误判（2026-10-16～17 实证，prj11 R1）：… |
| 19 | XDC/Tcl 行尾 `#` 注释非法 → 那条约束根本没生效 | 53 | Vitis 工程编译的是工程内副本，不是源码目录（2026-10-17 实证，prj11）… |
| 20 | `xdc_lint` 对 GT 参考时钟报 `MISSING_IOSTANDARD`（误报… | 54 | 一次 `stop` 后用 JTAG `mrd` 跨地址连读 M01 不可信（2026-10… |
| 21 | vivado-mcp `start_session` 必失败（`RuntimeError:… | 55 | 共享模块的“退役/删除”必须按实例作用域做——无条件删实例级读 FSM 会让 `HAS_D… |
| 22 | SmartConnect / AXI Interconnect 2023.1 均锁 IP … | 56 | 判据工具自身也是被测件：J3 预热帧在 DMA 模式槽泄漏 ⇒ `wr+255` 级联假 … |
| 23 | 多主共享 AXI 从机时，响应路由按 ID 位区分主 = 必死锁 | 57 | generate/分支内同名声明遮蔽模块级信号 = 静默缺陷（xvlog/xelab 不报… |
| 24 | 脚本以 'w' 模式打开文件后抛异常 = 文档被截断为 0 字节——2026-10-07 … | 58 | Vivado 长构建的 stdout 不要经 PowerShell 管道捕获（`imple… |
| 25 | 多驱动寄存器（同一 reg 被两个 always 块写）= 单元仿真抓不到、DRC 才拦 | 59 | 1-deep 预取流水：fetch 使能必须含“满拍保持拍”门控 |
| 26 | 恒 0/恒 1 的配置输入会把整条分支常量折叠掉 | 60 | “清寄存器”挂在跨条件转移拍 ⇒ 完成条件（FIFO level 比较）被并入宽寄存器 CE |
| 27 | RTL 结构性重排后，单元仿真过、单模块 OOC 综合过，工程级综合仍可能崩（工具级） | 61 | Vivado 安装盘文件偶发读失败（transient）——长构建要带自动重试 |
| 28 | 两个工具级坑（2026-10-08 W5 时序攻坚实证） | 62 | 官方 AI 技能附带的 Python 解析脚本在 Windows 跨盘时崩溃 |
| 29 | 「板内正常」≠「对端收到」：以太网最小帧（runt） | 63 | 项目专用 AI 技能装到全局技能根 = 所有工作区都看到，污染上下文 |
| 30 | 「拒收后不推进指针」的流控在无自动排空模式下必死锁 | 64 | hosted 文档检索的 `family`/`version` 过滤是提示性的，不是硬过滤 |
| 31 | 测上限必须让报价显著高于被测上限 | 65 | Vitis `app build` 在 workspace 元数据损坏时会"静默失败"（不… |
| 32 | 数据通路 TB 必须逐字节校验内容，不能只数帧数/字节数 | 66 | hw-ila 抓取脚本三处官方 API 口径（过去踩错） |
| 33 | RAM 推断对 always 块划分极敏感：把 `ram[addr] <= data` 与… | 67 | Vivado 2023.1 ILA `C_DATA_DEPTH` 合法值最小 1024（5… |
| 34 | 拆分 always 块时必须同时复核驱动归属（拆块与多驱动是一体两面） | 68 | module-ref IP cache 不随 RTL 源文件失效（BD 模块引用会用旧网表） |
| 69 | `is_error=false` 但文本是 `[ERROR]` ⇒ CLI 桥假成功（判据只看传输层） | 70 | CLI 桥一进程一调用 ⇒ 会话类工具在桥下不可用（写单进程脚本/长连接） |
| 71 | DSH 会话里 `pwsh` 中途消失（win-bash 插件 `replacePwsh`）⇒ 改用 `win_bash` | 72 | 2023.1 硬差异：Tcl **8.5.14**、`open_project -noprogress` 不存在 |
| 73 | Win11 `NoDefaultCurrentDirectoryInExePath` 静默挂掉 `launch_simulation` | 74 | `run_tcl` 原始 stdout 不裁剪 ⇒ 单次调用烧 ~8k tokens |
| 75 | `safe_tcl` 占位符必须独占一个 Tcl 词（`X={0}` 会炸） | 76 | 检查类工具默认必须无损：裁剪只能由调用方显式开启（`max_items=0`） |


## 十、当前工程状态（一屏速览；历史详情见附 A 与调试记录）

- ✅ **路线 A（prj10，W0–W6）已收口（2026-10-09）**：DDR 四档逐字节 / 10MB 100%+SHA / 导师四环节 / 死锁专项 / 稳定性 3/3 全过；`prj/project_10/` **目录冻结（只读）**，终版位流 `DBE35734…017F`。详见 `调试记录/` 各记录。
- ✅ **路线 B（prj11，B0–B5 / R1–R4）已收口（2026-10-19）**：round3d 位流 `F6012BA0`（WNS **+0.002** / WHS +0.004）+ 固件 `BA3C0220`；`r2_board.ps1 -Run` **S0–S11 13/13 PASS**（四档 20/20·12/12·12/12·300/300；10MB 7022/7022 + SHA；J3 四链；双桥对账 mem/mem2 各自 wm=wr_frm=rd_frm=9、ost=0、fault=0）。**R3 速率**：1466B 帧可持续 **2000 fps 零丢**、临界 ≈2500 fps、服务上限 ≈2560 fps（≈390 µs/帧；perf2/perf3 A/B 证明瓶颈=每帧软核服务往返，非单点延时；Q5 不要求提速）。**R4**：复现指南 B 章 / 探针清单 / 跨轮归档索引 **33 轮·627 文件·0 缺失**。
- 🧪 **演示固件（2026-10-22，非验收件；当日已回退）**：`B6D3F7B1` 在 `BA3C0220` 同源上仅增串口 `Q`（一行汇总：mode/wr/rd/drop/s2sr 解码/fault/末帧）与 `?`（速查），位流 `F6012BA0` 不变；归档 `prj/project_11/out/archive/fw_q_2026-10-22/`（含 J3 M/A/B 逐轮 + 四档 UDP 日志）。**已在役回退 `BA3C0220` 并跑通 S0–S11（`R2_RESULT: PASS`）**；正式证据仍以 `BA3C0220` 为准。
- ⏭️ **下一步（非强制）**：双板双链路按 2026-09-30 Q4 定案**暂缓**；SG 描述符环提速 / 调度与 FL 负载验证属新范围。
- 🧭 **权威指针**：当前状态=本文件 §十 + `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十九–§二十二；复现=`复现/复现_prj11_指南_2026-10-19.md`；证据索引=`prj/project_11/out/archive/ARCHIVE_INDEX_prj11.md`。

### 附 A · 工程索引详表（内部视角；状态截至 2026-10-19）

| 目录 | 工程 | 状态 |
|---|---|---|
| `prj/project_1/` | MicroBlaze 最小系统 | ✅ M1（08-11） |
| `prj/ibert_ultrascale_gth_0/` | IBERT 眼图 | ✅ 08-27（10G PRBS 跨口过纤 0E0） |
| `prj/aurora_64b66b_loop_ex/` | Aurora 例程 + UART 桥 | ✅ 08-31（内环验证） |
| `prj/project_6/` | 以太网 UDP 网口栈 | ✅ 09-04（ping/UDP/Wireshark 四包链） |
| `prj/project_8/` | Aurora-UDP 数据级桥 | ✅ M2（09-18） |
| `prj/project_9/` | 真光链路版（双笼 A↔B） | ✅ 09-21（WNS +1.006；10MB 100%+SHA 基线） |
| `prj/project_4/` | MIG/DDR4 | ✅ D1 校准（10-06，双位流全绿）；后续 D 线闭环在 prj10 |
| `prj/project_10/` | 内存进环路（路线 A） | ✅ W0–W6 收口（10-09），**目录冻结只读**，终版 `DBE35734…017F` |
| `prj/project_11/` | 路线 B（软核 + AXI DMA） | ✅ B0–B5/R1–R4 收口（10-19），验收对 `F6012BA0` + `BA3C0220` |
| `prj/0DMA_uart2ddr/`、`prj/project_2~3/`、`prj/project_7/` | 参考实现 / 练手 / 挂起 | 🗄️ 归档或挂起（见附 B 与 vault `操作文档/挂起/`） |

### 附 B · docs/ 文档中心指向

- `docs/` = vault 文档的**脱敏快照**（用户名→`***`，人名→`前辈`；`[[双链]]` 保留）；命名 `[阶段]_prj标识_概要_YYYY-MM-DD`；索引 `docs/README.md`（CI 第 6 项强制一致）。
- 关键文档：`导览_cross_已完成工作说明_2026-10-22.md` · `规划_cross_长期路线图_2026-09-04.md` · `追踪_cross_短期待办_2026-10-10.md` · `调试记录/`（结论与证据）· `操作文档/`（照着做）。

### 附 C · 标准开发流程

1. Vivado：设计 → 综合/实现 → Generate Bitstream → Export Hardware（含 bitstream）→ `.xsa`；
2. Hardware Manager：Program Device（成功标志 `End of startup status: HIGH`）；
3. Vitis：更新 `.xsa` → Run Configuration **取消 Program FPGA**（保留 Reset entire system）→ Run → 串口 9600；
4. 批处理：`vivado -mode batch -source <script>.tcl`（幂等脚本在各自 `scripts\`；⚠️ 工作目录必须纯 ASCII）。

## 十一、跨目录约定

- 本文件 = 工程规范权威版；`毕设\agent.md` = 会话入口镜像（冲突以本文件为准并回改镜像）。
- 文档目录（毕设\）的任务清单/路线图随里程碑同步更新。
- 历史协作契约（三层分工、同步中枢）已废弃（2026-09-20），资料存 `毕设\Agent 协作\` 仅供追溯。

## 十二、CI 与远程仓库规范（2026-10-17 增补）

**权威实现**：本地 [`scripts/ci_check.py`](scripts/ci_check.py)，远程 [`.github/workflows/ci.yml`](.github/workflows/ci.yml)——两边跑**同一个脚本**，判据完全一致。本地过、远程挂 ⇒ 先怀疑两边文件集不同（改动未提交、git 未跟踪新文件），不要先怀疑判据。

### 各项检查防什么

| # | 检查 | 防什么 | 关联坑 |
|---|---|---|---|
| 1 | 文档命名规范 | `docs/` 下文件名不合 `[阶段]_prj标识_概要_YYYY-MM-DD`、含空格，导致索引与检索失效 | — |
| 2 | 相对链接可解析 | Markdown 链接/图片指向不存在的文件（断链）；中文名文件曾因 git quotepath 整体漏检 | #46 |
| 3 | Python 语法 | 坏脚本静默入库（编译不过的 .py） | #45（跑脚本判成败的信任前提）|
| 4 | `.ps1` 必须 UTF-8 BOM | PS 5.1 按 CP936 解码无 BOM 中文脚本 ⇒ 一堆假语法错（**不是代码坏了**） | #17 / #18 |
| 5 | Tcl 可解析 | 引号/括号/花括号未闭合的 .tcl（`info complete`）；不含 XDC 行尾注释坑（那是运行期 CRITICAL WARNING，语法层测不出） | #19（同族提醒）|
| 6 | docs/README.md 索引与磁盘一致性（2026-10-17 新增；口径 = docs/ 下除**任意** `README.md` 外的全部 .md） | docs/ 增删文件后索引漂移——列了不存在的文件、或磁盘新文件没进索引 | — |
| 7 | 技能清单一致性（2026-10-24 新增，**本地专用**） | `SKILL.md` frontmatter 与 `MANIFEST.json` 不一致（手改清单 / 技能增删后没重跑生成器）；`baseline` 缺失；`status=verified` 却没有 `tested_on`+`evidence` | — |
| 7a | （状态说明）2026-10-24 起技能实体迁到 `dsh-vivado` 仓库 ⇒ vault 技能目录为空，**检查 7–10 自动 SKIP**；`MANIFEST.json` 作为快照保留，检查 12 仍有效。重生成清单请在 `D:\dsh-vivado` 跑其 `tools/gen_skills_manifest.py` | — |
| 8 | 技能 references 真实存在（本地专用） | SKILL.md 正文引用的 `references/`·`scripts/`·`examples/` 路径指向不存在的文件 | — |
| 9 | 技能内绝对路径存在（本地专用） | 技能里写旧/错路径（真实事故：`D:\FPGA\vivado-mcp` 当运行实例） | — |
| 10 | 技能工具名可解析（本地专用） | 技能声称的工具在本机不存在（真实事故：把条件句「已挂 32 工具」写成事实） | #69 同族 |
| 11 | 镜像门禁（本地专用，取代 2026-10-17 版「只提示」） | `docs/` 快照与 vault 漂移未登记 | — |
| 12 | `agent.md` 技能区块一致性（本地专用） | `BEGIN:skills` 区块过期（MANIFEST 变了、区块没重渲染）、`docs/agent.md` 镜像未同步 | — |

**第 7–12 项 = 本地专用门禁**（2026-10-24 新增）：检测不到本机 vault（`C:\Users\15266\Desktop\毕设\`）时整段 `SKIP`，**远程 GitHub CI 自动跳过**（技能与 vault 都不进仓库——这是刻意选择，代价是远程 CI 只覆盖第 1–6 项）。

- **第 11 项 镜像门禁**（2026-10-24 把原「只提示」升级为门禁）：逐文件比对 `docs/**/*.md` ↔ vault，**两侧先归一**（`15266`→`***`、去 UTF-8 BOM、CRLF→LF）再比字节；归一后仍不等、或 docs 独有而 vault 没有 ⇒ 必须在 `scripts/mirror_allowlist.json` 登记 `{path, kind: drift|docs-only, reason, since}`，**reason 必须可复核**（禁「历史遗留」空话），否则 FAIL。白名单自身也受校验（重复 / kind 与实际不符 / reason 空 ⇒ FAIL；过期条目只 `[提示]`，不卡 CI）。
  > 为什么仍以「归一 + 白名单」而不是「零字节 diff」：`docs/` 是 vault 的**脱敏快照**，「字节不一致」在很多情况下**是设计结果**（vault `C:\Users\15266\…` ⇄ docs `C:\Users\***\…`）。零 diff 只能靠取消脱敏实现，等于把用户名写进 git 历史。
- **第 12 项**把 `agent.md` 的 `BEGIN:skills` 区块也纳入门禁：该区块是 `MANIFEST.json` 的派生物，由 `scripts/render_agent_skills_block.py` 渲染（`--write` 同时把 vault `agent.md` **脱敏**写成 `docs/agent.md`；`--check` 即本项判据）。⇒ 改技能后固定两条命令：`py scripts\render_agent_skills_block.py --write`（vault 侧 MANIFEST 已是冻结快照，重生成清单改到 `D:\dsh-vivado` 用它自己的 `tools/gen_skills_manifest.py`）。
- ⇒ **纪律：绝不「为了对齐」把 vault 原文覆盖进 docs/**（会把用户名等敏感信息写进 git 历史）；确实要同步时：内容更新以「更晚、有实测证据」的版本为准，**同步后必须重新脱敏**，同步完再跑门禁。

### 本地怎么跑

```
py scripts\ci_check.py        # 或 §三 记录的全路径解释器；退出码 0 = PASS
```

- ⚠️ **Git Bash 里的 `python` 是 WindowsApps 别名坏壳**（静默退出码 49）——判成败只信脚本自身退出码，勿经管道（坑 #45）。
- 改完任何文档/脚本后，**提交前必跑一次**；位流/日志等 .gitignore 项不参与检查，不要试图入库。

### 远程 workflow 何时触发

- **push 到 master** / **PR 目标 master** / 手动 `workflow_dispatch` 三种触发；运行于 ubuntu-latest + Python 3.12 + tclsh，**job 超时 15 分钟**。
- 全程只用 **Python 标准库**，不安装任何第三方包；第 5 项的 Tcl 解释器探测顺序是 **`tclsh`（PATH）→ Vivado 自带 `bin\unwrapped\win64.o\tclsh*.exe`**（后者自动补 `PATH=<Vivado>\lib\win64.o` 与 `TCL_LIBRARY=<Vivado>\tps\tcl\tcl8.5`，否则报 `0xC0000135` 缺 DLL）；两者都没有才 `[跳过]`。
  > 2026-10-25 修正：旧实现的探针是 `tclsh "<<exit>>"`，任何**存在**的 tclsh 都会因读不到这个「文件」而非 0 退出 ⇒ 永远 `[跳过]`。现在探针改为 `input="exit 0"`，并优先复用 Vivado 自带的 8.5.14（与工具内解释器同版本）。

### 失败时怎么定位

1. 输出按 `[i]` 分组、逐条列出文件与原因——先对号入座是哪类检查。
2. **链接失败**：相对路径基准 = 当前文件所在目录（不是仓库根）；中文文件名从磁盘复制，勿手敲。
3. **命名失败**：对照 §八 规范；豁免仅 `README.md` / `agent.md` / 非 Markdown 数据文件；工程内部 docs/ 不受约束。
4. **Tcl 失败**：查引号/括号/花括号闭合；注释一律独立成行（行尾 `#` 是非法的，坑 #19）。
5. **BOM 失败**：改 `.ps1` 后必须复验前 3 字节 = `EF BB BF`——编辑工具会静默剥 BOM（坑 #18）。
6. **索引失败**：docs/ 有增删 ⇒ 同步更新 `docs/README.md` 的全量索引表。

### 新增文档/脚本时的自检清单（提交前过一遍）

- [ ] 文档命名合规（§八）且放对目录（操作文档/ vs 调试记录/，按主导内容归类）
- [ ] Markdown 相对链接（含图片）指向真实文件
- [ ] 新建 `.ps1` 带 UTF-8 BOM；**改动过**的 `.ps1` 复验前 3 字节
- [ ] 新 `.tcl` 引号/括号闭合、注释独立成行；可 `tclsh <file>` 干跑一遍
- [ ] 新 `.py` 可编译（`py -m py_compile <file>`）
- [ ] docs/ 有增删 ⇒ 同步 `docs/README.md` 索引（CI 第 6 项会拦）
- [ ] 本地 `py scripts\ci_check.py` 退出码 0