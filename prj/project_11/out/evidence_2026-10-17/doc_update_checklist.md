# R1 收口 · 文档同步清单（改哪里 / 改成什么 / 怎么验证）

- **用途**：2026-10-17 R1 读侧收口的**文档回填清单**。逐项给出「文件 + 位置（当前行号）+ 改什么 + 可直接粘贴的草稿 + 验收方式」。
- **生成**：2026-10-17 21:04，文档与证据管理员（Agent Team 成员 `docs-evidence`）。
- **纪律**：本清单只**列出**改动，**不执行**（本人不写 vault/docs/仓库、不 commit）。所有 `{{PENDING}}` 项必须等新位流 S0–S8 结果出来后再填，**禁止先填后验**。
- **依据**：`out\evidence_2026-10-17\R1_evidence_index.md`（证据/hash）、`out\evidence_2026-10-17\record_section_draft.md`（记录正文草稿）、`out\evidence_2026-10-17\rtl_fix_review_205656.md`（修复独立复核）。
- **行号基准**：2026-10-17 20:59 的磁盘现状；插入/改动后以**锚点文字**为准（行号会漂）。

---

## 0. 先看：本次收口"改什么、不改什么"

| 类别 | 结论 |
|---|---|
| **仓库代码** | 工作树 **4 个 M 文件**（`rtl/axi4_master_bridge.v`、`sim/mem_bridge_tb.sv`、`sim/w4_joint_tb.sv`、**`scripts/j3_soft_verify.py`**）已改、**未提交** → 收口时 Lead 提交（commit hash 记入记录 §8）。前 3 个 = RTL 修复；第 4 个 = J3 判据脚本缺陷修复（独立 [L4]，+15/−4） |
| **未跟踪的仓库侧交付物** | `out\S0S8_DESIGN.md`（判据设计说明）、`out\retire_s0_s8.ps1`、`out\j3_fourchains.ps1`、`out\jb31b_*` 取证工具 —— 是否入库由 Lead 定（建议与修复同批提交；`.md/.py/.ps1/.tcl` 不入 `.gitignore`） |
| **vault 调试记录** | 追加 `§三之二十`（草稿见 `record_section_draft.md`）+ 回填文末「§三、当前状态（末版快照）」 |
| **vault 操作文档** | 工作清单 §R1 行、§二之七（口径更新）+ 新增 §二之八（本次根因/修复/待验） |
| **vault 入口** | `毕设\agent.md` 当前状态节 + 文末「10-17 日场结论」加晚场小结 + 运维口径更正 |
| **仓库规范** | `D:\FPGA\AGENTS.md` §十（路线 B 状态行 + 未决项 ④⑥） |
| **docs/ 镜像** | 上述三份 vault 文档的脱敏同步 + （仅当新增文件时）`docs/README.md` 索引；**禁止用 vault 原文覆盖** |
| **不需要改** | `docs/README.md` 索引表（本次不新增 `.md` 文件；只改既有文件内容）——但必须跑 CI 第 6 项确认不红 |
| **不入库/仅本机** | `.gitignore` 忽略 `*.log` / `*.bit` / `*.ltx` / `*.xsa` / `*.rpt` / `*.jou` ⇒ 本目录的原始 `.log`、归档位流/探针**不会进 git**，只有 `.md`/`.csv` 可提交；收口说明里要写清留存边界（沿 §三之十九之补三 既有口径） |

---

## 1. `D:\FPGA\AGENTS.md` §十（当前工程状态 / 未决项）

**位置**：`## 十、当前工程状态（一屏速览；内部详表见本节附录）`（当前 L212）
- **条目 A**：路线 B 状态长句（当前 **L214**，以 `- 🔄 **路线 B / prj/project_11/ 进行中…**` 开头）
- **条目 B**：未决项列表（当前 **L215**，以 `- ⏭️ **路线 B 未决三项（下一步）**` 开头）

### 1.1 条目 A（L214）——在该长句**末尾**追加（不删原文）

> 草稿（可直接粘贴，行末接在原文最后一句后）：
>
> `→ **10-17 晚 R1 读侧收口（根因定案，修复待复验）**：退役位流 `3aa600aa`+ELF `2961b585`、`'d'`→ping×4 的有效判据（`clean_engine1_ping_204321.log`）显示桥① 读出正常（`WM_WR/WM_RD` 各 +4、`emit`={len=86,slot 递增,byte0=0x55}）但 ping 0/4、网卡 delta=0；桥级 ILA（`ilacap_*`，20:53 有效轮）进一步给出：**桥① `dbg_mem_rd_frm` 19→23、ost=0；桥②（u_mem2）`dbg_mem2_wr_frm` 19→23 而 `dbg_mem2_rd_frm` 0→0、`ost` 19→23** ⇒ 泵B 无输入、出向帧不上线。**根因 `[L3]` = `8afa168` 在共享模块 `rtl/axi4_master_bridge.v` 内无条件删除硬件读 FSM，误伤 `HAS_DMA=0` 的桥②（无 DMA shim）**；修复（工作树未提交）= 读 FSM 按 `HAS_DMA` 参数化（`HAS_DMA=1` 仍 DMA-only；`HAS_DMA=0` 恢复 `R_AR/R_R/R_UNPACK/R_FIN`）+ `shim_frame_done` tie-0 + W2/W4 TB 显式 `.HAS_DMA(0)`；离线 `bridge_dma_tb`/`mem_bridge_tb`（W2）/`w4_joint_tb`（W4，含负向）全绿，独立复核 `rtl_fix_review_205656.md` 通过。**新位流 + S0–S8 + 四判据 `{{PENDING}}`**（最高优先 = 桥② `dbg_mem2_rd_frm` 随 ping 前进）。详见记录 §三之二十 与 `out/evidence_2026-10-17/R1_evidence_index.md`。`

