# agent.md — 会话入口（本目录 = 毕设文档目录）

> 给从本目录启动的 AI 开发会话作第一页：目录定位、工程位置、规矩速览、当前状态。
> 工程规范权威版本 = `D:\FPGA\AGENTS.md`；本文件与它冲突时，以 AGENTS.md 为准并回改本文件。
> 状态提示：**路线 A（prj10）冻结、路线 B（prj11）已于 2026-10-19 全量收口**；最新发布见「30 秒导航」的 Release 行，当前入口见下方「30 秒导航」。

## 目录定位

| 路径 | 角色 |
|---|---|
| `C:\Users\***\Desktop\毕设\`（本目录） | 毕设文档目录：任务清单、路线图、操作文档、汇报、归档 |
| `D:\FPGA\` | FPGA 工程目录（git 管理，远端 chemmy-11/EIF）：project_1~9、官方例程留档、docs 快照。开发主战场 |
| `D:\BaiduNetdiskDownload\1_Verilog\KU060例程\` | 正点原子 KU060 官方例程源码库（56 章，GBK 编码）。事实源最高层 |

多会话协同由用户自行编排（按需加载技能），无固定分工契约。

## ★ 30 秒导航（2026-10-17 新增）

| 我要找 | 去哪 |
|---|---|
| **工程规范全文**（权威） | `D:\FPGA\AGENTS.md`；文件头有「目录（30 秒导航）」，覆盖 §一～§十二 |
| **结论依据等级制度**（L0–L4 + 6 条硬规则） | AGENTS.md **§6a**；速览表见本文件下文「结论依据等级制度」节 |
| **坑账本**（#1–#68（截至 2026-10-19），踩过的坑与修法） | `PITFALLS.md`（全文，仓库根）+ AGENTS.md **§九**（索引） |
| **外部 AI 技能 / 官方文档检索**（2026-10-18 新增） | 本文件「★ 外部 AI 技能与官方文档检索」节；细节 `参考_cross_AI工具链_AMD官方skill与知识库_2026-10-18`；AGENTS.md **§6b** |
| **当前入口（新对话从这里开始）** | `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十九–§二十二（路线 B 收口记录 + 速率 + 重审）；复现 `复现/复现_prj11_指南_2026-10-19.md`；剩余清单 `操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md` §七/§八 |
| **最新发布（Release）** | prj11 路线 B 收口（2026-10-19）— <https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19> |
| **已完成工作说明（补充材料）** | `汇报/导览_cross_已完成工作说明_2026-10-01.md`（vault）；GitHub 镜像 `docs/导览_cross_已完成工作说明_2026-10-01.md`（路线 A/B 均已收口） |
| **当前工程状态**（一屏速览） | AGENTS.md **§十** |
| **CI 与远程仓库规范**（6 项检查 / 本地怎么跑 / 远程触发 / 失败定位 / 提交前自检清单） | AGENTS.md **§十二**（2026-10-17 新增） |
| **文档索引与命名规范** | `D:\FPGA\docs\README.md`（全量索引，CI 第 6 项强制与磁盘一致） |
| **仓库入口：关键文档 / 提交文档规则** | `D:\FPGA\README.md` 的「关键文档」「提交文档」两节 |

**本地跑 CI（统一口径）**：`py D:\FPGA\scripts\ci_check.py`，**只认退出码**（0 = PASS）。
注意坑 #45：Git Bash 里的 `python` 是 WindowsApps 坏壳（静默退 49、无输出），必须用 `py` 或全路径解释器；也不要经管道判成败（拿到的是下游命令的退出码）。

## ★ 镜像口径（2026-10-17 实测定性，重要）

