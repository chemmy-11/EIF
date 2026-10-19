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
- [§十一 跨目录约定](#十一跨目录约定) · [§十二 CI 与远程仓库规范](#十二ci-与远程仓库规范)（**CI 五+1 项检查各防什么、本地怎么跑、新增文件自检清单**）

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
| JTAG | 调试烧录用 Digilent USB-JTAG（210512180081）；串口 FT2232H-B COM7 | hw_server 实测 |
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

**背景**：2026-10-18 接入 AMD 官方 Ross 技能包（Vivado：elaboration 日志分析 / RTL lint / 时序方法学 / 工程交接 / 仿真排错 / ILA·VIO 手册）与官方文档检索（hosted `amd-doc-search`）。二者是**知识与流程层**；执行层仍是本仓库 `vivado-mcp/`（32 工具）+ xsct + 自研脚本——**装了技能不等于多出 Vivado 工具**。

| 资产 | 位置 | 作用域 | 现状 |
|---|---|---|---|
| 项目级 AI 技能（7 个：6 官方 + `amd-doc-search` 桥） | `<vault>\.dsh\skills\`（vault = `C:\Users\15266\Desktop\毕设\`） | **仅本工作区**（DSH `projectRoot/.dsh/skills`，rank 100） | 已生效（热加载）；全局技能根 `~/.agents/skills` **不放**任何 Vivado 技能（2026-10-18 用户定案，避免污染其他 Agent 上下文） |
| 官方文档检索（原生 MCP） | `~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-amd-doc-search` 条目 | DSH **web profile 全局**（所有工作区；重启 `dsh web` 后生效） | 已配置；工具名 `mcp__amd_doc_search__vivado_doc_search` |
| 官方文档检索（项目桥） | `<vault>\.dsh\skills\amd-doc-search\doc_search.py` | **仅本工作区** | 已生效：`py doc_search.py "<query>"`（stdlib 直连 MCP，无需重启） |
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

## 九、Correction（坑账本：踩过的坑 = 规范的来源）

> 2026-10-12 规范化：条目按编号升序；统一三列格式（原两列式条目按首个「——」拆分，#22/#23 尾注并入第三列）；同族条目互见——#16↔#24 文档截断族、#17↔#18 PS BOM 族、#33↔#34 always 块拆分族、#41↔#42 Vitis 构建族、#32↔#48 仿真库状态族；已闭环条目保留不删（#36 已注 10-11 板上复验闭环）——教训仍是规范来源。

| # | 坑 | 根因与修法 |
|---|---|---|
| 1 | 中文路径 Tcl 报 File not found | GBK 码位问题；官方位流拷到 ASCII 路径再操作 |
| 2 | XDC 里写 if/foreach 被整段丢弃 | XDC 是受限 Tcl；逻辑放 build 脚本 |
| 3 | 帧尾总丢 1 字节（FCS 坏） | 帧泵 `rd_empty` 误用 `rd_bin_next` 提前判空——用当前 `rd_bin`（prj8 commit ae40965） |
| 4 | 回显帧中段断裂 | unpack 对帧中断流敏感——改整帧存储转发（09-10） |
| 5 | RX 字节「只 1→0」子集损伤 | 2023.1 吸收 BUFIO，IDDRE1 挂 BUFGCE 全局钟压位边界——FIXED IDELAY 1250ps×5 + IDELAYCTRL（065ee78/66ff43d） |
| 6 | PLIDC-10 / REQP-1816 / 1817 | IDELAY 必须配 IDELAYCTRL，其 RST 不得接地也不得直连 LOCKED——用 clk200 打拍同步链 |
| 7 | WNS=-2.6ns 假路径罚分 | 探针跨域采样 + 缺时钟组声明——mark_debug 标域 + set_clock_groups |
| 8 | MDRV-1 QPLL1LOCK 多驱动 | Aurora 核 `gt_pll_lock` 是输出口，外部不可驱动（42f0ba2 踩坑实录） |
| 9 | create_project -force 失败 | 残留 vivado 进程锁 runs 目录——先 Stop-Process vivado |
| 10 | fifo_generator set_property 致命错 | 参数名臆造（Write_Depth_Flag 等）不存在——只设有把握的参数 |
| 11 | hw_ila 属性拒绝 | TRIGGER_POSITION 不被接受——省略或 catch 包裹 |
| 12 | python 打印 ✓ 崩溃 | GBK 控制台——`PYTHONUTF8=1` |
| 13 | IBERT 与 Aurora 抢 GT | 同一 GT 通道不能二者并存——换装位流或用同 quad 空闲通道 |
| 14 | 位流断电即失 | JTAG 烧录易失——每次上电重烧（board_test 一键脚本兜底） |
| 15 | 真光链路 25 帧后全灭 | 帧泵 wr_full 二进制/格雷混比，跨 2048 回绕永久伪满——标准 Cummings 格雷满 + 帧原子性 + 复位对称（f7c8be8）；板上必现→仿真复现→修复三连 |
| 16 | 文档被截断丢失（README 19 行/待办剩头 20 行） | AI 会话"部分读取(limit)后整体回写"= 截断事故——**写前必须全量读取并校验 totalLines 一致**；重要文档靠 git 历史 rescued（b8ae05c）；vault 无版本控制，重建需标注 |
| 17 | `.ps1` 在 PS 5.1 下报一堆语法错（**不是代码坏了**） | 本机 shell = Windows PowerShell **5.1 Desktop**，`-File` 读**无 BOM** 的中文 `.ps1` 按 **ANSI(CP936)** 解码 → 中文串 UTF-8 字节把紧跟的单引号当双字节第二字节吞掉 → 字符串未闭合。实测：`verdict_capture.ps1` 前 3 字节 `35 32 61`(无 BOM) → `ParseFile` **6 真错误**；同目录 09-21 在用的 `storm_demo.ps1` = `239 187 191`(有 BOM) → **0**。⇒ **本仓库 `.ps1` 约定 = 带 UTF-8 BOM**。该文件因此**在 PS 5.1 下从未成功执行过**（连损坏前版本也不行）——排查时先验 BOM，别先怀疑逻辑 |
| 18 | 改完 `.ps1` 后 BOM 又被剥掉 | **编辑工具/文本重写会静默剥掉 BOM**（2026-10-01 实证：5 处定点 edit 后前 3 字节从 `239 187 191` 变回 `35 32 61`，`ParseFile` 0 → 27 错）。⇒ **任何 `.ps1` 改动后必须复验前 3 字节 = 239 187 191**，且**解析判据要用 `[Parser]::ParseFile`（= `-File` 的真实读法）**，只用显式 UTF-8 的 `ParseInput` 会给出"逻辑 0 错误"的**假安全**（同一文件两种读法一个 0 一个 27） |
| 19 | **XDC/Tcl 行尾 `#` 注释非法 → 那条约束根本没生效** | Tcl 里 **`#` 只在「命令行首」才是注释**；写在命令**行尾**的 `#` 会被当成**多余参数**传给命令 → `[Common 17-165] Too many positional options when parsing ...` **CRITICAL WARNING，命令失败**。prj9 实证：`xdc/aurora_udp_bridge.xdc:92` 的 `set_false_path ... # prj9: 通配符覆盖 _0 与 _1 双核` 未生效（该文件 40 处行首注释均合法，**行尾注释全文件仅此 1 处 ↔ 构建日志恰好 1 条 CRITICAL WARNING**，一一对应）。⇒ **XDC/脚本里注释一律独立成行**；排查「约束怎么没生效」先数 Too many positional options |
| 20 | `xdc_lint` 对 GT 参考时钟报 `MISSING_IOSTANDARD`（**误报，别照改**） | `gt_refclk_p/n`（T6/T5 = MGTREFCLK1_X1Y2）是 **GT 专用引脚**，不需要也不应写 IOSTANDARD。事实源：官方 GT Wizard 例程 `gtwizard_ultrascale_0_example_top.xdc` L56-57 **同样只写 `package_pin`**（而同文件对 `sys_clk`/`sfp_rs` 等普通 IO 都写了 IOSTANDARD）；prj9 同写法综合日志 **0 条 NSTD-1/BIVC-1**。⇒ 见此类告警**先判端口是否为 GT 专用脚**，是则忽略 |
| 21 | **vivado-mcp `start_session` 必失败（`RuntimeError: Vivado GUI 进程提前退出`）** | 0.3.26 把「`vivado_mcp_server.tcl` 的路径」写进一个只含 ASCII 的临时 `.tcl`（`D:\FPGA\tmpXXXX.tcl`）交给 `vivado -source`，而 **Vivado 的 Tcl 按系统 ANSI(GBK) 解码该文件** → 安装路径里的「毕设」解成「姣曡??」→ `couldn't read file ... no such file or directory`。与 #1 同根（GBK 码位）。**修法 = 把整个安装搬到纯 ASCII 路径**（2026-10-01 实做：`C:\Users\15266\Desktop\毕设\.mcp-pilot` → `D:\vivado-mcp`，含 venv+site）；`C:` 侧旧路径留转发壳。**注意 mcp 包自身的 `_check_ascii_paths` 已经把非 ASCII 路径列为红线**，但只查 vivado_path 与 cwd，**查不到包安装路径**——所以这条只能靠安装位置保证 |
| 22 | **SmartConnect / AXI Interconnect 2023.1 均锁 IP Integrator** | 独立 Tcl `create_ip` 生成产物为**空壳**（实测 BD 内只有 aclk/aresetn，无任何 AXI 端口）；SC 改全局综合模式（`generate_synth_checkpoint false`）后 wrapper 与内核端口又不一致。**修法 = 自研仲裁器**（`prj_loop/rtl/axi_arb_2to1.v`，事务级轮转 + 单元仿真）；若必须用 IP 互联，只能在 Block Design 内创建（W4 六轮构建实证，2026-10-06/07） —— AXI 互联选型：两主一从同域场景自研 ~200 行可控可仿真，比 BD 引入便宜 |
| 23 | **多主共享 AXI 从机时，响应路由按 ID 位区分主 = 必死锁** | W4 仲裁器按 `bid[0]/rid[0]` 路由，但两桥例化同一 `axi4_master_bridge`（awid/arid 硬编码常量 4'h0/4'h1），MIG 回声 ID 后**所有写响应涌向桥①、所有读响应涌向桥②**，板上必挂（T22/T23 可能照常亮、ping 可能过，UDP 回显必挂——"看起来活了"最危险）。**单元 TB 掩盖路径**：arb_tb 给两主手工喂不同 ID + T4 读数据回传置 0 跳过。**修法 = 响应路由按内部授权锁存（wbusy&wgrant / rbusy&rgrant），与响应 ID 彻底解耦**（2026-10-07 上板前审查拦截，联合仿真负向对照复现死锁证明可检出；证据 `prj/project_10/sim/w4_joint_run.log`） —— 系统级组合必须配系统级 TB：单元全绿 ≠ 集成不死锁；负向对照（故意例化缺陷副本必须 FAIL）是防"判据恒真"的标准动作 |
| 24 | **脚本以 'w' 模式打开文件后抛异常 = 文档被截断为 0 字节**——2026-10-07 实证：`io.open(P,'w',...,newline='\\\\n')` 的 newline 值非法触发 ValueError，但 **'w' 已在参数校验前完成截断**，J4 验证单正文瞬间清零（幸有 `docs/` 当日镜像可恢复）。**修法 = 改文档一律「先构造完整新内容 → 写临时文件 → os.replace 原子替换」，断言放在写之前；newline 参数用 `chr(10)` 不手写转义** | 与 #16（部分读取后整体回写）同族；凡"脚本写文档"都要走临时文件+原子替换，且改完必须回读校验长度与关键标记 |
| 25 | **多驱动寄存器（同一 reg 被两个 always 块写）= 单元仿真抓不到、DRC 才拦** | 2026-10-07 实证：`cmd_channel.v` 的 `cmd_hold` 被「解析块置位 / 执行块清零」两个 always 驱动，`xsim` 单元 TB（含 40 条随机命令 + 负向对照）**全过 0 errors**，但综合后在 `opt_design` 报 `[DRC MDRV-1] Multiple Driver Nets`，实现直接中止。**根因**：Verilog 允许多块写同一 reg（仿真按最后赋值/竞争裁决），**只有综合/DRC 才判非法**。**修法**：置位与清零分属两块时，必须拆成「单驱动标志 + 单拍握手」（本例：执行块拉 `cmd_take`，解析块见 `cmd_take` 清 `cmd_hold`）。**纪律：任何 RTL 改动在单元仿真之后必须过一次综合（或至少 `opt_design`）才能宣告可用**——"仿真 PASS" 不等于"可实现" |
| 26 | **恒 0/恒 1 的配置输入会把整条分支常量折叠掉 | 于是"从没被时序覆盖过的死逻辑"，一旦接活就崩**——2026-10-07 实证：`frame_mem_if.cfg_mode` 在 W2–W4 一直硬接 `1'b0`，桥内整条 RND 读决策分支被综合折叠，历次 WNS 记录（含 W4 的 +0.008）**都不包含它**；W5 把真 `cfg_mode` 接上后，该锥实测 **4.226ns vs 3.333ns**（`rc_data→eff_slot→full_bit[eff_slot] 256:1 分布式 RAM 查表→stat_ill_rd CE`，300MHz ui 域），全设计 4040 端点失败（WNS -1.142 / TNS -1094.6）。**判据**：①「模式位恒 0」的功能是**未经时序验证的功能**，启用前必须单独跑一次实现的时序判读（不能引用历史 WNS）；②裁剪周边负载（本例外：裁 96bit ILA 探针）与换实现配方都无法救「组合锥本身超预算」，**先量最差锥的 logic/route 占比再决定是否拆拍** |
| 27 | **RTL 结构性重排后，单元仿真过、单模块 OOC 综合过，工程级综合仍可能崩（工具级）** | 2026-10-07/08 实证：`axi4_master_bridge` 新增一个流水状态（R_PRE2，把范围判决寄存后再查表）后，Vivado 2023.1 工程级综合 **3 次可复现崩溃**（`EXCEPTION_ACCESS_VIOLATION`，位置固定在 `Mimic Skeleton from Reference` 之后，`hs_err_pid*.log` 无栈可看），而**同一文件单模块 OOC 综合通过**、四份仿真全绿；**回退该结构后同工程立即通过**（唯一变量）→ 判定为工具级触发而非 RTL 非法。**处置纪律**：① 判别用 `sim/mini_synth_check.tcl`（单模块 OOC 综合，约 1 分钟）二分“纯 RTL 问题 vs 与全工程组合触发”；② 排除环境脏（清 `.Xil`、删 run 目录）后再判定；③ **RTL 重排后必须先跑一次工程级综合（约 1 分钟见 `SYNTH_STATUS`）再投入 40 分钟完整构建**；④ 崩溃结构备份留证（本例 `sim/axi4_master_bridge_cut2_synth_crash_repro.v`），不要在同一条结构上反复对赌 |
| 28 | **两个工具级坑（2026-10-08 W5 时序攻坚实证）** | **①「接常量」做不了 RAM 读出路径的对照实验**：`u_rd_cmd`（4×9 命令 FIFO）被综合成 LUTRAM 宏（RAMD32），**宏对常量传播不透明**——把 `cfg_mode/cfg_rd_slot` 全接常量（完全复刻 W4 接线）后 `cmd_rnd`/`p_in_rng` 仍是活信号、锥原样存活（实测 −0.473/−0.297，与锥完整版同级）；**要验证某条读路径是否根因，必须做结构性移除（从 RTL 删掉），不能接常量**。**②寄存镜像必须 (* keep *)**：为把 256:1 `full_bit` 树从两个 FSM 的 CE 路径上摘掉做了 1 拍晚镜像 `full_bit_q`，不加 keep 时**综合器把镜像合并回原树**（路径里直接出现 `w_slotfull_i_87` 读 full_bit），**两轮构建 WNS 精确同为 −0.121、收益归零**；加 `(* keep = "true" *)` 后 **+0.001 达标**（差 0.122ns）。**判别法**：改完看最差路径列表——若源头信号没变，优化被合并/撤销了 |
| 29 | **「板内正常」≠「对端收到」：以太网最小帧（runt）** | 2026-10-08 实证：W5 命令通道应答帧长 58 字节（不含前导码）< 以太网最小帧 64 字节，**网卡在硬件层静默丢弃**：板内 ILA 显示 resp_busy 高 68 拍、66 字节完整发出、FCS 经独立参考 CRC + 残差校验通过、`cmd_err=0`，而 PC **一个包都收不到、网卡错误计数也为 0**。协议层「常识约束」（最小帧 / IFG / 前导码 / CRC）必须写进测试：单元 TB 此前只校验了字段与 FCS，**唯独没校验最小帧长**。修法：按 RFC 894 追加填充（不计入 IP/UDP 长度，仅参与 FCS），并在 TB 加护栏 + 旧 RTL 负向对照 |
| 30 | **「拒收后不推进指针」的流控在无自动排空模式下必死锁** | 2026-10-08 实证：W5 RND 模式（桥① 不自动读）下，写槽号取自**提交计数** `stat_wm`，而 `stat_wm` 只在 B 响应时 +1；一旦游标推进到某个未读满槽即被拒、游标不动 ⇒ 后续每帧都指向同一满槽 ⇒ **永久卡死**；同时 user 域**接受计数** `u_wr_frame` 继续 +1 而 `stat_wm` 不动（ILA 实测 334 vs 278 = 发散 56 帧）⇒ 上位机按「写槽 = 帧计数 mod 256」算出的槽号全错 ⇒ 连解锁所需的槽号都推不出来 ⇒ 不可恢复。**两条通则**：①「接受计数」≠「提交计数」，跨域计数器暴露给上位机时必须钉死语义与差值来源；②任何流控指针在拒收路径上也必须推进（否则在无自动排空的模式下必死锁）。修法：独立槽游标 `wr_slot_ptr`，提交计数语义不变 |
| 31 | **测上限必须让报价显著高于被测上限** | 2026-10-09 实证：测板卡帧率上限时用 pace=20µs 发帧（PC 上限 50k fps），128B 档的板卡真实上限（≥117k fps）被 PC 限速遮住，线性拟合于是把 PC 的节拍拟成了板卡的固定开销（20.3µs 假象），据此先做了只动固定项的 L2（无效）。换 pace=5µs 重测后固定项修正为 ~7µs，主要矛盾其实是字节项，修复方向随之转向 L1。任何上限/拐点测量，先确认激励源的量程覆盖被测上限 |
| 32 | **数据通路 TB 必须逐字节校验内容，不能只数帧数/字节数** | 2026-10-09 实证：L1 泵第一版每帧丢首字节（86→85B）且整体左移一位，帧数对 + 总字节=帧数×常数 两项检查全部通过，只有逐字节比对才抓得住。配套：xvlog 报 ERROR 后 xelab 仍会用旧快照 Built 并跑出结果——仿真脚本必须把 xvlog 非零退出当硬失败（串联判断或显式退出），否则会拿旧编译产物骗自己 |
| 33 | **RAM 推断对 always 块划分极敏感：把 `ram[addr] <= data` 与 FSM 寄存器赋值放进同一个 always 块，Vivado 会放弃 BRAM 推断变成触发器阵列** | 2026-10-09 实证：L1 帧泵的 4096×8 RAM 合并进 FSM 块后，失败路径目的地显示为 `u_pump_rev/ram_reg[3748][7]/D`（**FDRE 触发器**，不是 BRAM），时序 −0.169，且两次构建后诱发 MIG 缝合崩溃。修法：把 RAM 数据写拆回**独立 always 块**（照原版模式），日志里应能看到 `ram_reg_bram_0 (implemented as ...)`。判据：**综合日志里必须出现 `*_bram_*` 实体名**，否则 RAM 没推断出来 |
| 34 | **拆分 always 块时必须同时复核驱动归属（拆块与多驱动是一体两面）** | 2026-10-09 实证：为解决 #33 而拆出独立 RAM 块时，顺手把 `wr_addr <= wr_addr + 1` 也搬了过去，于是 `wr_addr` 被两个 always 块驱动（= 坑 #25 的教科书复现），而 **TB 照样 PASS**（多驱动仿真能过、DRC 直接挂）。拆块后必查：①每个 reg 的赋值点是否都在同一个 always 块；②综合日志 `MDRV` 计数是否为 0 |
| 35 | **BD 模块引用的 OOC 综合 DCP 缓存不随 RTL 变更失效** | 2026-10-11 实证：axi_lite_regs.v 修复后重建，`reset_run synth_1` 不级联 `mb_ctrl_*` OOC runs，烧上的仍是旧网表（板上现象不变才暴露；DCP 时间戳停在修复前）。**修法**：build 脚本显式 `foreach mr [get_runs -quiet -filter {NAME =~ <bd>_*}] { reset_run $mr }`。**判别法：改了 RTL 重建后板上行为不变，先查 OOC DCP 时间戳** |
| 36 | **SmartConnect 的 M01 AXI4-Lite 写转换 × 自研 Lite 从机在真硬件上交互楔死** | 2026-10-10/11 板上实证：TB 三种 AW/W 到达次序全绿、真网表确认入流、未映射地址写返回 DECERR 正常、同 SmartConnect 的 UARTLite(M00) 写正常——**唯独写 M01 上的自研从机挂死整条总线**（JTAG mrd 全通、mwr 即挂、后续读 overrun）。板下不可复现（问题在真硬件转换器行为）。处置：换 axi_interconnect（M1 本板验证过），**2026-10-11 板上复验闭环（自检 PASS + JTAG mwr 第三源）**。**教训：跨 IP 边界的协议组合仿真过≠板上过，必须有独立取证通道（本轮=JTAG mwr/mrd + 未映射地址差分）** |
| 37 | **AXI 测试 BFM 的两个经典竞态**（2026-10-10，两版各踩一次）：①"单拍 valid 脉冲"在 DUT 未 ready 的时钟沿丢事务（隔笔丢、表现为交替旧数据）；②"等 ready 再撤 valid"在 ready 波形与采样沿错位时活锁（无限受理）。**标准形=negedge 驱动 + negedge 上确认 ready=1 后才让 valid 覆盖下一 posedge**。配套 RTL 侧教训：**从机 ready 在接受拍同拍拉低（`<=1` 后 `<=0`）= 电平轮询主机永远看不到高** | 受理后进忙碌态再撤 ready |
| 38 | **握手电平请求在 2FF 往返窗口内会被重复执行** | 2026-10-10 实证：user 域执行 FSM 只看 `req_s[1]` 电平、执行完立刻回 IDLE，同步器撤销延迟窗口内同一命令每拍执行一次（脉宽监视器抓到 9 次脉冲）。**修法=cmd_channel 的关闭态纪律必须复刻：执行后停在 CLOSE 态等 `!req_s[1]` 再回 IDLE** |
| 39 | **axi_interconnect M01 读路径"休眠边界后首笔读重投递上一笔数据"（落后一笔）** | 2026-10-11 板上实证（prj11 J_B1）：M01 上自研 Lite 从机的读，在总线休眠边界后的第一笔会返回**上一笔 M01 读的数据**，随后背靠背读全新鲜；边界实证三类：UART(M00) 打印流量后、JTAG↔CPU 主机切换后、纯 CPU 长间隙后。**~~双读丢弃不可靠（第二笔仍陈旧）~~ / ~~写打头 100% 治愈~~ ——2026-10-17 复查推翻这两句**：固件 `U` 探针（软核自视同址连读）实测形态＝**序列首笔可能取到上一笔事务的值，同址连读第二笔即新鲜**（`R_ID` 首读 `0x17`，其后 5 读恒 `0x50314231`）；哑写并非必要。「写打头治愈」当年只在"边界后首笔"验证过，未覆盖"空闲环里每笔都插一笔哑写"的形态——从机 RTL 七套 TB 全绿 + 4 相邮箱逐行复核无缺陷，现象指向 interconnect 转换层/主机侧排队残留。**修法=软件 `rd_reg()`：先向被忽略偏移窗口哑写（OKAY 应答、零副作用）再读**；稳态轮询（B2 工作形态）观察全部正确，根治需 ILA 挂 Lite 总线 AR/R 信号（现 ILA 探针只有内部状态量，需重建位流） |
| 40 | **vivado 批处理抓 ILA 三连坑** | 2026-10-11 实证：① `wait_on_hw_ila` **无超时参数、触发条件不满足即永久阻塞**——触发必须选**恒真探针**（如已翻转的 owner 位），选了会翻转的信号（rx_tvalid）链路静默时直接挂死 batch；② 批处理下 `get_property VALUE $probe` 对多数探针**不填充**（GUI 才有）——正确做法 `upload_hw_ila_data` → `write_hw_ila_data -csv_file` 导出后离线解析；③ `get_hw_ilas <名字>` 匹配不到（hw_ila_N 编号与 ltx 名无对应）——**遍历 ILA 用 `get_hw_probes -of_objects` 反查含目标探针的那个** |
| 41 | **Vitis `app create` 不幂等** | 工程已在 workspace 时报 "A project with given name already exists"，即使脚本自称 set -force 重建（force 只对 platform 生效）。**修法=拆两个脚本**：首建 build_sw.tcl，改源后 rebuild_sw.tcl（copy main.c + `app build`，秒级）；勿每次重走 platform create（分钟级且撞名） |
| 42 | **Vitis `app build` TCF 通道 reset 后静默空转** | 2026-10-11 实证：IDE.log 出现 `ERROR : xsct server communication channel has closed unexpectedly`（发生在 "Checking for BSP changes" 阶段）后，`app build` 无报错返回、脚本 `J3_DONE` 照打，但 Debug/ 下**没有任何 .elf**（仅 makefile 骨架+部分 .d）。**判别法：构建后必须 `ls *.elf` 非空再信**。修法：进 Debug/ `make all` 直跑（PATH 补 `D:\Xilinx\Vitis\2023.1\gnu\microblaze\nt\bin` 与 `gnuwin\bin`），秒级、无 TCF 依赖 |
| 43 | **负向对照必须核对"FAIL 的原因是注入的缺陷本身"** | 2026-10-11 实证：Mock 注入"槽不退休"缺陷时把退休开关写反（`fresh[s] = defect != "noretire"`），结果正常模式变"永不退休"、缺陷模式反而正常；byte/order 缺陷轮的 B 轮 FAIL 是被这个反逻辑**误伤**，noretire 缺陷实际从未生效，而表面矩阵"有红有绿"看起来很健康。**纪律：每个注入缺陷的 FAIL 输出要指认到具体判据行/错误类别（如 bytediff、B-DUP-UNEXPECTED），且缺陷不影响语义的轮（如 noretire×主轮）应当 PASS——命中面精确才是判据健康** |
| 44 | **UART 打印行中穿插 AXI 读 = TX 行中后段字节损坏（板上物理层现象）**——2026-10-12 实证（prj11 J_B2）：`uputs(...) uputd(rd_reg(...))` 夹在字符之间的行**必挂**（'I' 快照行 `drop=` 后必丢、数字错位，4/4 稳定复现；JTAG 直读同址亦见错位数据），而 READY/DONE 等纯打印行（值已在局部变量）完好。根因同 PDRC-203：UART 引脚与 DDR4 校准 bitslice 同组，AXI 读突发把 UARTLite TX 拖进校准窗。**修法=先读完所有寄存器再一次性纯打印**（打印期间零 AXI 流量）；配套两条：①行式协议的接收端"超时丢弃残包"必须先解析**遗留缓冲里的完整行**（否则完整行在下一次超时被当残包丢弃——143 字节 DONE+进度行全被吃掉的实证）；②RX 侧幻影单字节（与打印突发相关）可用**补码对协议**（c,~c）防误触发 |
| 45 | **Git Bash 里 `python` 是 WindowsApps 别名坏壳：静默退出码 49、无任何输出** | 2026-10-12 实证：`python <任何参数>` 无输出退 49 ⇒ 一切"跑脚本看结果"的判断失效（曾把 CI 通过误判为通过；`python ... \| tail; echo $?` 拿到的是 tail 的退出码，假象放大）。**修法：调用一律用全路径解释器 `C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe`；判成败直接看脚本自身退出码（勿经管道）；对"无输出"必须存疑** |
| 46 | **`git ls-files` 默认转义非 ASCII 文件名 ⇒ 以它为输入的一切检查对中文名文件静默跳过** | 2026-10-12 实证：`ci_check.py` 的命名/链接检查因路径变成 `docs/\350\247\204...` 转义串、`Path.exists()` 为假，对 docs/ 下**全部中文名文档**长期漏检（镜像断链因此未暴露；修复后立刻抓到 4 处命名 + 2 处断链）。**修法：`git -c core.quotepath=false ls-files`（ci_check.py 已修）；凡"拿 git 输出喂路径逻辑"的地方都要过这一关** |
| 47 | **宽归约锥（popcount/校验和）可触发综合器静默误优化——"测量仪器说谎"形态** | 2026-10-13 实证（prj11 B3-1a）：sink 用 64 位 popcount(function+for) 计 TKEEP 字节数，Vivado 2023.1 综合报 **14 条 [Synth 8-6858/6859] multi-driven net Q**（1st driver = 该寄存器，混入别模块单元名），最终 **"保留常量驱动、忽略寄存器驱动"** —— keep_n 被静默置 0、整条 tkeep 链（含 `dma_tkeep` 全部网络）被删。特征：**DMASR/beats 计数全对、唯独该计数恒 0**（仪器说谎而非功能挂）；对照无该模块的旧构建 **CW = 0**。**判别法 = checkpoint 取证**：`open_checkpoint` 后 `get_pins`/`get_nets` 查目标网络的驱动/负载是否还在；**防法 = 把宽归约换成比较/计数结构**（本题改为"全有效拍计数+尾拍采样+粘滞位"）；**构建间对比 CW 数**是锁定引入源的最快指标 |
| 48 | **中断的 xvlog 写坏共享 `xsim.dir` work 库 ⇒ 之后同目录一切 xvlog 100% CPU 无限自旋（进程活着、零输出、零报错）** | 2026-10-15 实证（prj11 B3-1b）：v3 编译检查被强杀后，后续 `xvlog`（含 run_bridge_dma_tb.bat 全链）在 sim/ 目录**永不返回**——换空目录编译**同一文件集 1 秒通过**（判别法：空目录复跑 + 进程 CPU 满载但库文件停在半写态）。**修法：全部 `run_*.bat` 跑前 `if exist xsim.dir rmdir /s /q xsim.dir`（9 个脚本已统一，重编秒级）；纪律：xvlog/xelab/xsim 不在中途强杀，必须中断时先杀进程树再清库**。与 #32（xvlog 失败仍用旧快照）互为"仿真库状态"族 |
| 49 | **xsct `fpga` 命令 TCF 中途失败（一晚 ×2，均在长时间多轮烧录/stop/con 之后）** | 2026-10-16 实证：报 `process_tcf_actions ... invoked from within "fpga"` 后 JTAG 枚举空，hw_server 重启无效；**断电重上即恢复**。模式：长时间 JTAG 活动后链路状态劣化，与 wedge ×2（DMA 密集场次后不可响应）可能同族——**待归并**。纪律：连续多轮 JTAG 会话后若 `fpga` 失败，直接断电复位，勿反复重试 |
| 50 | **Vitis `app build` 增量失效三连**（2026-10-16 实证，prj11 R1）：①源已换但 ELF hash 不变（时间戳判断失效，app build 静默不重编）——**改 ELF 后必须核对产物 hash 变化**；②PowerShell `git show > file` 重定向把文本写成 **UTF-16**（尾部 `xx 00` 模式），损坏源码进编译链——**取历史文件一律用 `git checkout <commit> -- <path>`**；③Eclipse workspace 项目注册的文件级删除不可恢复（删 `.metadata/...projects/<name>` 后 `app create` 仍报 already exists）——**恢复法 = 新目录 `setws` + `importprojects <项目路径>` 再 `app build`**（10-16 实证可用）。与 #41/#42 同为 Vitis 构建族 |
| 51 | **`busy_ms` 型纯软件延时的时基必须在板上标定一次再信**（2026-10-16 实证，prj11）：`n = ms×100×33` 中 ×33 系数来历不明，反汇编乘法链确认生成 `ms×3300`；循环体 4 指令 ≈45ns ⇒ 实测 **busy_ms(1) ≈ 0.15ms（比设计快 6.6×，不是慢）**。曾在未实测时两次错判（"慢 25×"写进记录被实测推翻）。**纪律 = §6a 硬规则 5：延时/速率类代码上线前用可观测事件标定真实时长**；本条与 #47 同族（测量仪器/标定量说谎） |
| 52 | **二分归因只做单侧对照 = 必然误判**（2026-10-16～17 实证，prj11 R1）：现象「换回归档 ELF 就恢复」曾直接写成「判定为软核侧问题」，但那次恢复**同时换了位流与 ELF**——被固定的变量只有「现象」，没固定「位流」。10-17 做 2×2（位流 ± × ELF ±）才定案：**退役位流 `3aa600aa` + 归档 ELF 应答正常；绿位流 `708f15a4` + 驻留 ELF `f8175c32` 静默** ⇒ 责任在固件、退役位流洗清；原 `[L1]` 假说「退役位流读 `UART_ST` 恒 0」随之证伪。**纪律 = §6a 硬规则 2：怀疑「A 还是 B」时矩阵四格全跑、每格只改一个变量；对照的恢复动作若同时动了两个变量，该对照无效** |
| 53 | **Vitis 工程编译的是工程内副本，不是源码目录**（2026-10-17 实证，prj11）：`sw/src_j3/main.c` 是源码出处，但 `j3_soft` 工程实际编译 `sw/j3_soft/src/main.c`（`Debug/sources.mk` 的 `SUBDIRS` 只含 `\src`，编译行是 `../src/main.c`）。只改源码不同步副本 ⇒ 两次「重建」产出**完全相同的 ELF hash**（`f8175c32`），差点把旧二进制的行为当成新构建的行为。**纪律 = §6a 硬规则 4 的产物 hash 校验，且改 SW 后先确认「编译输入文件」是哪一个**；本工程固化为四步：「改 `sw/src_j3/` → 复制到 `sw/j3_soft/src/` → 删 `main.o`+`*.elf` → `make` → 核对 hash」 |
| 54 | **一次 `stop` 后用 JTAG `mrd` 跨地址连读 M01 不可信**（2026-10-17 实证，prj11）：连续读 7 个 M01 地址时值与地址错位（`0x44A10000` 读到 `R_ID` 的魔数 `50314231`、`0x44A00034` 也读到同一魔数），同址连读两次即稳定——与坑 #39 同源（一笔滞后），但在调试通道上表现为「随机乱值」。**纪律：取多地址状态时每地址先哑读一次再取第二笔；跨地址连读的结果不得单独作为判据** |
| 55 | **共享模块的“退役/删除”必须按实例作用域做——无条件删实例级读 FSM 会让 `HAS_DMA=0` 的实例死锁/无源** | 2026-10-17 实证（prj11 R1）：8afa168 在 `axi4_master_bridge.v`（`u_mem`/`u_mem2` **两实例共用**）里把 R_PRE 的 `else if (dma_engine)` 改成无条件 DMA 并删 R_AR/R_R/R_UNPACK/R_FIN ⇒ `HAS_DMA=0` 的桥②（`u_mem2`，无 DMA shim）读 FSM 永泊 `R_DRET`（`shim_frame_done` 在 `gen_no_dma` 分支无驱动恒 0）+ 读数据口无源（`brf_wr_en` 无人置位）⇒ 泵B 无输入、出向帧不上线。ILA 前后对照：旧位流桥② 写帧 +4/读帧恒 0/ost 19→23；修复位流 读帧 +4/ost 恒 0。**修法 = 读 FSM 按 `HAS_DMA` 参数化门控（`HAS_DMA=1` DMA-only / `HAS_DMA=0` 恢复硬件读）+ `shim_frame_done` tie-0**；修复版 `c8cd3a32` S0–S8/四判据全过。**纪律 = 删逻辑前枚举全部实例与参数化差异；结构差异用参数守卫、不用运行态位（`dma_engine`）**。详见记录 §三之二十 §2/§3/§9-②③。 |
| 56 | **判据工具自身也是被测件：J3 预热帧在 DMA 模式槽泄漏 ⇒ `wr+255` 级联假 FAIL；失败不得重试** | 2026-10-17 实证（prj11 R1）：绿位流 `--dma` 下 J3 四链连续三次 `[M] wr+255`（写少 1 帧）→ 读阶段不启动 → 槽满级联 FAIL；根因 = `scripts/j3_soft_verify.py` 的 `run_round()` 在 SEQOK 后无条件发 1 个预热帧，DMA 模式下该帧读请求永泊 `R_DRET` 占 1 槽（软核正停在 `round_command` 等 GO、驻留服务不在跑），写阶段第 256 帧槽满被拒；桥模式由硬件读引擎自动退休故 PASS。**修法 = `warm_probe=(not args.dma)`（`--dma` 跳过预热帧）**，复验 `green_dma_j3_run5_warmfix.log` PASS；修复版位流 S8b（带 `--dma`）M/A/B 全 PASS。附纪律：J3 必须**新烧录后**跑；跑前 `'S'`+只读检查 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍（清槽）；**`wr+255`/收帧停摆不得重试**（级联假 FAIL + 可能半楔死需重烧）；轮末 `R_ENGINE=0`/`R_MODE=RND` ⇒ 后续 ping 判据重发 `'d'`/`'S'`。另：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ **NIC 主判据用 `ReceivedBytes`**（单帧 74B / 4 帧 296B），`ReceivedUnicast` 恒 0 不可用。详见记录 §三之二十 §4.2/§9-⑧⑨。 |
| 57 | **generate/分支内同名声明遮蔽模块级信号 = 静默缺陷（xvlog/xelab 不报错、综合 0 CW）** | 2026-10-17 实证（prj11 R2）：`axi4_master_bridge.v` 的 `generate if(!HAS_DMA)` 新分支内又声明了 `reg [15:0] wr_slot_ptr`，新写引擎只驱动**局部副本**，而读 FSM 的槽域判决（`c_clamp`/`c_in_rng`/`p_target_ok`）用**模块级副本** ⇒ `HAS_DMA=1` 时模块级游标无驱动（仿真 X / 综合常量）⇒ 所有 DMA 读请求按"无帧"应答（J3/E/四档读路径必挂）。**xvlog 对遮蔽不报错、综合 0 CW**，只跑编译/综合会全绿。**纪律 = ①删旧逻辑或搬 generate 前 `grep 'reg .*<name>'` 确认声明唯一；②白盒 TB 对关键状态加 `$isunknown` 断言；③"编译通过/综合 0 CW/TB 部分通过"不等于语义正确，共享模块退役必须有独立审计**。详见 `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §四 A1。 |
| 58 | **Vivado 长构建的 stdout 不要经 PowerShell 管道捕获（`implement_debug_core` 会 spawn 子 vivado，管道组合可能死锁）** | 2026-10-17 实证（prj11 R2 首轮 sweep）：`vivado -mode batch ... 2>&1 \| Select-String ... \| Select-Object -Last N` 运行中，`implement_debug_core` 子进程（`.Xil/Vivado-<pid>/dc_drv.0/dc/debug_ip_core.tcl`）在生成完 4 个 ILA IP 后**停滞 >14 分钟且 CPU 不再增长**（父等子、子 stdout 被管道缓冲堵住）；杀进程重跑、stdout 改为文件重定向（`cmd /c "vivado ... > out\log 2>&1"`）后同一阶段约 3 分钟通过、整轮正常。**纪律 = 长构建一律 `> logfile 2>&1` 落文件，再用 `Select-String` 读文件**（与 §四"日志落文件再检索"同源）。本轮为一次对照、机理未逐层取证 ⇒ `[L1]`；再遇优先按本条绕开。 |
| 59 | **1-deep 预取流水：fetch 使能必须含“满拍保持拍”门控** | 2026-10-18 实证（prj11 R2 round2）：字节捕获流水首版 `wd_fetch` 缺 `!wd_beat_full`，满拍保持拍（`byte_valid_q=1 && beat_full=1`）继续 fetch 覆盖跨拍预取的下一字节 ⇒ **每个非末拍 64B 边界丢 1 字节**；len≥66 帧尾拍永不满足 → 56ms 看门狗 HALT。证据 [L2]：T1 len=64（单拍无跨拍预取）PASS 对照 T2 len=70 未提交 / T3 idx=1 自 k=64 逐字节错位（`got[k]=exp[k+1]`）；修法 `wd_fetch` 加 `&& !wd_beat_full` 后全过。**纪律 = 流水/预取类改造必须构造“跨边界”用例（len=64±k、背靠背帧），单拍用例会漏**。 | 2026-10-18 |
| 60 | **“清寄存器”挂在跨条件转移拍 ⇒ 完成条件（FIFO level 比较）被并入宽寄存器 CE** | 2026-10-18 实证（prj11 R2 round2b→2c）：30/30 最差路径 = `u_wr_bytes/wr_gray_s2`→gray2bin→`rd_level`(3×CARRY8)→`wd_data_r[*]/CE`；根因 = `WD_WAITGO` 完成条件 `wf_level>=wd_len` 同拍清 512 位 `wd_data_r/wd_keep_r`（clear-on-transition）⇒ level 比较锥并进 512 CE。修法 = 拆 `WD_ARM` 独立一拍，用**状态译码**清零，比较只驱动 `wdst`（3 FF；HALT 编码保持 6，每帧 +1 拍）：WNS **−0.127 → +0.004**。**纪律 = 转移拍不要清宽寄存器；CE 尽量只依赖状态译码（FF），完成条件只进状态寄存器**。 | 2026-10-18 |
| 61 | **Vivado 安装盘文件偶发读失败（transient）——长构建要带自动重试** | 2026-10-18 实证（prj11 R2 白天）：同一综合脚本先后遇 `versal_hdmi_tx_ss/bd.tcl: invalid argument`、`tcllib1.11.1/yaml/yaml.tcl: no such file`、ddr4 IP `Failed to deliver file(s)`；文件实际存在、无残留进程、重试即过（本轮第 2/4 次成功）。**纪律 = 综合/实现批处理加自动重试包装（如 `out/r2_synth_retry.ps1`，最多 4 次并记录 try 次数），不要把瞬态误判为设计/脚本缺陷**。 | 2026-10-18 |
| 62 | **官方 AI 技能附带的 Python 解析脚本在 Windows 跨盘时崩溃** | 2026-10-18 实证：AMD `vivado-rtl-elaboration-analysis` 的 `parse_elab_messages.py` 用 `os.path.relpath(filepath, output_dir)` 把源文件路径转成相对输出目录的路径；源日志在 `D:`、输出 CSV 在 `C:` 时**抛 `ValueError: path is on mount 'D:'`，整份报告中止**（本轮实测写成 3 行后崩溃；同目录 elab 日志 452 条本应全量输出）。**修法 = `try/except ValueError` 保留绝对路径**（`<vault>\.dsh\skills\vivado-rtl-elaboration-analysis\parse_elab_messages.py` 已打本机补丁，`install_skills.py` 可重放）。**纪律 = 跑官方脚本先做日志副本、输出落同盘或先打补丁，不在 prj 目录原地跑** | 2026-10-18 |
| 63 | **项目专用 AI 技能装到全局技能根 = 所有工作区都看到，污染上下文** | 2026-10-18 实证：DSH 技能根按 rank 扫描——`<projectRoot>/.dsh/skills`(100) → `.agents/skills`(200) → custom(300) → `~/.dsh/skills`(400) → `~/.agents/skills`(500) → bundled(600)；`projectRoot` = 最近含 `.git` 的祖先，无 `.git` 用 cwd。曾把 6 个 Vivado 技能装进 `~/.agents/skills`（rank 500 全局用户根）⇒ 所有工作区会话技能目录都多出约 2 KB 描述。**修法 = 项目专用技能一律放 `<workspace>\.dsh\skills`（项目级、随 workspace 走、`watch:true` 热加载）；全局根只留跨项目通用技能** | 2026-10-18 |
| 64 | **hosted 文档检索的 `family`/`version` 过滤是提示性的，不是硬过滤** | 2026-10-18 实测：按 `family=["Kintex UltraScale+"]`、`version=["2023.1"]` 查询，返回结果仍混有 `family: All` / `version: All` 的通用条目（ILA 手册、chipscopy、AR 等）。**纪律 = 不能凭"加了过滤参数"就声称结果已限定器件/版本；引用前逐条核对返回块的 `family:`/`version:` 字段**（§6a"判据未触发≠通过"的变体：过滤参数≠过滤结果） | 2026-10-18 |
| 65 | **Vitis `app build` 在 workspace 元数据损坏时会"静默失败"（不编译不报错）** | 2026-10-18 实证（prj11 R2 诊断固件）：改完 main.c 跑 `rebuild_j3.tcl`（xsct `app build`），日志只打印 J3_DONE 但 ELF 时间戳/hash 不变；`sw/IDE.log` 显示 `ERROR : xsct server communication channel has closed unexpectedly`，`.metadata/.log` 有 `Build step failed, canceling full build chain`（`j3_soft_system` 项目元数据丢失）。**判定法**：比对 ELF hash/时间戳 + `mb-nm` 查新符号；**修法/兜底**：`D:\Xilinx\Vitis\2023.1\gnuwin\bin\make.exe -C j3_soft\Debug all`（PATH 加 `gnu\microblaze\nt\bin`）——手编会把真实编译错误打出来（本次即靠它发现注释块内插代码导致的语法错）。坑 #53/#54 同族：构建脚本"看起来成功"必须用产物 hash 验证 |
| 66 | **hw-ila 抓取脚本三处官方 API 口径（过去踩错）** | 2026-10-18 对照官方 `hw-ila-debug` 技能修正：① 基本触发必须显式 `set_property CONTROL.TRIGGER_MODE BASIC_ONLY` + `CONTROL.TRIGGER_CONDITION AND`（多 probe 的 `TRIGGER_COMPARE_VALUE` 才按 AND 合成）；② **`wait_on_hw_ila -timeout N` 的单位是分钟**（不是秒；旧脚本传 30 会挂 30 分钟）；③ `write_hw_ila_data -csv_file` 用**基名**（不带 `.csv`）。官方比对值语法 `eq<width>'<radix><value>`。证据：`out/evidence_2026-10-18/tools/r2_ila5_capture.tcl` 修正 + 参考文档 §3.1 |
| 67 | **Vivado 2023.1 ILA `C_DATA_DEPTH` 合法值最小 1024（512 非法）** | 2026-10-19 实证（prj11 R2 round3b）：为省 300MHz 面积把 `u_ila_5` 深度设 512，综合阶段 `open_run` 后 `create_debug_core` 报 `[Vivado 12-206] Invalid value '512' for 'C_DATA_DEPTH'. Valid values are 1024 2048 ...`，4 次重试全败；改回 1024 即过。⇒ 降 300MHz ILA 压力时**只能从 2048→1024**（ILA3 本轮即如此），不能低于 1024；要再省只能裁 probe 或换更小核 |
| 68 | **module-ref IP cache 不随 RTL 源文件失效（BD 模块引用会用旧网表）** | 2026-10-19 实证（prj11 R2 round3c）：`axi_lite_regs.v` 在 10-18 有 fix1/fix2 两次修改，但 round2f/round3/round3b 位流的 synth 日志均读 `mb_ctrl_axi_lite_regs_0_0_9/...dcp`；旧 IPCACHE `1f8570ac…` 文件 mtime=**10-17 22:22:03**、`stats.txt` NumberHits=19/最后命中 **10-19 00:10:59（=round3b 构建）** ⇒ **fix1/fix2 从未进入任何位流**，板上表现为 lite 总线协议违例（读回冻结/UART 静默）。**判别法**：build 日志中 module-ref IP 目录 `<N>` 的 dcp mtime 应晚于对应 RTL mtime；或查 `vivado/gen/…/ip_cache/…/stats.txt` 命中历史。**修法**：改 module-ref RTL 后**重新 generate BD**（实例号会 +1、`IPCACHESYNTHCRC` 改变），或删 cache / `config_ip_cache -disable_cache`；`reset_run`+`MODULE_REF_RESET` 只刷新 OOC run，**不足以**让 IP cache 失效（与坑 #35 同族） |



## 十、当前工程状态（一屏速览；内部详表见本节附录）

- 🔄 **路线 B / `prj/project_11/` 进行中（2026-10-10 起，最新 10-16）**：**B0** 断点核查与 fork 脚手架（10-10）→ **B1 软核控制面集成**（`axi_lite_regs`（W5 语义 Lite 从机）+ mb_ctrl BD + owner 最近写者仲裁；七套回归全绿；J_B1 板上三步全过 **`[B1-SELFTEST] PASS (0 errors)`** + ILA 九项交叉一致；位流 `d14425f2…`）→ **B2 J3 软核验证**（UART 两段协议 + `scripts/j3_soft_verify.py`（`--mock` 全绿）；**J_B2 板上三轮全 PASS**：逆序对 24905/0 缺 0 多 0 字节差；板上实证三段缺陷链：read_line 遗留缓冲 / RX 幽灵字节 / 打印穿插 AXI 读）→ **B3-0 延迟可观测**（桥内 `lat_w`/`lat_r` 饱和计数 + 双回读路 UDP `GET_LATENCY(0x05)` / 软核 Lite `+0x20/+0x24`；板上 128 帧采样 **Lw 中位 97 拍 0.32µs、Lr 中位 23 拍 0.08µs**，`LAT_BOARD: PASS` ⇒ **B3 硬阻断（真 MIG Lw/Lr 实测）闭合**）→ **B3-1a DMA 集成**（BD 加 `axi_dma`（512b MM2S、控制 100M/数据 300M 双时钟域）+ `dma_sink` + `dma_rd_shim` + 三主仲裁器；`DMA_SMOKE PASS` + 四档基线前后双跑零回归；根因定案 = axi_dma 512b 数据通道**确定性装配偏移**（非故障，判据预补偿）；坑 #47 宽归约锥静默误优化）→ **B3-1b 双读引擎 + v3 结构重构**（10-14～16：DMA 服务机制全通、**AR 无偏移定案**、槽存完整 ETH 帧（−8 窗口）；0 回显链收敛到「shim 输出域被综合器改写」⇒ **v3 职责剥离**：shim 只发字节流 + `frame_done`，描述符改由桥 R_DRET 自发射；离线回归全绿（shim/shim_drop/bridge_dma/arb3/lite/cmd/sink/W2/W4）；**v3 位流 `a432addd…a023`（WNS +0.004 / WHS +0.004）/ xsa `03c90cdd…`**，归档 `out/archive/b31b_board_2026-10-15/`，提交 `fa9ed97`）→ **10-16 v3 板场次**：烧 `a432addd` + ELF `0f4f0bd3` ⇒ **四档零回归 PASS**（20/20 · 12/12 · 12/12 · 300/300）+ **DMA_SMOKE PASS**，但 **'E' 轮 4 次全 FAIL（0/16 ×3、单帧 0/1）⇒ v3 未消除 0 回显**；同帧 A/B 对照（桥模式 16/16 逐字节回显 vs E 模式 0/16）**计数签名逐项一致**（`up_frames/up_bytes/echo_b_rx/echo_b_tx` 各 +20，ovf/stall/err 全 0）⇒ 缺陷在**内容**不在通路/长度；E-EMIT `len = 载荷+54`、byte0 = PC MAC 首字节稳定正确；PC 网卡零到达且错误计数 0 ⇒ **根因重定向到「DMA MM2S 在 base=SA 的字节映射 / DROP_BYTES 口径」**；证据归档 `out/archive/b31b_board_2026-10-16/`）→ **同日第二轮取证（只重建 ELF `03d456ef`，位流不动）**：新增软核命令 `'F'`（`SA−64/SA/SA+64` 三点各做一笔 MM2S 64B，回读 `dma_sink.q1` = 流首拍 4 字节）⇒ `SA+64` 点命中末帧帧内偏移 56 ⇒ **流起点 = 帧首前 8 字节 ⇒ `DROP_BYTES=8` / `DMA_LENGTH=len+8` 口径实测正确，DMA 映射嫌疑证伪**；最小帧对照（2B 载荷 → 帧 44B 补齐 60B、`len_tab=72`、传输 80B = 2 拍）**桥模式回显 `aa55` ✓ / E 模式 0 回显 ✗** ⇒ **损坏在帧首字节之后**（拍内 lane 4..63 或拍间字节流 —— `dma_sink` 只能看 lane 0..3 的盲区）→ **同日第三轮：发射字节流探针定案（v5 位流 `442ca75a`）**：给 `u_ila_0` 新建 probe1（`dbg_mem_rden`+`mem_rd_data[7:0]`，复用既有检查点只跑 impl，**WNS/WHS 仍 +0.004**）⇒ 同一帧两模式各捕获一次（总长均 **1526B = len_tab**）：**桥流 =【8B 以太网前导+SFD (`55×7,D5`)】+【帧】+【FCS】**（回显 YES）vs **E 流 =【帧】+【FCS】+【8B 垃圾】**（回显 NO）⇒ **0 回显根因 = `DROP_BYTES=8` 把槽内存开头的以太网前导+SFD 丢掉、`DMA_LENGTH=len+8` 又多读 8B** ⇒ 上线无前导 ⇒ 接收侧 MAC 无法定界 ⇒ 静默丢弃（与"三类计数全对、错误计数 0、`E-EMIT` byte0=0x08 正确"完全自洽）。**修复已实施**：`rtl/axi4_master_bridge.v` 用 `DROP_BYTES(0)` + `sw/src_j3/main.c` 用 `DMA_LENGTH = len` ⇒ DMA 发射流与桥引擎逐字节同构；探针已固化进 `scripts/build_debug.tcl`（probe1 + place 指令 `ExtraPostPlacementOpt`）；v3 位流与 pre-fix RTL 快照归档 `out/archive/v3_bit_a432addd_2026-10-16/` 可回滚 → **同日修复板级验证（v5-SW，无需重建位流）**：`DMA_SA = 槽基址-8` + `DMA_LENGTH = len+8`（配 `DROP_BYTES=8` 位流；前移 8B 让"被丢的 8B"落在前导之前）⇒ **'E' 轮 `ECHO: 16/16` 逐字节回显 + `B31B_E_ROUND: 0 errors`（该判据首次跑绿）** + **四档零回归 PASS**，发射流恢复【8B 前导+SFD】+【帧】+【FCS】与桥流同构（`E-EMIT` byte0 `0x08`→`0x55`）。等价形态 v5-RTL（`DROP_BYTES=0` + `LEN=len`）位流被时序门限拒（−0.017/−0.185），`build_v5_sweep.tcl` 指令扫描进行中；**软核口径必须与位流 DROP 配对**（配对表见记录 §三之十二）→ **最终口径收敛 = v5-RTL（同日 16:2x）**：指令扫描第一轮 `place -directive ExtraTimingOpt` 过门限（**WNS/WHS +0.004**）⇒ 位流 **`708f15a4`**（`DROP_BYTES=0`）/ ltx `352a5f28` / xsa `6a0af1ef` + 软核**单一口径**「基址对齐 + `LEN=len`」（ELF `c13a54f5`）⇒ **四档零回归全 PASS + 'E' 轮 16/16 逐字节回显 + 桥/E 发射流都以 8B 前导开头、1526B 同长逐字节同构**；v5-SW 保留为"不便重建位流时的等价应急口径"；最终配置归档 `out/archive/b31b_v5rtl_2026-10-16/` → **B3-1c 功能闭包（同日）**：`sw/src_j3/main.c` 加 `'d'`（读出引擎切换命令）+ `serve_dma_once()`（等 sticky 请求 → 编程 MM2S（v5-RTL 配对 SA=槽基址/LEN=len）→ 等 Idle → 等退休），并在 `run_round()` 逐槽等待里逐笔服务 ⇒ **RND 也走 DMA 描述符**；`scripts/j3_soft_verify.py --dma`（幂等切引擎）复跑四条链：**M `wr+256 rd+256 inv=16260 miss=0 extra=0 bytediff=0` PASS · A `rd+255 miss=1`（恰缺帧#5100）PASS · B 重读槽无产出 PASS**（ELF `4b463f93`，位流沿用 `708f15a4`）⇒ B3-1c **行为面收口**；剩「退役桥②读引擎」（删 `R_AR/R_R/R_UNPACK/R_FIN` + 输出 mux → 重建位流 → 四档 + 四条链复跑，届时 DMA 为唯一读路径）→ **退役尝试（同日傍晚）**：RTL 已删硬件读路径 + 引擎 mux（shim 唯一消费者）、`bridge_dma_tb` 按新架构改造后 **PASS（0 errors）**、位流 **`7064368d`**（首掷 −0.068 被拒 → 重掷 `ExtraTimingOpt` **+0.004**，体积小 ~0.9MB）；但**板验暴露基线回归：板卡不再应答 ARP ⇒ ping 不通** ✗。**根因（代码级）**：**栈自发帧也走内存环路**——`stack_txd/stack_tx_en`（eth 栈产生的 ARP/ICMP/命令应答）经泵A 写入 DDR（`aurora_mem_bridge.v` L108/L756），其读回同样依赖读出路径；退役后必须由软核编程 MM2S，而软核**只在轮次内服务** ⇒ 应答出不去；另 `dma_tready = dma_engine_ui ? shim : sink`（L290）在退役后必须**恒接 shim**。**已恢复绿配置**（烧回 v5-RTL `708f15a4` + ELF `c13a54f5` ⇒ ping ✓ + M 轮 `inv=30897` PASS ✓）。**退役前置两件**：① `dma_tready` 恒接 shim；② 软核驻留服务（主循环空闲即服务 sticky 请求）或保留一条硬件读路径专服务栈自发帧；W2/W4 两个 TB 因此失效（驱动已退役路径）→ 改造成 DMA 版为待办 → **10-17 日场 L1 假说检验（2×2，记录 §三之十八）**：位流 ± × ELF ± 四格全跑 ⇒ **退役位流 `3aa600aa` 配归档 ELF `c13a54f5` 应答正常（`LAT w=68 r=0`），绿位流 `708f15a4` 配驻留 ELF `f8175c32` 静默** —— **退役位流洗清、责任归位固件**，§三之十七 的 `[L1]` 假说「退役位流读 `UART_ST` 恒 0」**证伪**；本轮另排除 LMB 容量（15.6KB/64KB）、DMA 覆写软核段（槽基址 `0x00100000` vs LMB ≤`0x10000`）、构建-源不一致（`j3_soft/src/main.c` ≡ `src_j3/main.c` = `6ea72c5c`）、链接脚本差异（两 ELF 节布局/VMA 一致）；→ **同日（10-17）根因定案并修复（记录 §三之十九）**：新增固件 `'U'` 探针（软核自视连读 `R_ID/R_DMAREQ/R_WM_WR/UART_ST` 各 6 次）实测 M01 读形态 = **一笔滞后、同址连读第二笔即正确**；驻留空闲环里 `serve_dma_once()` 的 `rd_reg(+0x34)` 含**哑写 0x2C**，而 `urx_poll()` 原为**单次读** `UART_ST` ⇒ 每笔都落在「紧跟写之后的第一笔读」位置 ⇒ `RX_VALID` 恒 0 ⇒ **软核收不到任何字节 = 串口静默（与位流无关）**。修复 = `urx_poll()` 同址双读（`UART_RX` 必须保持单读，双读会吞两字节——本轮实踩一次，ELF `597ef983` 全哑）；**ELF `24eb49c7` 复验：绿位流与退役位流在 `'d'` 切 DMA 后串口均即时应答 ⇒ 退役位流首次具备可用控制面 `[L4]`**。遗留三项：①退役位流 **ping 0/3 且 PC 网卡计数 delta=0**（绿位流对照 3/3）⇒ 栈自发帧没上线 `[L3]`；②因 ARP 不通、PC 发不出 UDP 数据帧 ⇒ **四判据在退役位流上尚未取值**（广播直发探测既无回显也无 `wm_wr` 增长 = 判据未取得，§6a 硬规则 3）；③（**已撤销**）所谓「J3 `--dma` 基线冲突」是我的参数误用——板端 `NSLOTS` 编译期固定 256，`--nslots 64` 只改 PC 侧期望；按默认 256 复跑，桥引擎与 DMA 引擎**两种模式三链全 PASS**（`[M] inv=26057/25472`、`[A] miss=1` 恰帧#100、`[B] inv=25665/25092`），另有 `manual_round.py` 手动轮 `wr+256 rd+256 stall=0` + 256/256 回显旁证；④**缺陷已锁进退役 RTL**：`'d'` 现在同时写 `R_ENGINE`（ELF `4aac46be`），**绿位流 engine=1（驻留服务）ping 4/4 ✓，退役位流同固件同开关 ping 0/3、PC 网卡 delta=0 ✗** ⇒ 同一驻留服务在绿位流可用、退役位流不可用 ⇒ 差异在退役 RTL；`full_bit` 退休清零与 `out_dec` 均正常，候选收敛到「shim 结算 ↔ `frame_mem_if` 读出端口」，需 ILA 取证
- ⏭️ **路线 B 收口后剩余（2026-10-19 重审，官方知识库核对）**：R2 已收口（上条：round3d `F6012BA0` + S0–S11 13/13）。剩余仅 **≈1 天**：**R3 速率量化**（0.5 天，板场次；`json_storm --chunk 1466` pace {1000/200/13}µs + 0 参考档 → fps–失配腿点；归因**修正**：本工程 `C_INCLUDE_SG=0`=Direct Register Mode **无描述符**（PG021），`s2mm_introut` **未接 MB 中断**（BD 无 intc，固件轮询 DMASR）⇒ 瓶颈=每帧软件服务/轮询，**不是**"描述符/中断开销"；82.67k fps 系 prj10 旁路帧泵基线，仅作差距参照）+ **R4 文档收口**（0.5 天；复现指南 B 章 / prj11 探针-计数清单（移植 w6_inventory 思路，非搬 prj10 三件套）/ 跨轮归档索引 0 缺失 / AGENTS+记录+docs 同步）。**已结项**：D1（W2/W4 TB 改造已由 10-17 端口 tie + 回归完成，且 `r2_wr_tb` PASS）、K2（wedge 根因=IP cache 陈旧，坑 #68）、`mentor_verify --ctl soft` 判据不存在（B2 已由 `scripts/j3_soft_verify.py` 落地，S9 覆盖）。**D2（坑#39）**降为可选诊断并入 R3。**论文口径待对齐**：开题 4.2 "AXI DMA+描述符环" vs 实现 Direct Register Mode（建议写"首版直接寄存器 + SG 为后续演进"）；开题时间线"双板双链路" vs 2026-09-30 Q4 单板定案。详见记录 `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` **§二十一** 与剩余清单 **§七**。
- 🔄 **路线 B / R2 桥①写侧换层 S2MM（2026-10-17 晚～10-18，位流已出、板验待上电）**：设计 v1.2 / 实现落地（`HAS_DMA` 参数化、桥② 写读零改动）/ 请求-GO-ACK-introut 协议 / fail-stop 同前；**独立审计 A1–A19 全闭环**。**round2c 位流过时序门限**：`ExtraTimingOpt` 后布 WNS +0.042 → 尾判 **+0.004 / WHS +0.004**、DRC **0 Errors / 22 Warnings**、`V5_SWEEP2_OK`；修复链 = ①字节捕获 1 级流水（审计抓 A16“跨拍预取覆盖”后修复，坑 #59）②`WD_ARM` 拆拍把 FIFO level 比较从 512 CE 移走（坑 #60）③ILA 裁剪（ILA1/2 整核移除、ILA0 374→92、ILA3 184→152；缺失探针列=INFO/判据未取得）。产物：bit **`28921C6B…324627`**（10,266,180 B）/ ltx `4AC25546…`（审计 ltx 实物逐项核对 92/9/152 通过）/ xsa `16A4F01F…` / ELF `1bc8088d`；归档 `out/archive/b31b_r2_2026-10-18/`（**27 项清单 + SHA256.txt（28 文件）**，清单自身 SHA256 `73FB1AAE…`，清单头 A19 已修）；**S0 已钉且 dry-run PASS**（WNS/WHS/DRC/hash 全过）。**板验待用户上电**：烧归档绝对路径 bit+ELF → S0–S11（S4 单帧 86B 尾拍逐字节 + S2MM DMASR；`dbg_s2mm_state` **7=ARM 正常/6=HALT fail-stop**；`fault` 全程 0）。RTL 冻结 blob **`f43267db`**。详见 `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十。**round2c 后继续（10-18 下午/晚间）**：lite_regs AXI 协议修复（`d133b508`→fix2 `d5d16d46`）、写引擎 fix2 `c92c20c7`、round2f 位流 `8A8FE378` **过门限 +0.004** 并上板：**S0/S1/S3 PASS**，AXI 楔死定位到 lite_regs 写后紧接读、用 GO 后 1ms 间隔规避；写/读数据面计数推进（wm/rd_frm=5/5）；但 **PC 仍收不到帧**（`r2_tx_probe`=NO_FRAME），**R1 绿位流对照 ping 4/4** ⇒ 问题在 R2 数据面（写流首拍/前导/TKEEP 待证）。round3 加 `u_ila_5@ui` 写流探针（64/8/1/1/1）+ ILA0 写入口 9b（92→101）+ lite fix2 `d5d16d46` 后构建 **WNS=-0.002 / WHS=+0.004（差 0.002ns）⇒ NO_BITSTREAM 未收口**（归档 `out/archive/b31b_r2_2026-10-18_round3/`）。按用户要求断电收尾，**本轮板验未完成**。**新会话入口 = `操作文档/阶段三_prj11_R2板验续作交接单_2026-10-18.md`**；下一步 = 构建（ILA5 1024→512 / ILA3 2048→1024 后重掷）→ 板验最小序列 → ILA5 首拍抓写流（期望 beat0 `0xD555555555555555`/tkeep=FF）→ 修数据面 → S0–S11 + 四档/10MB/双桥对账。**10-19 00:36 round3b 位流 PASS**：lite fix2 `d5d16d46` + `u_ila_5@ui` 写流探针（64/8/1/1/1，深 1024）+ ILA0 101b（92b 旧位序不变），ILA3 深降 1024；`ExtraTimingOpt` 首掷 **WNS=+0.004 / WHS=+0.004**（`V5_SWEEP2_OK`）；bit **`02F7153A`**（9,996,016 B）/ ltx **`0B2CC2F5`**（84,582 B，3 核）/ xsa `95E1D156` / 诊断 ELF `16D06BD3`；归档 `out/archive/b31b_r2_2026-10-19_round3b/`（含 BUILD_STATUS）。**板已断电收尾** ⇒ 待上电按 BUILD_STATUS §4：'d'→'W'（期望 s2sr=0/s2len=0）→ ping→'W'（期望 s2len=86/s2sr=0x1002）→ ILA5 首拍（`0xD555…`/tkeep）判写侧。官方工具定位（PG021/PG022 + 官方 axi_dma IP 仿真 `TEST_PASS`）见 `out/evidence_2026-10-18/R2_official_tool_diagnosis_20261018.md`。详见记录 §十二–§十七。**✅ 10-19 R2 收口（round3c/round3d）**：① 楔死根因 = **module-ref IP cache 陈旧**（lite fix1/fix2 从未进旧位流；BD regen 后新 cache 才真综合当前 RTL）——坑 #68，`[L2 强推断]`；② **隔帧 50% 丢帧根因 = 固件读服务 `MM2S_DMACR.Reset` 连带复位整个 AXI DMA**（PG021 原文直证），S2MM 变 Halted ⇒ 下一帧 `S2MM_LENGTH` 写 no effect ⇒ 无 introut ⇒ 桥 WAITDONE 超时 → WD_HALT → 故障恢复 → 隔帧循环；**修复 = 固件 `s2mm_rearm()`（零 RTL 改动）**，50%→100%；③ round3c-diag 位流 `9852016C`（WNS +0.004）上首次全通四档/10MB+SHA/J3；④ **round3d 验收位流 `F6012BA0`（9,288,496 B，WNS **+0.002**/WHS +0.004/DRC 0E，ltx `2F8AF498`：ILA0 110/ILA3 **152**/ILA5 47、xsa `216839F4`、验收固件 ELF `BA3C0220`）→ `r2_board.ps1 -Run` 完整 **S0–S11 13/13 PASS（`R2_RESULT: PASS`，run3 16:42–16:46）**：S6 双桥差分各 +4/ost=0；S7 四档 20/20·12/12·12/12·300/300；S8 10MB 7022/7022 + SHA256 一致（独立复算）；S9 J3 M/A/B 全 PASS；**S10 双桥对账 mem/mem2 各自 wm=wr_frm=rd_frm=9、ost=0、stall/len_err=0、wr_fault=0**；S11 sticky=0**。工具维护（判据逻辑零改动）：`r2_counter_recon.py` recon 补打 `R2_RECON_RESULT` marker、`j3_fourchains.ps1` R2 口径、`r2_ilacap.tcl` 探针 5→9、S0 用 `r3d_s0_buildlog_adapter.py` 适配 `V5_SWEEP1_OK`。证据：`out/evidence_2026-10-19/R3D_S0-S11_run{1,2,3}.log` + `EVIDENCE_INDEX_r3c.md` + `tools/r3c_pin.md`；记录 §十八–§二十。**R2 关卡 = 完成**（遗留：ILA5 GO/ACK 触发未抓，不影响判据）。
- ✅ **速率线速化 L1 帧泵乒乓双 bank（2026-10-09，014cde2）**：根因 = prj9 帧泵握手门控（帧在途到达的帧整帧丢弃，背靠背丢 50%）；派生副本 `prj_loop/rtl_patch/frame_fifo_pump.v`（prj9 原件零改动）帧尾立即翻 bank 接收下一帧。实测 1466B 帧 41.7k→**82.67k fps 零丢帧（≈969 Mbps 线速）**、PRJ9 同款吞吐档 51.45%→99.99%；功能回归全过（DDR 四档 / 导师原话正常+报错 / 死锁专项 / 稳定性 3/3）；WNS +0.019。**当前在库位流 = DBE35734…017F**（`prj_loop/out/aurora_mem_bridge.bit`，与 probes.ltx 配对）。坑账本 #31–#34
- ✅ **W6 可观测性收口 ⇒ 路线 A（W0–W6）收口（2026-10-09，9680b2c）**：①判决计数器总表自动生成（49 信号 / 795 bit）；②4 个 ILA 按域分挂核对（user_clk 404b / eth_rxc 111b / user_clk_b 101b / ui_clk 179b，无跨域采样）；③归档索引 41 条带 SHA256、0 缺失；三脚本 `w6_inventory.py` / `w6_healthcheck.py` / `w6_archive.py`，自检经正负对照验证（5 健康 PASS / 1 死锁 FAIL）。诚实缺口：4 个桥内部计数器挂 ILA3 会打崩 300MHz 域（WNS −0.041→−1.142）故未挂、仅 xsim 可见（清单与验收记录已标注并给替代路径）。**J1–J6+J3′ 全过 ⇒ 路线 B 启动条件满足**


- ✅ **D1 DDR4 校准 + W3 内存插入联调全过（2026-10-06，c27eea3/2465cf4）**：双位流校准全绿；集成位流 ping 20/20 + UDP 12/12 + 10MB 桥零丢零错 + 七级对账闭合；一条命令验证 prj_loop/scripts/udp_verify_ddr.py（四档全 PASS）
- ✅ **过载硬冻结修复落地（2026-10-06 晚，9f29d7c）**：prj_loop/rtl_patch/udp_tx.v 派生副本（忙时锁存 pending，prj9 原件零改动）；R4 TB + 板上重放 pace 13µs 场景双验证，"过载只降速不冻结"达成
- ✅ **W5 随机读（命令通道 + J3/J3′）—— 上板验证通过（2026-10-08 晚，J5）**：导师原话四环节全部取到板卡证据（J3 逆序对 52 / 逐帧对应 16/16 / J3′ 收 16/16 缺 0 多 0 字节差 0 / 负向 A 报缺 1 帧 / 负向 B 观测到「空」），终端一键复现 `prj_loop/scripts/mentor_verify.py`（展示层独立复核，不采信引擎 PASS）。过程中发现并修复**两处真实缺陷**：①**应答帧是以太网 runt**（58B<64B，网卡硬件静默丢弃、板内 ILA 全正常）→ 按 RFC 894 加 6B 填充 + 单元 TB 补最小帧长护栏（旧 RTL 负向对照 FAIL 45 例）；②**RND 模式写槽游标死锁**（接受计数 334 vs 提交计数 278 发散 56；写槽号取自提交计数，拒收时不推进 ⇒ 游标停在满槽上永久卡死、上位机推不出正确槽号）→ 新增独立槽游标 `wr_slot_ptr`（每帧无论提交或被拒都 +1），专项回归 `deadlock_regress.py` PASS。另排除三个假故障：PC 侧 ARP 老化、工具应答配对错位、LUTRAM 宏常量传播。**终版位流 SHA256 `6ACFF515…A62B`（WNS +0.010）**，报告见 `docs/汇报/汇报_导师原话验证报告_prj10内存进环路_2026-10-08.md`。**原时序攻坚（第三轮）**：时序攻坚 8 轮 **−1.121 → +0.001**（WNS_GATE 过 / 全域 0 失败端点；SHA256 `18387F8C…FDF9E`，19:31:22 版，与 probes.ltx 配对）。根因经**对照实验链定案**：主因 = 读命令解码锥（结构性移除实验 −0.494→−0.074，占缺口 4/5），次因 = cmd_channel 负载（≈0.08ns）；**两次「cfg 常量对照」均无效**（LUTRAM 宏对常量传播不透明，坑 #28）。最终修法（全在 axi4_master_bridge.v，两桥共享）：预取拍做范围数学并寄存 `pre_eff` + `len_beats_tab` 预算表 + **keep 保护的 `full_bit_q` 控制镜像**（无 keep 被合并回原树、收益归零）。四仿真全绿、计数逐字一致。上板验证单已恢复「就绪」。详见 `docs/调试记录/阶段三_prj10_W5时序收敛_第三轮根因验证与收敛_2026-10-08.md`。：命令通道 `rtl_patch/cmd_channel.v`（单元 TB PASS / 负向 FAIL 68，集成期拦下两缺陷：应答注入点必须走 RGMII 末级而非泵A、`cmd_hold` 多驱动 DRC 才拦）+ PC 侧 `scripts/j3_random_read.py`（`--mock` 全流程 PASS）已交付。**时序阻断**：`cfg_mode` 接活后**整条读命令解码锥**超预算（`u_rd_cmd` FWFT 组合读出 → 范围比较 → 槽选择 → `full_bit/len_tab` 三张 256:1 查表 → 各 CE/D，4.226ns vs 3.333ns；W2–W4 通过纯属常量折叠，残段只剩 +0.008ns）。**cut-1 已实施**（命令预取寄存 + `R_PRE` 判决拍 + `len_beats_tab` 预算表）→ **WNS -1.121 → -0.494**（失败端点 5011→3464），四仿真全绿；**cut-2 触发 Vivado 2023.1 工程级综合崩溃 ×3（单模块 OOC 却通过）→ 回退留证**（坑账本 #27）。停点 **-0.494ns，不可上板**；构建脚本已带 **WNS/WHS 门限**（不达标不写位流）。候选手段 B→A→D 见 `docs/调试记录/阶段三_prj10_W5时序收敛_第二轮根因重定与修复_2026-10-08.md`。⚠️ 盘上 `.bit`（20:43，WNS<0）与 `probes.ltx`（00:03，cut-1 网表）**互不配对，都勿烧**。
- ✅ **W4 两级内存全环路（J4 全过，2026-10-07 收官）**：缺陷修复 + 位流重建后，AI 远程烧录 + 判读完成 J4 五项——PROGRAM_OK（4 ILA+1 MIG/四域时钟）· T22/T23 双灯（ILA 印证 calib=1/ch_up=1）· ping 20/20 · 四档 PASS · **10MB 质量档 7022/7022 + SHA256 一致** · **双桥对账 mem/mem2 各自 wm=wr_frm=rd_frm=11012、错误计数全 0**；另 pace13 吞吐档：零损坏/不冻结、丢失全在泵A之前（已知单帧在途结构）。**下一步 W5（命令通道 + 随机读 J3/J3′）**。原状态（留痕）：：第七轮构建实际已成功（WNS=+0.035）；上板前审查拦截仲裁器 B/R 响应按 bid/rid[0] 路由 + 两桥常量 ID 恒同 → 必死锁（单元 TB 喂不同 ID 掩盖）。修复 = 按 wgrant/rgrant 授权锁存路由；新增两桥联合仿真 w4_joint_tb（负向对照复现死锁 + 正向 0 错误）+ 双回归逐字一致 + ila_snap.tcl 板上对账。J4 验证单就绪（vault 操作文档 10-07），待用户烧板
> **README 分工变更（2026-10-01）**：仓库 `README.md` 改为**面向组员/新手的外部门面**（工程血缘图 + 通俗一览 + 快速开始）。原 README 承载的**内部信息**（工程索引详表、docs 文档中心指向、标准开发流程、挂起区触发条件）全部迁入本节附录，内部协作只看 AGENTS.md。

- ✅ prj6 网口栈（09-04）· ✅ prj8 数据级桥 M2 判据全过（09-18，git 66ff43d）
- ✅ **prj9 双笼真光链路判据全过（09-21，f7c8be8）**：渡光两次，ping 20/20 + udp 12/12 + 压力 36/36 + 复测无楔死，WNS=+1.006ns
- ✅ **会话 JSON 全量传输质量评测（09-21）**：质量档 100%+SHA 一致 · 单流 19.3 Mbps（PC 侧天花板）· 并行回程 22.9 Mbps（**测量下界，非结构极限**——原「串行上限」归因已由设计报告 v0.5 §3.3.2 修正）；损坏/乱序全程 0
- ✅ **prj9 尾巴 = 全量传输 0.4% 丢失已定案修复（09-21 晚）**：判决位流 build9v（三域 ILA）差分链算术闭合——pack 输出队列 2 深溢出吞 tlast 字→相邻帧合并（7×2+9×2=32，git d9327bd）；队列 2→16（0ee2611）后全量 10MB **100%+SHA 一致**（历史首次）；真实业务传输层 json_reliable.py 交付 100%/0 重传
- ⏭️ 下一步（09-26 导师定案：DDR 先行，路线图 #14）：**D 线 DDR4 队列缓存**——D1 MIG 校准复验（prj4 位流在库）→ D2 队列后端 DDR 化 → D3 判别复测 → D4 缓存/直通双模式 → D5 AXI DMA；BRAM v2 = 回退。并行：双板双链路组网（10G 模块 4 只 + LC 跳线 4 条已齐备，零采购）。后续：过载冻结根因（看门狗就位）→ IBERT 眼图（空闲通道 C/D）
- 🔄 project_4 MIG 已解冻移入主线（#14，D1 校准复验起步）；⏸️ 挂起区：串口桥三级验证 · project_7 内环 · 8b/10b 练手（恢复触发条件见本节附 A）
- ✅🔬 **prj10 W2 内存桥 RTL + xsim 仿真（09-29）**：`prj/project_10/`（三层 RTL + AXI4 RAM 替身 + 六用例 TB），`=== prj10 W2 SIM: PASS (0 errors) ===`；一键复现 `sim\run_sim.bat`（只用 xvlog/xelab/xsim，**未建 Vivado 工程/未上板**，prj4·prj9 零改动）。实测单桥服务 3.11/3.07 µs 每帧（开工草案 §九 漏算 8b↔512b 逐字节转换，已修正；节拍结论不变）。bring-up 修掉 AXI R 通道握手违规 / 尾拍不满 64B 卡死 / 描述符长度清零竞争三条真 BUG（见 vault 执行记录）

### 附 A · 工程索引详表（内部视角，原 README 2026-10-01 迁入）

**✅ 已完成**

| 目录 | 工程 | 达成 | 说明 |
|---|---|---|---|
| `prj/project_1/` | MicroBlaze 最小系统 | ✅ M1（08-11） | BD design_1：MicroBlaze + UART Lite + AXI Interconnect |
| `prj/ibert_ultrascale_gth_0/` | IBERT 眼图实验 | ✅ 08-27 | 10G PRBS 跨口过纤 0E0；眼图截图已归档 |
| `prj/aurora_64b66b_loop_ex/` | Aurora 例程 + UART 桥 | ✅ 08-31 内环验证 | 10G duplex X1Y11；`uart_bridge.v`（串口桥位流在库，验证挂起见下） |
| `prj/project_6/` | 以太网 UDP 网口栈 | ✅ 09-04 上板验证 | 官方 39_eth_udp_loop 整包移植；ping/UDP 回环/Wireshark 四包链 |
| `prj/project_8/` | Aurora-UDP 数据级桥 | ✅ M2（09-18）判据全过 | 以太网栈 + Aurora 64b/66b（X1Y11 内环）；axis_word_pack/unpack 8↔64 + 双向帧泵；`rtl/*_dly.v` = IDELAY 1250ps 修复版；排障脚本与 ILA 数据在 `scripts/` |
| `prj/project_9/` | 真光链路版（双笼 A↔B） | ✅ 真光链路判据全过（09-21，f7c8be8） | prj8 全部验证资产复用；loopback=3'b000 正常模式；判决位流 build9v/w（三域 ILA）；0.4% 丢失已定案修复（pack 队列 2→16，0ee2611），全量 10MB 100%+SHA |

**🔄 正在推进**

| 目录 | 工程 | 状态 |
|---|---|---|
| `prj/project_4/` | MIG/DDR4（D 线第一步） | **D1 校准已过（2026-10-06，双位流 MIG JTAG 报告全绿）**；例程自带比对测试有自身缺陷链，内存正确性以集成位流全链判据为准；D2 队列 DDR 化待启动 |
| `prj/project_10/` | 内存进环路（DDR4 帧队列） | **路线 A（W0–W6）已收口（2026-10-09），全目录冻结为路线 A 资产**（只读；终版位流 DBE35734…017F）：W3 插桥 → W4 两级全环路 J4 → W5 随机读 J5（导师原话四环节）→ 速率线速化 969 Mbps → W6 可观测性；J1–J6+J3′ 全过。**路线 B 在新工程 `prj/project_11/` 做**（fork prj10；MicroBlaze + AXI DMA，Q1/Q3 后继——2026-10-10 用户定案） |
| `prj/project_11/` | 路线 B（软核控制面 + AXI DMA 数据面） | 🔄 **进行中（2026-10-10 起）**：B0 脚手架 → B1 软核控制面集成（`[B1-SELFTEST] PASS`）→ B2 J3 软核验证（`[B2-SOFT-VERIFY] PASS`）→ B3-0 延迟可观测（Lw 中位 97 拍 / Lr 中位 23 拍）→ B3-1a DMA 集成（`DMA_SMOKE PASS`）→ B3-1b 双读引擎 + v3 结构重构。**2026-10-19：R1/R2 已收口（round3d `F6012BA0` WNS+0.002/WHS+0.004 + S0–S11 13/13 PASS）；剩 R3 速率量化 + R4 文档收口（≈1 天，重审版见剩余清单 §七/记录 §二十一）；D1/K2 结项、D2 可选、坑#39 降级** |

**⏸️ 挂起（恢复触发条件见 vault `操作文档/挂起/README`）**：串口桥 M-D 三级验证（解 dbg 探针时钟域 undefined + AE33 输入方向）· `prj/project_7/` SFP 前端内环（09-22 定案后不再复活，PCS/PMA 配置留档）· 8b/10b 练手（IBERT 已覆盖）· prj9 传输效率深挖 B 组（B1 板卡自发流/B2 C 发包器/B3 帧泵 B 硬件提速；E1–E5 已随实操单 v2 移回主线）。

**🗄️ 归档/工具**：`prj/project_2/` 8b/10b 练手遗骸 · `prj/project_3/` Aurora IP 定版 xci · `prj/0DMA_uart2ddr/`（MicroBlaze+MIG+DMA+UART 参考 BD，Vivado **2019.2**，**未验证勿当资产**，D2/D5 骨架）· `scripts/` 顶层 Tcl 骨架 + `ci_check.py` · `KU_IO.xdc` + `docs/KU引脚表.xlsx`（GBK）· `docs/参考_cross_FMC_4SFP_GTH引脚表_2026-08-27.md` · **`vivado-mcp/`**（上游 [vivado-mcp](https://github.com/mapleleavessssssss-wq/vivado-mcp) v0.3.26 **零改动副本**，Apache-2.0；权利边界与 NOTICE 见根 `THIRD_PARTY.md`；运行时实装在 `D:\vivado-mcp`，见坑账本 #21，仓库内副本仅溯源）· **CI**：`.github/workflows/ci.yml`（push 触发 `scripts/ci_check.py` 仓库体检：文档规范/链接/Tcl 语法；本地收尾先跑 `"C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe" scripts/ci_check.py`，**Git Bash 的 `python` 是别名坏壳**，坑账本 #45）· 根 `LICENSE`（MIT，**仅覆盖作者原创部分**）。

### 附 B · docs/ 文档中心指向（原 README 迁入）

- `docs/` = vault 文档的**脱敏快照**（用户名→***，人名→前辈；`[[双链]]` 按仓库惯例保留）；命名规范 `[阶段]_prj标识_概要_YYYY-MM-DD`，索引见 `docs/README.md`。
- 关键文档：`导览_cross_已完成工作说明_2026-10-01.md`（8 件已完成工作展开）· `规划_cross_长期路线图_2026-09-04.md`（v4.5，#15 prj10 定案）· `追踪_cross_短期待办_2026-10-10.md` · `规划_cross_AI-Infra系统设计报告_2026-10-06.md`（v0.6，服务器底座定案：Windows + WSL2 / 4090D 24GB）· `操作文档/`（含挂起区）· `调试记录/`（prj10 W2/W3 执行记录、prj9 R4 仿真复现等）· `结论_cross_prj9-prj10_进度体检报告_2026-09-29.md`。

### 附 C · 标准开发流程（原 README 迁入）

1. Vivado：设计 → 综合/实现 → Generate Bitstream → Export Hardware（含 bitstream）→ .xsa
2. Hardware Manager：Program Device（成功标志 `End of startup status: HIGH`）
3. Vitis：更新 .xsa → Run Configuration **取消 Program FPGA**（保留 Reset entire system）→ Run → 串口 9600
4. 批处理构建：`vivado -mode batch -source <script>.tcl`（幂等脚本见各工程 `scripts\`；⚠️ 纯 ASCII 工作目录）

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

另有一条**本地专用提示**（不计入失败、不卡 CI）：检测到本机 vault（`C:\Users\15266\Desktop\毕设\`）时，比对 docs/ 快照与 vault 对应文件的字节一致性，不一致则打印 `[提示]` 清单。**为什么它只提示不卡 CI（2026-10-17 实测定性）**：`docs/` 是 vault 的**脱敏快照**，因此「字节不一致」在很多情况下**是设计结果、不是缺陷**——当日抽查 9 个不一致文件中的 `阶段二之十_prj9_json_storm改造…` 第 601 行：vault 为 `C:\Users\15266\…`，docs 为 `C:\Users\***\…`，差异全部来自脱敏替换。另有一批 vault 侧文件已移入 `归档/` 或改目录（docs 保留历史快照）。
⇒ **纪律：绝不「为了对齐」把 vault 原文覆盖进 docs/**（会把用户名等敏感信息写进 git 历史）；确需同步时先判断差异类型（脱敏 / 内容更新），内容更新以「更晚、有实测证据」的版本为准，且**同步后必须重新脱敏**。

### 本地怎么跑

```
py scripts\ci_check.py        # 或 §三 记录的全路径解释器；退出码 0 = PASS
```

- ⚠️ **Git Bash 里的 `python` 是 WindowsApps 别名坏壳**（静默退出码 49）——判成败只信脚本自身退出码，勿经管道（坑 #45）。
- 改完任何文档/脚本后，**提交前必跑一次**；位流/日志等 .gitignore 项不参与检查，不要试图入库。

### 远程 workflow 何时触发

- **push 到 master** / **PR 目标 master** / 手动 `workflow_dispatch` 三种触发；运行于 ubuntu-latest + Python 3.12 + tclsh，**job 超时 15 分钟**。
- 全程只用 **Python 标准库**，不安装任何第三方包；tclsh 仅供第 5 项使用，安装失败该项自动跳过（本地无 tclsh 同理，输出 `[跳过]`）。

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