**验收**：`Select-String -Path D:\FPGA\AGENTS.md -Pattern '三之二十'` 有命中；长句仍保持单 bullet 格式。

> **补充（21:2x 新增事实，必须一起写进长句或紧随其后）**：
> - **J3 判据脚本缺陷 [L4]**：绿位流 `--dma` 下 J3 四链 FAIL 的根因是 `scripts/j3_soft_verify.py` 在 SEQ 窗无条件发预热帧（DMA 模式下占 1 槽 ⇒ `wr+255` → 级联 FAIL），**与 RTL/位流无关**；修复 `run_round(..., warm_probe=(not args.dma))`，复验 `green_dma_j3_run5_warmfix.log` **PASS**（`[M] wr+256 rd+256` / `[A] wr+256 rd+255` 恰帧#100 / `[B] wr+256 rd+256`）。
> - **NIC 判据口径 [L3]**：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ `ReceivedUnicast` 恒 0；S4/S5/S6 主判据必须用 **`ReceivedBytes`**（单帧 ≥74、4 帧 ≥296）。绿侧实测 ping 4/4：`Unicast=0/Bytes=+296`。
> - 建议在 L214 长句末尾补一句：`另：J3 判据脚本 DMA 预热帧缺陷已修复复验 [L4]（+15/−4，见记录 §三之二十 §4.2）；NIC 判据改用 ReceivedBytes（静态 ARP 环境 Unicast 恒 0）。`

### 1.2 条目 B（L215）——按项替换

| 原项 | 改成 |
|---|---|
| ④ **退役位流数据面未通**（控制面已可用）…… | `④ **退役位流数据面：根因已定 `[L3]`（10-17 晚）、修复待上板复验 `{{PENDING}}`**——读侧断点**不在**"shim 字节流→发射口→线上"的桥① 段（该段字节级已证正确，`rdcap2_retired.csv` 1526B/前导/1526 拍无气泡），而在**桥②（u_mem2，HAS_DMA=0）读 FSM 被 8afa168 误删**（ILA：桥② 写帧 +4、读帧恒 0、ost 只增不减）。修复见记录 §三之二十；四判据复验未做。` |
| ⑥ **归因未定（已降级，见记录 §三之十九之补二 §2）**…… | `⑥ **归因已定（10-17 晚，`[L3]`）**：不是"归档位流不对应 RTL"、不是网表差异，而是共享模块退役误伤桥② 读引擎（详见记录 §三之二十；原 H2/H4 候选降为历史）。"桥① 发射口之后"的收窄仍成立，但其中"桥② 读路径"已由 ILA 直接观测锁定。` |
| 其余 ①~③⑤ 项 | 保持原文，**不要删**（历史留痕）。 |

**验收**：④/⑥ 两行含 `L3`、`三之二十`、`PENDING` 字样；未改动其它行。

### 1.3 （可选，建议做）AGENTS.md §九 坑账本新增 **#55**

位置：§九 坑账本表末（当前最后一条为 #54，L211）。草稿：

> `| 55 | **共享模块的"退役/删除"必须按实例作用域做；旧 S2–S6 序列在判据前改 engine/mode ⇒ 对照无效** | 2026-10-17 实证（prj11 R1）：提交 8afa168 在 `axi4_master_bridge.v`（u_mem/u_mem2 **两实例共用**）里无条件删读 FSM，误伤 `HAS_DMA=0` 的桥② ⇒ 泵B 无输入、出向帧不上线（ILA 直接观测：桥② 写帧 +4/读帧恒 0/ost 只增不减）；**纪律 = 删逻辑前枚举全部实例与参数化差异，结构差异用参数（HAS_DMA）守卫、不用运行态位（dma_engine）**。附：`retire_s2_s6.ps1` 的 S4 跑 M 轮（轮末 `R_ENGINE=0`、`R_MODE` 留 RND）⇒ S5 ping 是无效实验，绿/退役都 0/N；**纪律 = 任何"M/A/B 轮后直接 ping"的对照作废，有效判据必须 `'d'`（确认 DMA）→ ping 中途不跑轮**。详见记录 §三之二十 §9。 |`

**验收**：表列数一致（6 列）、编号 #55 唯一、不与其他坑重复。

### 1.4 （可选，建议做）AGENTS.md §九 坑账本新增 **#56**

位置：同表末（#55 之后）。草稿：