- `D:\FPGA\docs\` = 本目录（vault）的**脱敏快照**（用户名→`***`，人名→`前辈`），不是逐字节镜像。
- **「字节不一致」多数是脱敏设计的结果，不是缺陷**：当日抽查的差异样本中，vault `C:\Users\***\…` 对应 docs `C:\Users\***\…`，差异全部来自脱敏替换。
- ⇒ **纪律：绝不「为了对齐」把 vault 原文覆盖进 `docs/`**（会把敏感信息写进 git 历史）。确需同步时先判定差异类型（脱敏 / 内容更新），内容更新以「更晚、有实测证据」的版本为准，**同步后必须重新脱敏**。
- **vault 增删文档后，镜像入 `docs/` 时必须同步 `docs/README.md` 全量索引**（口径 = docs/ 下除任意 `README.md` 外的全部 .md），否则远程 CI 第 6 项会红。
- CI 里另有一条**本机专用提示**（不卡 CI）：存在 vault 时比对镜像字节一致性，打印差异清单——**它是提示，不是待办清单**，逐条判定后才动。

## 文档地图（本目录）

| 条目 | 内容 |
|---|---|
| `追踪_cross_短期待办_2026-10-10.md` | 任务清单与里程碑（当前任务的水位线）|
| `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` | **路线 B 收口记录（新对话第一份读）**：全过程/判据/速率/重审，§十九–§二十二 为收口结论 |
| `参考_cross_AI工具链_AMD官方skill与知识库_2026-10-18.md` | 官方 AI 技能与文档检索：接入、调用、2023.1 待实测（2026-10-18）|
| `规划_cross_长期路线图_2026-09-04.md` | 长期路线与决策记录 |
| `操作文档/` | **操作开发类**（照着做）：实操单 / 实施单 / 开工开发文档 / 前置清单 / 验证单 / 作战卡（命名 `[阶段]_prj标识_概要_日期`）；`操作文档/挂起/` 为挂起课题收纳区（状态轴）|
| `调试记录/` | **调试记录类**（看结果）：调试记录 / 执行记录 / 测试报告 / 独立复核 / 复现记录。**两类分开存放，判据见 README「存放规则」** |
| `汇报/` | 组会汇报（md/pptx/pdf）|
| `8.3/` | 导师会议纪要、任务分工、论文拆解、基线工程资料 |
| `毕设方向与论文大纲/` | 课题定位与论文大纲 |
| `笔记和开发指南/` | 板卡手册研读笔记 |
| `截图归档/` | 上板截图 |
| `Agent 协作/` | **历史归档**（旧协作契约，2026-09-20 废弃，仅供追溯）|

## 红线速览（全量见 AGENTS.md）

1. 每步标注「为什么」——工程优先，写清依据（契约/实证/官方例程出处），不只给结论。
2. 物理层经允许可代劳：工具链 = 工程仓库 `vivado-mcp/`（运行时 `D:\vivado-mcp`）+ xsct，经用户允许后代劳烧录/ILA/串口/JTAG 上板验证；插拔光纤/电源、开关机仍归用户。协作 agent 推荐同一工具链。
3. **两轴采信**（AGENTS.md §二/§6b）：**知识/工具语义轴** = AMD 官方文档/知识库**最高权威**（Tcl/属性/IP 参数/协议/报错，引用带 `docs.amd.com` URL）；**工程事实/判据轴** = 本项目实测优先（官方文档与本板实测冲突时以实测为准，记录并列两栏）。引用官方文档必须给「URL + 本工程落点（2023.1/器件/IP 实例/验证动作）」两件套。
4. 官方文件不改动原件：修复用「同名模块顶替」或「派生新文件」。
5. Vivado 相关路径全 ASCII（中文路径 GBK 实坑）。
6. 改动可追溯：工程改动走 git；文档遵守命名规范。

## 硬件事实速查（全表见 AGENTS.md 第三节）

- 板卡：正点原子 KU060，Kintex UltraScale `xcku060-ffva1156-2-i`；时钟 100MHz 差分 AK17/AK16；复位 AC34 低有效。
- 网口：GE1 RGMII（YT8531）；PC 192.168.1.102/24 ↔ 板 192.168.1.10；RX 采样须 `rgmii_rx_fix2.v`（IDELAY 1250ps）。
- 光口四笼（GT Quad X1Y2）：A=Y11=X1Y11 · B=Y9=X1Y9 · C=Y10=X1Y10 · D=Y8=X1Y8；Aurora 线速率 10G → 光模块须 10G SFP+。
- LED：T23 = 链路指示（channel_up 门控，判据硬前提）；T22 = 观测。

## 验证判据

```powershell
# 位流断电即失 → 一键重烧+判据：
powershell -File D:\FPGA\prj\project_9\scripts\board_test_*.ps1
ping 192.168.1.10 -n 20                          # 0% 丢包、全 <1ms
$env:PYTHONUTF8 = 1                              # 必须（GBK 控制台崩溃）
cd D:\FPGA\prj\project_9; python scripts\udp_verify.py  # 回显一致 12/12
```

佐证：Wireshark 过滤 `udp.port==1234`，请求/回显成对且 payload 相同。三层证明力：T23=链路、ping=通路、udp_verify=数据完整性。

**prj11 路线 B 判据（已收口；prj9 段为历史基线）**：

```powershell
# 板验 S0–S11（需板上电 + 已烧归档绝对路径 bit+ELF；-Run 才真执行）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_board.ps1 -Run `
  -Bit <归档 bit> -Elf <归档 ELF> -Xsa <归档 xsa> -IlaLtx <归档 ltx> `
  -ExpectBitHash8 <前8位> -ExpectElfHash8 <前8位>
# 桥级 ILA 抓取（round3d 验收 ltx；详见 复现_prj11_指南 §9）
$env:R2_LTX='<round3d 归档 ltx>'; $env:R2_OUT_DIR='D:\FPGA\prj\project_11\out\evidence_2026-10-19'
$env:R2_TAG='r3d'
vivado -mode batch -source D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_cap.tcl
```