> `| 56 | **判据工具自身也是被测件：预热帧在 DMA 模式占槽 ⇒ `wr+255` 级联假 FAIL；失败不得重试** | 2026-10-17 实证（prj11 R1）：绿位流 `--dma` 下 J3 四链连续三次 `[M] wr+255`（写少 1 帧）→ 读阶段不启动 → 槽满级联 FAIL；根因 = `scripts/j3_soft_verify.py` 的 `run_round()` 在 SEQOK 后无条件发 1 个预热帧，DMA 模式下该帧读请求永泊 `R_DRET` 占 1 槽（软核正停在 `round_command` 等 GO，驻留服务不在跑），写阶段第 256 帧槽满被拒；桥模式由硬件读引擎自动退休故 PASS。**修法 = `warm_probe=(not args.dma)`（--dma 跳过预热帧），复验 PASS（`green_dma_j3_run5_warmfix.log`）**。附纪律：J3 必须在**新烧录后**跑；跑前 `'S'`+只读检查 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍（清槽）；**`wr+255`/收帧停摆不得重试**（级联假 FAIL + 可能半楔死需重烧）；轮末 `R_ENGINE=0`/`R_MODE=RND` ⇒ 后续 ping 判据重发 `'d'`/`'S'`。另：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ **NIC 主判据用 `ReceivedBytes`**（单帧 74B / 4 帧 296B），`ReceivedUnicast` 恒 0 不可用。详见记录 §三之二十 §4.2/§9-⑧⑨⑩。 |`

**验收**：表列数一致（6 列）、编号 #56 唯一（若 Lead 已有 #55 之外的编号，顺延即可）。

---

## 2. `C:\Users\***\Desktop\毕设\操作文档\阶段三_prj11_路线B剩余工作清单_2026-10-16.md`

### 2.1 §一 总览 · **R1 行**（当前 L21）

把 R1 行"判据"列的末尾（`⑤ 正从当前树重建位流并在新位流上按 §二之七 的 S0–S8 收口`）改成：

> `⑤ 正从当前树重建位流并在新位流上按 §二之七 的 S0–S8 收口；⑥ **10-17 晚根因定案 `[L3]`**：8afa168 在共享模块 `axi4_master_bridge.v` 无条件删读 FSM，误伤 `HAS_DMA=0` 桥②（无 DMA shim）⇒ 泵B 无输入（ILA：桥② 写帧 19→23、读帧恒 0、ost 19→23；桥① 读帧 19→23、ost=0）；⑦ 修复 = 读 FSM 按 `HAS_DMA` 参数化（工作树未提交）+ W2/W4 TB 显式 `HAS_DMA(0)`，离线回归全绿；⑧ **J3 判据脚本缺陷已定案并修复 `[L4]`**（`scripts/j3_soft_verify.py`：DMA 模式预热帧占槽 ⇒ `wr+255` 级联；修 `warm_probe=(not args.dma)`，复验 `green_dma_j3_run5_warmfix.log` PASS，与 RTL/位流无关）；⑨ **NIC 判据改 `ReceivedBytes`**（静态 ARP ⇒ 板自发帧广播 dst ⇒ `ReceivedUnicast` 恒 0；单帧 ≥74 / 4 帧 ≥296）；**新位流 + S0–S8 + 四判据 `{{PENDING}}`**（详见记录 §三之二十）`

### 2.2 §二之七（当前 L87–L103）——**追加"口径更正"块**

在 §二之七 表格**之后**、"过程纪律"（当前 L103）**之前**插入：

> ```markdown
> **⚠️ 10-17 晚口径更正（先读，否则 S5/S8 会假红/白跑）**
> 1. **`'d'` 是翻转不是置位**（`sw/src_j3/main.c:436-446`）：必须「发 `'d'` → 解析回显 `DMAMODE now=DMA` → `'U'` 断言 `req` bit24=1」。盲发一次可能把引擎翻回 bridge——10-17 第一轮 ILA 就是这么作废的（`r1cap_uart_pre/post.log` `mode=0`）。
> 2. **S4 不要用 `manual_round.py COM5 1` 之后直接 S5 ping**：M 轮末固件会把 `R_ENGINE` 写回 0（`main.c:375-379`）且 `R_MODE` 停在 RND（`main.c:358`）⇒ 读侧零启动（`s2_s6_204148.log`：`WM_WR 2→7`、`WM_RD 2→2`）。**ping 前不跑任何 M/A/B**；若必须跑，跑完补 `'S'`（回 SEQ）+ 重新确认 `'d'` 状态。**工具口径已更新**：Lead 的 `out/retire_s0_s8.ps1` 把 S4 改为 **`ping -n 1` 单帧判据**（NIC delta + `'U'` 前后差分），本清单表格的 S4 也按此写。
> 3. **S7 判据更新**：本次修复的判别性观测是桥② 的 ILA 计数（现有 u_ila_3 已含 `dbg_mem2_wm/rd_frm/ost`，**不用改 RTL 加探针**）：`dbg_mem2_rd_frm` 必须随 ping 前进、`ost` 回落。旧"发射字节流逐字节对照"保留为 S7 的**辅助**（桥① 段已证正确，见 `rdcap2_retired.csv`）。
> 4. **S8 "发射流同构"判据必须带环境掩码**：10-17 加了 PC 永久静态邻居后 PC 不发 ARP ⇒ 板自发帧 dst = 广播 `ff:ff:ff:ff:ff:ff`（参考流是 PC MAC）。正确掩码 = dst(8–13)+IPv4 ID(26–27)+IP 头校验和(32–33)+末 4B FCS；或同环境同轮抓绿参考流（`rdcap2_green.csv` 已抓）。
> 5. **§二之七 表内两行同步改**：S4 行的 `manual_round.py COM5 1` → **`ping -n 1` 单帧 + NIC delta + `'U'` 前后差分**；S7 行主判据 → **桥② ILA 计数**（`dbg_mem2_rd_frm` 前进/`ost` 回落），发射字节流降为辅助。
> 6. **NIC 主判据改用 `ReceivedBytes`（不是 `ReceivedUnicast`）**：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ `ReceivedUnicast` 恒 0；S4 要求 `Bytes ≥74`（单帧 ICMP）、S5 要求 `Bytes ≥296`（4×74B），`ReceivedBroadcastPackets` 辅助打印。绿侧实测 ping 4/4：`Unicast=0/Bytes=+296`。旧表"S5 ReceivedUnicast delta"判据会**假 FAIL**。
> 7. **J3 执行/失败纪律（[L4]）**：J3 必须在**新烧录后**跑；前置 `'S'` + 只读轮询 `'U'` 到 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍；**`wr+255`/收帧停摆不得重试**（会级联假 FAIL + 可能半楔死需重烧）；J3 跑完轮末 `R_ENGINE=0`/`R_MODE=RND` ⇒ 后续 ping 判据必须重新 `Set-EngineMode DMA` + `'S'`。另：修复后 `--dma` 已可 PASS（`green_dma_j3_run5_warmfix.log`），`S0S8_DESIGN.md` §1.7 的"不带 --dma"是修复前临时口径，最终以 Lead 统一为准。
> ```

**验收**：6 条均在 §二之七 下、表格之后；行内 hash/编号与证据索引一致。

### 2.3 新增 **§二之八**（插在 §二之七 之后、`## 三、排期基线（顺序）`（当前 L105）之前）