口径：R2 位流 `'d'` 后必须 ping 回包 + NIC `ReceivedBytes` 增长；双桥对账 = `mem/mem2` 各自 `wm=wr_frm=rd_frm`、`ost=0`、`fault=0`；规则号 1 = 槽号接收即推进（被拒帧同样消耗）。

## 环境事实

- Vivado 2023.1：`D:\Xilinx\Vivado\2023.1\bin\vivado.bat`；批处理 `-mode batch -source <tcl>`，日志落文件再检索。
- Python：`C:\Users\***\AppData\Local\Python\pythoncore-3.14-64\python.exe`。
- JTAG：Digilent USB-JTAG（210512180081）；**板卡串口 = COM5（USB-SERIAL CH340，9600 8N1；115200 无响应属正常，非故障）**。
- **板卡状态（2026-10-19 收尾时的最后在役配置）**：round3d 位流 `F6012BA0` + 固件 `BA3C0220`（`'d'` 后 DMA 模式）；是否上电以现场为准，重烧与体检见 `复现/复现_prj11_指南_2026-10-19.md` §2–§3。
- **prj11 主线工具入口**：判据 `D:\FPGA\prj\project_11\out\r2_board.ps1`（S0–S11；工具 README `R2_tools_README.md`）；PC 侧 TX 判别 `out\r2_tx_probe.ps1`；ILA 抓取 `out\r2_ilacap.tcl` 与 `out\evidence_2026-10-18\tools\r2_ila5_capture.tcl`。
- 各工程脚本（create/build/program/board_test，幂等）在 `D:\FPGA\prj\project_N\scripts\`。
- **配套工具 `vivado-mcp`（已随仓库入库）**：MCP 服务，**32 个工具**——会话/Tcl/工程/流程/报告/诊断/CDC/位流探针/IP/波形十类；其中 `parse_xpr`·`parse_bit_header`·`parse_ltx`·`xdc_lint` 为**离线工具**（不启 Vivado）。**上游 = [mapleleavessssssss-wq/vivado-mcp](https://github.com/mapleleavessssssss-wq/vivado-mcp) v0.3.26（Apache-2.0，LICENSE 已随源码入库）**——本仓库副本**零代码改动**、仅目录重组（上游 `src/vivado_mcp/` + 顶层 `scripts/` `skills/` → 平铺入包内；逐字节比对 52 同 / 0 改）。上游基准 **Vivado 2019**，本项目 **2023.1**：离线工具与 Vivado 会话实测可用；**`compare_xci` 不可用**（上游按 XML 版 xci 设计，本项目 2023.1 的 xci 全为 JSON 版）。 仓库内为**可移植副本**（`D:\FPGA\vivado-mcp\`，零本机配置），安装与清单见 `vivado-mcp/README.md`。⚠️ **与下条「工具纪律」里的本机 CLI 壳是两回事**：那层壳是开发者本地设施、不入库。两条硬约束：安装路径必须**纯 ASCII**（中文路径经 Vivado Tcl 的 ANSI 解码会乱码，会话必失败）；Vivado 会话与综合/实现/仿真**全局串行**。
- **AI 技能与官方文档检索（2026-10-18 新增）**：项目级技能 `毕设\.dsh\skills\`（7 个，**仅本工作区可见**；全局 `~/.agents/skills` 不放 Vivado 技能）；官方文档检索 hosted `amd-doc-search`（MCP 已配置在 DSH web profile，**重启 `dsh web` 后生效**；未重启时用项目桥 `py 毕设\.dsh\skills\amd-doc-search\doc_search.py "<query>"`）。调用与引用纪律见下节。

## ★ 外部 AI 技能与官方文档检索（2026-10-18 新增）

- **技能（项目级，仅本工作区）**：`毕设\.dsh\skills\` 下 7 个——`vivado-rtl-elaboration-analysis`（综合日志分析 + **560 个** `[Synth 8-XXX]` 修复卡）· `vivado-rtl-lint`（20 个 lint 规则修复模板）· `vivado-revision-control`（工程导出/交接/重建）· `vivado-simulate-rtl`（XSim 排错/覆盖率/波形）· `hw-ila-debug` · `hw-vio-debug` · `amd-doc-search`（官方文档检索桥）。**全局技能根 `~/.agents/skills` 不放 Vivado 技能**（2026-10-18 定案，避免污染其他 Agent 上下文）。
- **官方文档检索**：AMD hosted `amd-doc-search`（`https://ross.amd.com/mcp/doc-search`，免 key，英文；`version` 含 2023.1、`family` 含 Kintex UltraScale+）。原生 MCP 已配置在 DSH web profile（**重启 `dsh web` 后**工具名 `mcp__amd_doc_search__vivado_doc_search`）；未重启时用项目桥：`py 毕设\.dsh\skills\amd-doc-search\doc_search.py "<query>" --limit 5`。
- **触发纪律**：AMD/Xilinx 官方依据类问题**先检索再回答**，结论带 `docs.amd.com` / `adaptivesupport.amd.com` URL；检索不到就写「未检索到」，**禁止臆造**命令/参数/约束。官方文档在事实源排序中 = **官方文档层**（高于 AI 生成文档、低于官方例程/已验证 prj，只作 L3/L4 旁证）。
- **过滤要核对**：`family`/`version` 是提示性过滤，返回里仍可能混 `All` 条目，引用前逐条核对（坑 #64）。
- **执行层不变**：技能只是知识与流程；官方 skill 里的 `vivadoExecute`/`vivado_start`/`vivado_doc_search` 按技能顶部「本机适配注记」映射到本工程 `run_tcl`/`start_session`/`mcp_ctl.py` CLI 桥。只读日志分析**不启动 Vivado、不占全局串行锁**；原始日志先复制到 C: 侧副本再解析。
- **细节**：[[参考_cross_AI工具链_AMD官方skill与知识库_2026-10-18]]；坑账本 #62–#64；2023.1 适配待实测项见该文档 §6。