> ```markdown
> ### 二之八、10-17 晚：退役读侧根因定案（**桥② 被退役误伤**）与修复（记录 §三之二十）
>
> - **有效判据**（`out/evidence_2026-10-17/clean_engine1_ping_204321.log`；退役 `3aa600aa`+ELF `2961b585`、`'d'` 后 `'U'` 确认 `req` bit24=1、ping×4 中途不跑 M/A/B）：`WM_WR/WM_RD` 各 **11→15（+4）**、`emit`={len=86, slot 10→14, byte0=0x55}、`arl` slot 10→14；但 **ping 0/4、PC 网卡 delta=0** ⇒ 桥① 读侧/发射字段正常，故障在"桥① 发射口之后"。
> - **桥级 ILA（20:53 有效轮，`ilacap_*` + `ilacap_counters_summary.txt`）**：桥① `dbg_mem_rd_frm` 19→23、`ost`=0；**桥② `dbg_mem2_wr_frm` 19→23（帧已跨 Aurora 写入）、`dbg_mem2_rd_frm` 0→0（一次没读出）、`dbg_mem2_ost` 19→23（只增不减）**；user 域 `dbg_mem2_u_wr` 19→23、`dbg_mem2_u_rd`=0 ⇒ **泵B 无输入**。
> - **桥① 发射字节流（`rdcap2_retired.csv`，1526B）**：前导 `55×7+D5`、1526 拍 `dbg_mem_rden=1` 无气泡、与归档绿参考仅差 dst MAC(8–13)/IPv4 ID(26–27)/校验和(32–33)/FCS；dst 广播是**静态邻居环境所致**，不是缺陷 ⇒ 桥①→Aurora 段字节级正确。
> - **根因 `[L3]`**：`8afa168` 在**两桥共用**的 `rtl/axi4_master_bridge.v` 里无条件删掉硬件读 FSM（R_AR/R_R/R_UNPACK/R_FIN）并让 R_PRE 无条件进 R_DRET；`u_mem2` 是 `HAS_DMA(0)`、无 DMA shim ⇒ `shim_frame_done` 无驱动（恒 0）+ `brf_wr_en` 无人置位 ⇒ 读 FSM 永久停泊、读数据口无源。
> - **修复（工作树，未提交）**：读 FSM 按 `HAS_DMA` 参数化——`HAS_DMA=1` 仍 DMA-only（桥① 收口语义不变）、`HAS_DMA=0` 恢复原硬件读 FSM；`gen_no_dma` 加 `assign shim_frame_done=1'b0;`；`sim/mem_bridge_tb.sv`、`sim/w4_joint_tb.sv` 实例显式 `.HAS_DMA(0)`。独立复核 `out/evidence_2026-10-17/rtl_fix_review_205656.md`：A–E 全过、无功能缺陷（3 条非阻塞项：过期注释/TB 标签/构建闸门）。
> - **离线回归**：`bridge_dma_tb` PASS；`mem_bridge_tb`（W2，HAS_DMA=0）PASS（`rd_frame=585`）；`w4_joint_tb`（W4）正向 PASS、负向按设计 FAIL/deadlock（日志已归档为 `sim_*_run.log`）。
> - **J3 判据脚本缺陷（独立 [L4]，与 RTL/位流无关）**：绿位流 `--dma` 下 J3 四链连续 FAIL（`[M] wr+255` → 读阶段不启动 → 级联）；根因 = `scripts/j3_soft_verify.py` 的 `run_round()` 在 SEQ 窗无条件发 1 个预热帧，DMA 模式下该帧读请求永泊 `R_DRET` 占 1 槽 ⇒ 写阶段第 256 帧槽满被拒；桥模式由硬件读引擎自动退休故 PASS（`green_bridge_j3_run1.log` PASS）。修复 = `warm_probe=(not args.dma)`（+15/−4）；复验 `green_dma_j3_run5_warmfix.log` **PASS**（`[M] wr+256 rd+256` / `[A] wr+256 rd+255` 恰帧#100 / `[B] wr+256 rd+256`）。纪律：J3 必须新烧录后跑、`wr+255`/收帧停摆不得重试、J3 后 ping 需重发 `'d'`/`'S'`。
> - **NIC 判据口径（[L3]）**：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ `ReceivedUnicast` 恒 0；S4/S5 主判据用 **`ReceivedBytes`**（单帧 ≥74、4 帧 ≥296）。绿侧实测 ping 4/4：`Unicast=0/Bytes=+296`。**旧"Unicast delta"表述全部作废。**
> - **绿基线（判读口径要带模式/序列前缀）**：绿位流桥引擎四档 **PASS**（`green_engine1_4tier.log`：ping 20/20、基础 12/12、槽深 12/12、稳定 300/300）+ ping **4/4**（`green_engine1_ping.log`）；桥模式 J3 **PASS**（`green_bridge_j3_run1.log`）；"绿 + DMA + J3" 在脚本修复后 **PASS**（`green_dma_j3_run5_warmfix.log`）。⇒ 绿基线可用，但引用时必须写清模式/脚本版本。
> - **下一步（PENDING）**：新位流构建（工作树 blob `7fe880e`）→ S0–S8 → **四判据**；判别性观测 = 桥② `dbg_mem2_rd_frm` 前进 + `ost` 回落。**修复效果未复验前不得写"已收口"**；`j3_soft_verify.py` 修复需与 RTL 修复同批提交（4 个 M 文件）。
> - **无效实验留痕**：旧 `retire_s2_s6.ps1` 的 S5（M 轮后 ping）作废（`s2_s6_201701.log`/`s2_s6_204148.log`）；第一轮 ILA（20:51，`mode=0`）作废、CSV 已被第二轮覆盖；第一次 `rdcap2` 抓取（probe 未解析）作废。
> ```

**验收**：§二之八 存在且位于 §二之七 与 §三 之间；所有数字在 `R1_evidence_index.md` 有对应文件/时间。

### 2.4 运维口径"先记死"块（当前 L89）——改两处

1. `'d'` 句改成：`**退役位流每次上电必须先发一次 `'d'` 才有桥① 读出路径**（`'d'` 是**翻转**：脚本必须"`'U'` 回读 `mode`+`req.bit24` → 不匹配才发 `'d'` → 再回读，**同时满足 mode=1 且 bit24=1 才继续**"；不要盲发两次——第二下会关掉 DMA 驻留服务）。`
2. 烧录纪律句改成：`烧录一律用**绝对路径 + 先 `Get-FileHash` 核对**，**不要引用默认名产物**（`out/aurora_mem_bridge.bit` 的 hash 随每次构建变化：快照时（21:18）为 `0ecb8438`（旧退役版），修复版构建会覆盖它；旧文写的 `3aa600aa` 已过期）。`
3. 新增一条 NIC 口径：`**NIC 主判据 = `ReceivedBytes`**（静态 ARP ⇒ 板自发帧 dst=广播 ⇒ ReceivedUnicast 恒 0；单帧 ICMP 回包 74B、ping×4 = 296B；ReceivedBroadcast 辅助）。`

---

## 3. `C:\Users\***\Desktop\毕设\agent.md` 当前状态节

### 3.1 「当前状态」大 bullet（当前 L116，路线 B 推进水位）——末尾追加

> `……**10-17 晚 R1 读侧根因定案 `[L3]`**：8afa168 在共享模块 `axi4_master_bridge.v` 无条件删硬件读 FSM，误伤 `HAS_DMA=0` 的桥②（`u_mem2`，无 DMA shim）⇒ 桥② 读 FSM 永泊 R_DRET、泵B 无输入 ⇒ 出向帧不上线（ILA 直接观测：桥② 写帧 19→23、读帧恒 0、ost 19→23；桥① 读帧 19→23/ost=0；`rdcap2_retired.csv` 桥① 发射流 1526B 字节级正确）。修复（工作树未提交）= 读 FSM 按 `HAS_DMA` 参数化（`HAS_DMA=1` DMA-only 不变 / `HAS_DMA=0` 恢复硬件读）+ `shim_frame_done` tie-0 + W2/W4 TB 显式 `.HAS_DMA(0)`；离线全绿、独立复核通过。**新位流 + S0–S8 + 四判据 `{{PENDING}}`**（判别性观测：桥② `dbg_mem2_rd_frm` 前进、`ost` 回落）。详见记录 §三之二十。`

### 3.2 「★ 10-17 日场结论」节（当前 L140–L165）——在节末（L165 后）追加新子块

> ```markdown
> ### ★ 10-17 晚场结论：退役读侧根因 = 桥② 被退役误伤（不是"发射口之后"的 Aurora/PHY）
>
> - **有效判据**（`out/evidence_2026-10-17/clean_engine1_ping_204321.log`）：退役 `3aa600aa`+ELF `2961b585`，`'d'`→`'U'`(bit24=1)→ping×4（**中途不跑 M/A/B**）：`WM_WR/WM_RD` 各 **11→15**、`emit` len=86/slot 10→14/byte0=0x55、`arl` slot 10→14；但 ping **0/4**、网卡 delta=0 ⇒ 桥① 段正常、故障在其后。
> - **桥级 ILA（20:53 有效轮，`ilacap_*`）**：桥① `rd_frm` 19→23、`ost`=0；**桥② `wr_frm` 19→23、`rd_frm` 恒 0、`ost` 19→23** ⇒ 泵B 无输入。桥① 发射流 `rdcap2_retired.csv` 1526B/前导/无气泡（与归档绿参考只差 dst MAC/IP-ID/校验和/FCS，dst 广播=静态邻居环境所致）。
> - **根因 `[L3]`**：`8afa168` 在**两桥共用**的 `rtl/axi4_master_bridge.v` 里无条件删读 FSM（R_AR/R_R/R_UNPACK/R_FIN），桥②（`HAS_DMA=0`，无 shim）读 FSM 永泊 R_DRET、读数据口无源。
> - **修复（工作树未提交）**：读 FSM 按 `HAS_DMA` 参数化 + `shim_frame_done` tie-0 + W2/W4 TB 显式 `.HAS_DMA(0)`。离线 `bridge_dma_tb`/`mem_bridge_tb`/`w4_joint_tb`（含负向）全绿；独立复核 `rtl_fix_review_205656.md` 通过。
> - **J3 判据脚本缺陷（独立 [L4]）**：绿位流 `--dma` 下 J3 连续 FAIL（`wr+255` → 读阶段不启动 → 级联）根因 = `scripts/j3_soft_verify.py` 在 SEQ 窗无条件发预热帧、DMA 模式下占 1 槽（桥模式自动退休故 PASS）；修复 `warm_probe=(not args.dma)`，复验 `green_dma_j3_run5_warmfix.log` **PASS**（`[M] wr+256 rd+256` / `[A] wr+256 rd+255` 恰帧#100 / `[B] wr+256 rd+256`）。纪律：J3 必须新烧录后跑、`wr+255`/收帧停摆不重试、J3 后 ping 需重发 `'d'`/`'S'`。
> - **NIC 判据口径（[L3]）**：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ `ReceivedUnicast` 恒 0；主判据用 **`ReceivedBytes`**（单帧 ≥74、4 帧 ≥296）。绿位流 engine=1 ping 4/4 实测 `Unicast=0/Bytes=+296`。
> - **`{{PENDING}}`**：新位流（工作树 blob `7fe880e`）+ S0–S8 + 四判据；判别性观测 = **桥② `dbg_mem2_rd_frm` 随 ping 前进、`ost` 回落**。
> - **旧脚本作废**：`retire_s2_s6.ps1` 的 S5 无效（S4 跑 M 轮 ⇒ 轮末 `R_ENGINE=0` + `R_MODE` 停 RND ⇒ 读侧零启动；`s2_s6_201701/204148.log` 两个 S5 均 0/N，绿位流同样）。
> ```

### 3.3 运维口径更正（当前 L160/L161 一带）

- L160（`g_dma_mode` 上电默认 0 / 退役位流必须先 `'d'`）追加：`**`'d'` 是翻转**：脚本必须"`'U'` 回读 mode+req.bit24 → 不匹配才发 `'d'` → 再回读，最后同时满足 mode=1 且 bit24=1 才继续"；**不要盲发两次**（第二下关掉 DMA 驻留服务）。`
- L161（上板顺序 S0–S8）里 `+0x3C dbg_emit` 分叉之后追加：`**S7 判别观测改为桥② ILA 计数**（`dbg_mem2_rd_frm` 前进/`ost` 回落，现有 u_ila_3 已含，无需改 RTL）；发射流同构判据须掩 dst+IP-ID+校验和+FCS（静态邻居⇒广播 dst；绿 vs 退役同掩码 ndiff=0）。另：**NIC 主判据用 ReceivedBytes**（单帧 ≥74、4 帧 ≥296；Unicast 恒 0）。`
- 若 L161 后那条"烧录纪律"仍写 `out/aurora_mem_bridge.bit` 等于 `3aa600aa`：改成「**默认名产物 hash 随构建变化，一律绝对路径 + 先核 hash**；快照示例 `0ecb8438`（旧退役版，修复版构建会覆盖该默认名）」。
- （可选）`agent.md` 若有"工具链/脚本"小节：补一句 `scripts/j3_soft_verify.py` 的 `--dma` 预热帧缺陷与修复（记录 §三之二十 §4.2），避免以后又把"绿 DMA J3 FAIL"当位流回归。

### 3.4 「本文件纪律」要求同步「追踪待办」

`毕设\agent.md` L123：`「当前状态」节随里程碑更新，同时更新追踪待办。` ⇒ 若团队习惯同步，则 `C:\Users\***\Desktop\毕设\追踪_cross_短期待办_2026-10-10.md` 的 R1/路线 B 行也按 §2.2 口径加一句（**本条为可选**；任务书未点名该文件）。

---

## 4. `D:\FPGA\docs\` 镜像同步（**脱敏规则：用户名→`***`，人名→`前辈`；禁止用 vault 原文覆盖**）

**总纪律**（`docs/agent.md` §★镜像口径 L31–L38）：
1. 先改 vault（§1–§3），再**重新写** docs 副本（不要 `copy`/覆盖，逐段审差异类型：脱敏 vs 内容更新）；
2. 内容以"更晚、有实测证据"的版本为准，同步后**重新脱敏**；
3. 同步后必须跑 CI（§5），第 6 项（索引一致性）不能红；
4. **绝不**为了字节一致把 vault 原文（含 `C:\Users\***\` 等个人路径/人名）拷进 docs（会进 git 历史）。

### 4.1 `D:\FPGA\docs\调试记录\阶段三_prj11_B3-1三主仲裁器与DMA读路径设计_2026-10-12.md`

- 当前与 vault 逐字节相同（SHA256 前 8 `D4024C79`，1012 行）。
- **改动 A**：在 `### 三之十九之补四` 结束（L1002）与 `## 三、当前状态（末版快照）`（L1003）之间插入 `record_section_draft.md` 的**正文**（删掉该草稿顶部的"目标文件/插入位置/写作纪律"元信息块）。
- **改动 B**：回填 `## 三、当前状态（末版快照）`（L1003–L1011），建议：
  - L1008「退役位流数据面仍未通」段：改成"根因已定 `[L3]`（桥② 读引擎被 8afa168 误伤；ILA 桥② 写帧+4/读帧恒 0/ost 只增不减）；修复待新位流复验 `{{PENDING}}`"；
  - L1009「处置进行中」段：改成"修复在工作树（未提交）；下一步 = 新位流构建 → S0–S8 → 四判据（记录 §三之二十 §5）；**另：J3 判据脚本缺陷已定案并修复复验 [L4]（§4.2），NIC 判据改用 ReceivedBytes**"；
  - L1010「烧录纪律」：`out/aurora_mem_bridge.bit` **快照时（21:18）**实测 = `0ecb8438`（更正旧 `3aa600aa`；**默认名会随修复版构建被覆盖，不要写死 hash**）；
  - 其余条目保留。**建议在 §三之十九之补四 末尾加一行醒目更正**：`⚠️ 补四 表中"两侧 wmwr/wmrd 1/1→4/4 逐项相同"与 s2_s6_204148.log 不符（该轮 S5 无效，见 §三之二十 §1.4/§9-①）；有效判据下的数值见 §三之二十 §1.1。`
- **脱敏检查**：本节草稿已避免个人路径；若从 vault 复制后用 `Select-String -Pattern '***|C:\\Users'` 复检。

### 4.2 `D:\FPGA\docs\操作文档\阶段三_prj11_路线B剩余工作清单_2026-10-16.md`

- 当前与 vault 相同（`C8FFFE60`，107 行）。
- 按 **§2.1 / §2.2 / §2.3 / §2.4** 同步（R1 行、§二之七 口径更正块、新增 §二之八、运维口径块）。
- 注意：vault 版里如有 `[[wiki 双链]]`/`C:\Users\***` 字样，docs 版保留双链（仓库惯例）但个人路径脱敏。

### 4.3 `D:\FPGA\docs\agent.md`

- 当前与 vault 相同（`A924316F`，165 行）。
- 按 **§3.1 / §3.2 / §3.3** 同步（当前状态大 bullet、晚场结论新子块、运维口径更正、追踪待办可选）。

### 4.4 `D:\FPGA\docs\README.md`（全量索引）

- **本次不新增 `.md` 文件**（只改既有 3 份）⇒ **索引表行数/文件数（当前 L40 "当前 75 个"）不变，无需改**。
- 但**必须**跑 CI 第 6 项确认：`D:\FPGA\docs\README.md` 索引与磁盘一致（改内容不影响，但若同步时误增/误删文件会红）。
- **例外**：如果收口决定把 `R1_evidence_index.md` 等**新文件**放进 `docs/`（不建议：它是工程内证据，应留在 `out/evidence_*`），则必须：
  1. 按命名规范改名（`[阶段]_prj标识_概要_YYYY-MM-DD.md`）；
  2. 在 `docs/README.md` 对应目录表（`调试记录/` 当前 L102 起）加一行；
  3. 更新 L40 的"当前 N 个"计数；
  4. 跑 CI 第 1/6 项。