## 当前状态（2026-10-20 更新；主线 = 路线 B 已收口）

- ✅ **路线 B（prj11）已全量收口（2026-10-19）**：round3d 位流 `F6012BA0`（WNS +0.002）+ 固件 `BA3C0220`；S0–S11 **13/13 PASS**；四档 / 10MB 100%+SHA / J3 四链 / 双桥对账全过；R3 速率：1466B 可持续 2000fps 零丢、上限≈2560fps；R4 文档收口完成（复现指南 / 探针清单 / 归档索引 0 缺失）。
- 📦 **发布页**：<https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19>（tag `prj11-routeB-closed-2026-10-19`）；**已完工作说明**：vault `汇报/导览_cross_已完成工作说明_2026-10-01.md`（GitHub 镜像 `docs/导览_cross_已完成工作说明_2026-10-01.md`）。
- ✅ **路线 A（prj10）目录冻结只读**（终版 `DBE35734…017F`）。
- **入口**：`调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十九–§二十二（收口/速率/重审）；`复现/复现_prj11_指南_2026-10-19.md`（一键复现）；`操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md` §七/§八（重审与收尾）。
- **下一步（非强制）**：双板双链路按 2026-09-30 Q4 暂缓；SG 描述符环 / 调度与 FL 负载验证属新范围。


### 历史状态（≤2026-10-19，仅供追溯）

路线 A（W0–W6）与路线 B（B0–B5 / R1–R4）的完整过程、位流哈希、缺陷链与证据均在：
`调试记录/`（尤其 `阶段三_prj10_*`、`阶段三_prj11_*` 系列）与 `D:\FPGA\prj\project_11\out\archive\ARCHIVE_INDEX_prj11.md`。
本文件自 2026-10-20 起不再维护逐日历史（精简，约 -35KB）。