- 索引中 B3-1 记录行（L131）的说明列取自一级标题，**正文追加小节不改一级标题 ⇒ 该行不需改**。

---

## 5. 收口提交前检查（全部做完才算完）

```powershell
# 1) 代码侧：4 个 M 文件（RTL + 2 TB + J3 判据脚本）+ 允许的新增
git -C D:\FPGA status --short
git -C D:\FPGA diff --check
git -C D:\FPGA hash-object prj/project_11/rtl/axi4_master_bridge.v        # 期望 7fe880e…
git -C D:\FPGA hash-object prj/project_11/scripts/j3_soft_verify.py       # 期望 59a2d7e…

# 2) 文档侧：改完后跑仓库 CI（AGENTS §十二；本机 Python 见 AGENTS）
& "C:\Users\***\AppData\Local\Python\pythoncore-3.14-64\python.exe" D:\FPGA\scripts\ci_check.py
# 期望全绿；重点第 1 项（文档命名）、第 6 项（docs/README 索引一致性）、
# 第 2 项（链接）——vault 双链在 docs 里按仓库惯例保留，若第 2 项报错先看是否新引入

# 3) 镜像一致性（提示项，非硬失败）：逐条判定差异是"脱敏"还是"内容更新"
#    见 docs/agent.md §★镜像口径 L31–L38

# 4) 记录回填完整性：把 PENDING 全部替换或明确标注"未发生"
Select-String -Path 'C:\Users\***\Desktop\毕设\调试记录\阶段三_prj11_B3-1三主仲裁器与DMA读路径设计_2026-10-12.md' -Pattern 'PENDING'
```

**提交范围建议（Lead 决策）**：
- 代码：`prj/project_11/rtl/axi4_master_bridge.v` + 2 个 TB + **`prj/project_11/scripts/j3_soft_verify.py`**（J3 脚本缺陷修复，独立 [L4]）；
- 工具/设计（建议入库）：`out\S0S8_DESIGN.md`、`out\retire_s0_s8.ps1`、`out\j3_fourchains.ps1`、`out\jb31b_*` 取证工具（`.md/.py/.ps1/.tcl` 不在 `.gitignore`）；
- 证据：`prj/project_11/out/evidence_2026-10-17/*.md`（3 份交付 + 审计/复核/准备单 + `rtl_fix_review`）与可提交的 `.csv`（**`.log/.bit/.ltx/.xsa/.rpt/.jou` 被 .gitignore 忽略**；日志请另存归档或只留摘要）；
- 文档：vault 3 份 + `D:\FPGA\AGENTS.md` + `docs/` 3 份镜像；
- **提交前确认新位流 hash / S0–S8 结果已回填，或明确在提交信息里写"修复待复验"；J3 脚本修复的 [L4] 结论与 RTL 修复分开写。**

---

## 6. 每一项的"完成定义"（验收清单）

| # | 文件 | 改动点 | 完成标志 |
|---|---|---|---|
| 1 | `D:\FPGA\AGENTS.md` | §十 L214 追加 R1 收口（含 J3 脚本 [L4] + NIC 口径）；L215 ④⑥ 更正；§九 可选加 #55/#56 | 有 `三之二十`、`[L3]`、`[L4]`、`PENDING`；④⑥ 不再写"归因未定/未通" |
| 2 | vault 工作清单 | §R1 行 ⑥⑦⑧⑨；§二之七 口径更正块（含 NIC 与 J3 纪律）；新增 §二之八；运维口径块 | 有 §二之八；`'d'` 翻转/掩码/桥② ILA/NIC=ReceivedBytes/J3 纪律五条口径在表后 |
| 3 | vault `agent.md` | 当前状态 L116 追加；10-17 结论节追加晚场子块（含 J3 脚本 [L4] 与 NIC）；运维口径 L160/L161 更正 | 有"桥② 被退役误伤"+"J3 脚本缺陷"+"PENDING"；`0ecb8438` 更正 |
| 4 | docs 镜像 ×3 | 同步 #1–#3 的对应内容并脱敏 | `Select-String '***'` 在 docs 新增内容中 0 命中；CI 全绿 |
| 5 | docs/README.md | 不新增文件 ⇒ 不改；跑 CI 第 6 项 | CI 第 6 项 PASS |
| 6 | 证据索引 | 收口时把 §7 PENDING 行补全（新位流/构建日志/S0–S8/J3 脚本提交/绿 vs 退役 cmp 日志/NIC 原始读数） | `R1_evidence_index.md` 无未替换的 `{{PENDING}}`（除"未发生"明确标注） |
| 7 | 记录正文 | `record_section_draft.md` 的 §5 表格回填、§6 升 [L4]、§8 PENDING 替换；§4.2 J3 脚本结论按 Lead 最终口径定稿 | 记录 §三之二十 无假 PENDING；依据等级与证据一致；J3 脚本 [L4] 与 RTL 修复分开写 |
| 8 | `scripts/j3_soft_verify.py` | 与 RTL 修复同批提交（+15/−4） | commit 里含该文件；记录 §8 记 hash/commit |

> **红线提醒**：`{{PENDING}}` 一律不得用推测值/期望值冒充实测；"修复后全过"在 S0–S8 真跑完之前**不得写入任何文档**。
