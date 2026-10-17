# R2（B3-2）桥①写侧换层 S2MM — 独立 RTL 审计与离线验证报告

> 角色：独立 RTL 审计 / 独立 TB（teammate `rtl-auditor`，非 Lead、不改 Lead 拥有文件）
> 时间：2026-10-17 晚（R2 冻结版离线审计+仿真）
> 被审对象（Lead 冻结 hash，`git hash-object` 实测一致）：
> * `rtl/axi4_master_bridge.v` = `5f878644404fbb34ef1ada48bb9556ff8f401549`
> * `rtl/frame_mem_if.v` = `96d5b136305e81ee9d4cc716e60c5034581d027d`
> * `rtl/aurora_mem_bridge.v` = `1885225ffac800c71187aa428f3d4908f7e3f975`
> * `rtl/axi_lite_regs.v` = `421df59cc31a24dfe241c430e3687bd2d3332bac`
> * `scripts/create_bd_b.tcl` = `9c26b15e7f102bd28419633a59f3ad8b5f9e5cc4`
> 依据等级按 AGENTS.md §6a：L0 猜测 / L1 相容假说 / L2 对照成立 / L3 板证实 / L4 定案。
> **本报告无板上证据；凡"判定/根因"措辞仅限 L2 及以上的离线对照，其余一律写"假说/待板证"。**

---

## 0. 结论摘要（给 Lead）

| 项 | 结论 | 等级 |
|---|---|---|
| 阻塞缺陷 A1（写槽游标遮蔽导致读 FSM 断源） | **真阻塞，Lead 已修**；修法和建议一致（删 generate 内同名声明，驱动模块级 `wr_slot_ptr`） | L2（缺陷：代码级+仿真行为；修复：xvlog/xelab/xsim + 回归） |
| A2/A3/A4/A5/A6（AXI 口悬空 / 无看门狗 / 陈旧 GO·IOC / 超时值不一致 / fault 无清除路径） | **Lead 已修**，本报告逐条复核修法 | L2（离线） |
| A7（CDC 域归属） | Lead 更正正确：`dma_wr_go/ack` 源=user_clk(151.5M)，`s2mm_introut` 源=IP 的 Lite(100M) 域；两条 2FF 各自正确 | L1（厂商源码+代码核对） |
| A8（burst 拆笔 / DRE 不可用） | 厂商 IP 元数据实证：S2MM burst=16 beats、512b 流 DRE 不可用 → 设计 §6.4 结论正确；SA 必须 4KB 对齐（本设计恒对齐） | L1（厂商元数据） |
| A9（TKEEP→WSTRB 逐位等价） | **仍是 [L1] 待板证**：厂商 datamover 源码存在"由流 TKEEP 生成 WSTRB"与"由 BTT/地址派生 start/last strobe"两种形态，本板配置取哪种未确证；离线 TB 只证 DUT 输出流正确 | L1 |
| 独立 TB（`sim/r2_wr_tb.sv`） | **PASS（0 errors）**：T1–T9 全过，101 次提交、规则号 1 golden model 100 帧逐槽比对 | L2（离线） |
| 负向对照 ×2 | **均按设计 FAIL 且指认判据行**：`[FAIL-T4-CURSOR]` / `[FAIL-KEEP-MASK]` | L2（离线） |
| 既有三回归 | 见 §7（`mem_bridge_tb` / `w4_joint_tb` 正向+负向 / `bridge_dma_tb`） | L2（离线） |
| 构建前硬门槛判定 | 离线可证的都证了；**离线不可证的清单见 §8**，必须由板验 S4/S5/S7/S8/S10 覆盖 | — |

---

## 1. 审计范围与方法

1. 精读 R1 收口版与 R2 冻结版 RTL 关键路径（写 FSM、槽表、commit、读 FSM、CDC 镜像、仲裁器接线）。
2. 对设计草案 `out/R2_S2MM_DESIGN.md` v1 逐条与 RTL 对照（规则号 1 六要素、HAS_DMA 边界、字节/突发等价、握手、仲裁器）。
3. 厂商资料取证（本机 Vivado 2023.1 IP 安装目录，非 AI 文档）：
   * `axi_dma_v7_1/bd/bd.tcl`、`component.xml`：S2MM 参数、DRE 使能条件、burst size 语义；
   * `axi_dma_v7_1/hdl/axi_dma_v7_1_vh_rfs.vhd`：`s2mm_introut` 的跨域实现（`GEN_INTROUT_ASYNC`，CDC 到 `s_axi_lite_aclk`）；
   * `axi_datamover_v5_1/hdl/axi_datamover_v5_1_vh_rfs.vhd`：`axi_datamover_wrdata_cntl` 的 WSTRB 生成两形态、`stbs_set_nodre` 的 TKEEP 计字节。
4. 独立 TB（白盒、行为模型、golden model、2 负向对照）。
5. 既有三回归按 Lead 授权做"最小端口补齐"后复跑（补丁见 §7.3）。

---

## 2. 审计发现清单（A1–A13，含状态与复核）

> 严重度：阻塞 / 高 / 中 / 低 / 信息。状态以 **R2 冻结版**为准。

### A1【阻塞·已修】写槽游标被 generate 内同名声明遮蔽 → 读 FSM 断源
* 现场（22:12 中间版）：模块级 `wr_slot_ptr`（`axi4_master_bridge.v:336`）+ `g_wr_dma` 分支内重复 `reg [15:0] wr_slot_ptr`（旧:574）；新写引擎只驱动局部副本（旧:616/658），而读 FSM 的槽域判决用模块级副本：`c_clamp`/`c_in_rng`/`p_target_ok`（现:877/878/885）。
* 后果：HAS_DMA=1 时模块级 `wr_slot_ptr` 无驱动（xsim=X / 综合常量）⇒ `p_target_ok=0`、`c_in_rng=假` ⇒ **所有 DMA 读请求按"无帧"应答**（J3/E/四档读路径必挂）。
* 隐蔽性：xvlog 对 generate 内同名遮蔽声明**不报错**（实测 `sim/r2_tmp/t_shadow.v`，exit=0）⇒ 静默缺陷，只能靠代码审查/白盒 TB 抓。
* Lead 修法（冻结版 `:574-576` 注释 + 单一声明 `:337`）：删除局部声明、直驱模块级 —— **与建议一致**。
* 复核证据：`grep 'reg .*wr_slot_ptr'` 仅 1 处；R2 TB 末尾 `$isunknown(wr_slot_ptr/ro_wm/ro_dma_wr_req)` 断言 0 触发；`bridge_dma_tb`（HAS_DMA=1 读路径回归）PASS。**等级：L2**（缺陷成立=代码级；修复成立=仿真对照+回归，未板证）。

### A2【高·已修】HAS_DMA=1 的 AXI4 写口 7 根输出无驱动
* 现场：`m_axi_awaddr/awlen/awsize/awburst/wdata/wstrb/wlast` 的 assign 原先只存在于旧写块；R2 分支不驱动 ⇒ xsim=z / 综合 undriven。
* Lead 修法（冻结版 `:617-625`）：`g_wr_dma` 内显式钉 0，并注释"顶层 u_mem 这些口悬空、不得再接/再 assign"（顶层 `aurora_mem_bridge.v:812-826` 已是输入钉常量+输出悬空）。**一致**。
* TB 复核：独立 TB 以 `[FAIL-AXI-WRITE]` 监视 `m_axi_awvalid/wvalid/arvalid` 恒 0，0 触发。**L2**。

### A3【高·已修】WD_STREAM/WD_PUSH 原先无看门狗 → 可永久泊
* 现场（22:12 版）：STREAM/PUSH 仅等 `wf_empty`/`tready`，若 S2MM 提前完成/通道 halt/长度不符导致 tready 长低，写引擎无路可退（违反坑 #55"不可恢复挂起结构上不可能"）。
* Lead 修法（冻结版）：`wd_stall_cnt`（24 位，`:586`）在 STREAM/PUSH 无进展时累加，到 `24'hFFFFFF`（≈56ms@300MHz）→ `stat_wr_timeout++`、`fault=1`、进 `WD_HALT(6)`（`:731-740` / `:759-768`）。
* **覆盖缺口**：本 TB 的 T9 只触发 **WAITDONE** 看门狗；STREAM/PUSH 两条分支未被离线触发（见 §8 缺口 G3），由代码审查判定结构存在。**L1（分支存在）/L2（WAITDONE 同构路径已验证）**。

### A4【高·已修（fail-stop）+ 残余窗口】
* 原风险：超时丢帧后软核可能仍在服务旧帧并翻 GO/迟到 IOC，桥把旧事件当新帧 ⇒ 错槽/错长/错提交。
* Lead 修法（冻结版）：STREAM/PUSH/WAITDONE 超时 → **fail-stop**：`fault` 粘滞、停收新帧、进 `WD_HALT`（`:811-822`）；唯一出口 = 软核复位 S2MM 通道 + 清 IOC + 翻 `dma_wr_ack`（`frame_mem_if.v:467-469` 2FF 进 ui），桥清 fault 回 IDLE（`:814-821`）。
* **残余窗口（已在此报告，建议保留文档+SW 兜底）**：**WAITGO 超时仍是"丢帧不 halt"**（T6/S2b 身份测试需要该行为，且属未发流的良性丢弃）。若软核在 >56ms 停驻后恢复，可能把旧帧 GO 翻给下一帧。建议 `serve_write_once()` 在**翻 GO 的同一轮**二次读 `WR_REQ` 并确认 `pending==1 && toggle==saved` 才翻 GO（否则丢弃本次编程、不翻 GO）——本 TB 软核模型即按此实现（`r2_wr_tb.sv` SS_IDLE/SS_GO）。**L1（协议推理）+ 设计 §4.3 已记窗口**。

### A5【中·已修】看门狗时长设计/RTL 不一致
* 中间版 RTL 有 `2^25` 与 `2^24` 混用；冻结版统一 `24'hFFFFFF`（`:708/731/759/782`）≈56ms@300MHz，与设计 §4.3 的 WAITGO 值一致。**但设计稿 v1 §4.3 仍写"2^25≈112ms"给 D_WAITDONE → 文档需更新为 2^24≈56ms**（见 §8 D1）。**L2**。

### A6【中·已修】fault 粘滞无清除路径
* Lead 修法：Lite 新增 `+0x4C` 写（opcode 0x06）翻 `cfg_wr_ack`（`axi_lite_regs.v:100/206/382-385`）+ HALT 出口；`ro_dma_wr_dbg[31]` 可见。TB T9 验证：fault 置 1 → 软核 ACK → fault 清 0、回 IDLE、恢复后可继续提交。**L2**。

### A7【信息·Lead 更正采纳】两条跨域路径的源域不同
* `dma_wr_go` / `dma_wr_ack` 源头 = `axi_lite_regs` 的 U_* 状态机，`always @(posedge clk_user)`（151.5MHz）⇒ `frame_mem_if.v:456-469` 的 **user→ui 2FF 正确**。
* `s2mm_introut` 源头 = axi_dma IP 的 **s_axi_lite_aclk(100M) 域**（厂商 VHDL `GEN_INTROUT_ASYNC`：IP 内部 `cdc_sync` 到 Lite 域，`:9429-9467`）⇒ `frame_mem_if.v:472-477` 的 **100M→ui 2FF 正确**。
* 两条路径互不相同、各自合法（§5.1 三种合法形式之 2FF）。**L1（厂商源码）+L2（代码核对）**。

### A8【信息·L1 厂商元数据】S2MM burst 拆笔与 DRE 约束
* `axi_dma_0.xci`：`c_s2mm_burst_size=16`（单位=**beats**，xgui tooltip）；厂商 `axi_datamover_v5_1_utils.tcl` 对 512b 数据宽度限 ≤64 beats（4KB 边界）⇒ **1538B=25 拍会被拆成 16+9 两笔 AW**；设计 §6.4 结论正确；仲裁器事务级轮转天然兼容。
* `axi_dma_v7_1/component.xml`：`C_INCLUDE_S2MM_DRE` 的使能条件 = `C_S_AXIS_S2MM_TDATA_WIDTH < 128`（xgui tooltip 亦注"unaligned 仅支持流宽 ≤64bit"）⇒ **512b 流 DRE 不可用**；因此 S2MM 目的地址必须对齐（本设计 `SLOT_BASE + slot*4096` 恒 4KB 对齐 ✓），也不能依赖 DRE 处理尾拍重排 ⇒ 尾拍必须靠 TKEEP 精确表达（见 A9）。
* **L1**（厂商 IP 元数据/工具脚本，非板证）。

### A9【信息/风险·L1 待板证】TKEEP→WSTRB 与 TLAST/LENGTH 语义
* 厂商 datamover 仿真源码（`axi_datamover_v5_1_vh_rfs.vhd`）显示 WSTRB 生成有两种形态：
  * `C_ENABLE_INDET_BTT=0`：`data2skid_wstrb <= strt_strb_reg(首拍) / last_strb_reg(末拍) / 全 1(中间拍)`（`:16080-16089`）——即 **WSTRB 由命令 BTT/地址派生，不看流 TKEEP**；
  * `C_ENABLE_INDET_BTT=1`：注释"Strobes come from the Stream input from the Indeterminate BTT module"（`:16422-16434`）——**由流 TKEEP 派生**。
  本板 AXI DMA 直通模式实际取哪种，本机 IP 元数据未直接给出（datamover 子核默认 `C_S2MM_SUPPORT_INDET_BTT=0`，但 AXI DMA 内部映射需看 xci/BD 生成物）⇒ **不能写成定论**。
* 推论（[L1]）：两种形态下"LENGTH=len + 流末拍 TLAST + 尾拍 TKEEP=(len%64) 连续低位"都应当得到正确字节图；若实际为"BTT 派生"形态，则尾拍 TKEEP 错可能表现为 BTT/短包错误而非写脏。**离线 TB 只能证明 DUT 输出流满足设计假设，不能证明厂商 IP 行为**。
* **板验要求（硬）**：S4 单帧用例必须包含 **len 非 64 整数倍**（ping 回显 len_tab=86=64+22 正好覆盖尾拍 22 lane）并逐字节比对 + 记录 S2MM `DMASR` 错误位；S7 四档覆盖多长度/尾余数。**L1/待板证 L3**。

### A10【中·已修（随 A4）】WAITDONE 超时后不提交且不得误 retirement
* 冻结版：WAITDONE 超时 `wr_commit` 不发（`:782-788`），slot 不置满；TB T9 验证"超时帧不提交、恢复后下一帧可提交"。**L2**。

### A11【低·信息】桥① B3-0 延迟观测在 HAS_DMA=1 下失效
* 桥① AXI 写口退役后 `lat_w` 恒 0（`:1137` 起的 lat 计数量读取 m_axi_awvalid/awready/bvalid，均钉 0），`ro_lat_w` 在桥① 恒 0；桥②（HAS_DMA=0）不受影响。**建议**：设计/记录与 S 判据注明"桥① lat_w 不再有意义，B3-0 口径仅桥②"；不要用 `GET_LATENCY` 的桥① 值做判据。**L2（逻辑）**。

### A12【低·信息】取证字段语义
* `dbg_wr_last_slot` = 最近**分配**槽号（`:655/:670`）；`dbg_wr_last_len` = 最近**提交**帧长（`:779`）；`ro_dma_wr_dbg` 布局 `{fault,7'b0,last_alloc_slot[23:16],last_commit_len[15:0]}`（`frame_mem_if.v:91`）。板验 `'U'` 取值时须按此语义解读（"分配"≠"提交"）。**L2**。

### A13【低·完整性】HAS_DMA=0 分支文本保全（坑 #55 复刻检查）
* `git diff -U0` 实测：R2 对 `axi4_master_bridge.v` 的删除行仅 3 行 = 端口行逗号、两行 `assign wf_rd_en/wd_rd_en`；**旧写 FSM（W_IDLE…W_DRAIN、提交队列、游标、DRAIN、lat 计数）0 删除行**，整块移入 `generate if (!HAS_DMA) : g_wr_hw`。桥② 写/读路径语义未动。**L2（diff 可复核）**。

---

## 3. 规则号 1（写槽 = 帧计数 mod 256）等价性逐项核对

| 要素 | R1 现状（HAS_DMA=0 / 旧写 FSM） | R2 冻结版（HAS_DMA=1 / WD_*） | 判定 |
|---|---|---|---|
| 槽号分配游标 | 模块级 `wr_slot_ptr[15:0]`（`:337`） | 同一模块级游标；`wd_slot_next = wr_slot_ptr[7:0]`（`:595`） | 等价（A1 修复后同源） |
| 推进点 | **描述符接收拍**（`W_IDLE` 弹描述符时，旧 `:445-459`） | **描述符接收拍**（`WD_IDLE` 弹描述符时，`:657-672`） | 等价 |
| 被拒帧推进 | 拒收/坏长同样 `+1`（旧 `:459`，W5/L2 语义） | 同（`:671-672`，在 `WD_IDLE` 无条件 +1） | 等价（TB T4 显式判据） |
| 槽地址映射 | `SLOT_BASE + {w_slot,12'b0}`（旧 `:374`） | 桥不写 AXI；把 `slot` 交软核，SA = `SLOT_BASE + slot*4096`（TB 软核模型按此换算） | 等价（TB 校验 S2MM 模型收到的 SA==期望槽基址） |
| 长度语义 | 描述符长度 = 字节 FIFO **实际入队字节数**（`frame_mem_if.v:273-283,326-336`，R2 未改） | 同：`wd_len <= wd_data`；S2MM LENGTH = 同 len；`len_tab[slot]=wr_commit_len` | 等价（TB 校验 len_tab/模型 LEN/期望长度三一致） |
| 满槽拒收 | `w_no_room`（full_bit_q）→ 整帧 DRAIN、不覆盖未读槽、`stat_wr_stall++` | `wd_noroom_n`（full_bit_q）→ WD_DRAIN、不覆盖、`stat_wr_stall++`（`:657-677, :794-801`） | 等价（TB T4 判据：字节未改/full_bit/len_tab 未改/stall+1） |
| 坏长度拒收 | `len==0 || len>MAX_LEN` → `stat_len_err++`、整帧丢弃 | 同（`:597, :673-677`） | 等价（TB T5：1600B 拒收、len_err+1；len==0 见下） |
| 槽占用/提交时刻 | B 响应出队拍（提交队列）→ `wr_commit/out_inc/stat_wm/stat_wr_frame` | **S2MM 完成中断（s2mm_introut）拍** → 同组信号（`:771-781`） | **语义同（"DDR 写已提交"），时基不同**（旧=B 响应，新=IOC）；A9 风险点，需板验 S4/S5 |
| full_bit 置位时刻 | `wr_commit` 后 1 拍写 full_bit/full_bit_q/len_tab/len_beats_tab（`:236-256`） | 同（slot 表块未改） | 等价 |
| 数据布局 | 槽基址起逐字节 + 8B 前导 + 尾 4B FCS；尾拍 WSTRB 精确掩码 | S2MM：槽基址起、LENGTH=len、尾拍 TKEEP 精确；字节图假设与 WSTRB 同（A9） | 设计等价；**厂商 IP 行为待板证** |

**游标/提交解耦结构保留**：R2 的 WD_* 是"一帧在途"串行（WAITGO→STREAM→PUSH→WAITDONE），R1 的 4 深提交队列不再存在；因 `wr_slot_ptr` 仍在接收拍推进，连续帧不会抢同一槽号（TB T3 背靠背 3 帧判据）。**吞吐退化在设计与 §R3 中已声明**，非本轮判据。

---

## 4. HAS_DMA 参数化边界（坑 #55 复刻纪律）

**实例枚举**（`aurora_mem_bridge.v`）：
| 实例 | 参数 | 写路径 | 读路径 | AXI 口 |
|---|---|---|---|---|
| `u_mem`（桥① INGRESS） | `HAS_DMA=1`（默认） | **R2：WD_* S2MM 写引擎**；旧 W_* 不例化 | R1：R_PRE→R_DRET（DMA-only） | 写口钉 0（`:617-625`），读口仍驱动给 shim 侧无 AXI；顶层输入钉常量 |
| `u_mem2`（桥② EGRESS） | `HAS_DMA=0` | 旧 W_* 原样（`g_wr_hw`） | R1 修复版硬件读 FSM（`g_wr_hw` 同分支外） | 原样 → 仲裁器 S01 |
| `bridge_dma_tb` 直例化 | 默认 HAS_DMA=1 | 现为 WD_*（TB 需服务模型，见 §7.3） | DMA-only | — |
| `mem_bridge_tb` / `w4_joint_tb` | `HAS_DMA=0` | 旧 W_* | 硬件读 | — |

**可审计做法（已核对）**：
1. 旧写 always 块整块移入 `generate if (!HAS_DMA) begin : g_wr_hw`（`:371-557`），**文本 0 删除行**（A13）。
2. 新写引擎整体在 `g_wr_dma`（`:557-827`），两分支互斥 elaboration；`wr_commit/out_inc/stat_*` 等共享寄存器各分支单驱动（`xelab` 通过；MDRV 需综合复核——本 TB 不产生 MDRV）。
3. `wf_rd_en`/`wd_rd_en` 端口级用结构常量二选一（`:343-346`），HAS_DMA=0 语义不变。
4. `frame_mem_if` 的 B3-2 端口在 `HAS_DMA=0` 分支全部钉 0（`frame_mem_if.v:514-519`），顶层 `u_mem2` 显式 tie（`aurora_mem_bridge.v:994-1002`）。
5. **回归**：`mem_bridge_tb`（HAS_DMA=0）与 `w4_joint_tb`（HAS_DMA=0，含 DEFECT 负向）见 §7。**L2**。

**diff 检查清单（供 Lead 提交前复核）**：`git diff -U0` 中 `g_wr_hw` 区间应 0 删除行；`grep 'reg .*wr_slot_ptr'` 应仅 1；`m_axi_aw*` 的 assign 在 `g_wr_dma` 必须存在；`stat_wm/out_inc/wr_commit` 每分支恰一处驱动；`xelab` 无 multi-driver 告警。

---

## 5. AXI-Stream→AXI4 字节等价（设计 §6 的独立核对）

| 设计声明 | 独立核对结果 | 等级 |
|---|---|---|
| §6.1 拍内 lane k = 帧字节偏移 k（小端） | 桥输出流 `wd_data_r[wd_bi*8 +: 8] <= wf_data` 逐字节低位起填（`:721-729`）；TB 模型按 lane 一一写回并逐字节比对 PASS | L2（离线） |
| §6.2 尾拍 TKEEP = len%64（非 0 时） | 冻结版 `wd_keep_r[wd_bi]<=1` 逐字节置位、每拍后清零（`:667/723/748`）；TB T2(70B→6 lane)/T8(16 个边界长度) 判据 PASS；负向②注入"尾拍 tkeep 满 64"必 FAIL（`[FAIL-KEEP-MASK]`） | L2（离线，DUT 侧） |
| §6.3 退休时刻：IOC ⇒ BRESP 已收（"DDR 写已提交"） | 逻辑上 IOC 在 S2MM 完成（含写响应）后置位；但**离线不可证**（TB 只模拟行为），且 A9 的 WSTRB 形态未证 ⇒ 保持 **L1**；板验 S4/S5 计数+回显联合验证 | L1 |
| §6.4 多 burst（>16 拍拆两笔） | 厂商元数据：burst=16 beats（A8）⇒ 25 拍帧拆 16+9；仲裁器事务级轮转/响应按授权锁存（W4 已定案）不受影响 | L1（厂商元数据+既有 W4 结论） |
| §6.5 8B 前导+4B FCS 不增删 | R2 写侧对 byte 流只做搬运（`len` 原样）；TB 逐字节校验含任意字节值 | L2（离线） |

---

## 6. 握手协议与仲裁器复用风险核对

### 6.1 请求镜像（toggle+pending）
* 实现：`frame_mem_if.v:480-494`（ui→user 2FF 同源同拍 + `{pending,6'b0,toggle,slot,len}`）；软核在 user 域轮询。TB 用同样语义的软核模型跑通 101 帧（含背靠背）。
* 风险：`{slot,len}` 在 pending 保持期间稳定（µs 级），2FF 采样可接受；**toggle 用"每次请求翻转"避免连续请求漏服务**——设计 §7 的论证成立（TB T3/T8 背靠背覆盖）。**L2（离线）**。

### 6.2 GO / ACK 2FF（user→ui）与 introut 2FF（100M→ui）
* 见 A7；两者都在 `frame_mem_if` 内 2FF，桥内采样。TB 中 GO 翻转→桥开流 <10 ui 拍，时序余量足。**L2**。

### 6.3 IOC 清除时序
* 协议：软核 arm 前写 DMASR W1C 清 IOC；桥在 WAITGO 见 GO 后要求 `!s2mm_introut` 才放流（`:699`）。
* TB T7 专门验证"GO 先翻、IOC 后清"：桥停留 WAITGO（`[FAIL-T7-GO-GATE]` 监视未触发），清 IOC 后才发流并提交。**L2**。
* 板级风险：软核写 DMACR/DMASR 走 Lite 邮箱（µs 级），若清 IOC 与翻 GO 相隔过近（<2FF 窗口），桥可能多等 1 个软核服务周期——功能不受影响，仅延迟。**L1**。

### 6.4 超时/恢复（见 A3/A4/A5/A6）
* WAITGO 超时≈56ms：丢帧+DRAIN+`stat_wr_timeout++`，**不停泊**（TB T6 真实等满 `24'hFFFFFF` ui 拍后验证下一帧正常提交、fault 保持 0）。**L2**。
* STREAM/PUSH/WAITDONE 超时：fail-stop→`WD_HALT`→软核复位 S2MM+清 IOC+翻 ACK→清 fault 回 IDLE（TB T9 用力加速触发 WAITDONE 分支验证——**时基加速已在 TB 内注明"仅缩短仿真等待，不改判据"**）。**L2（WAITDONE 分支）**。

### 6.5 读服务与写服务互斥/停泊风险
* RTL：读 FSM 与写引擎独立、共享槽表但单驱动；写请求串行（一帧在途）⇒ 无"写等读"内部依赖。
* 软核侧（Lead 拥有，未审计）：单线程 `serve_any()` 同时处理读/写请求时，若读服务等待 DMA 完成期间写请求堆积（byte FIFO 4KB≈2.7 帧），可能出现 buf_drop；设计 K6 已声明。**建议**：板验 S4/S5 观察 `stat_wr_timeout/buf_drop` 计数并记录（S10 对账口径）。**L1**。

### 6.6 仲裁器 S00 复用（桥① 写口 → axi_dma M_AXI_S2MM）
* 顶层：S00 接 S2MM（写-only：AW/W/B），AR/R 钉无效（`aurora_mem_bridge.v:1033-1057`，`:1057` 注释）；S01=桥②、S02=MM2S 不变。
* W4 已定案"响应按授权锁存路由、与 ID 解耦"⇒ S00 换主不破坏响应路由；S2MM 的 AWID 无（ID 宽度 0），S00 的 awid/bid 口钉 0 合法。
* **风险（L1）**：S2MM 每帧 2 笔 AW（A8），仲裁器事务级轮转下相邻两笔可能被 S01/S02 插入；AXI 允许，S2MM 内部按序收 B ⇒ 功能无碍，但**板验 S5/S7 吞吐/时延会受仲裁影响**（R3 归因项，非本轮判据）。
* `C_PRMRY_IS_ACLK_ASYNC=1` 由 BD 传播（xci 实测），`s2mm_introut` 内部已同步到 Lite 域（A7）。**L1/L2**。

---

## 7. 离线验证结果（TB 与回归）

### 7.1 独立 TB：`sim/r2_wr_tb.sv` + `sim/run_r2_wr_tb.bat`
* DUT = `frame_mem_if #(.HAS_DMA(1))`（含 axi4_master_bridge + dma_rd_shim_v2）。
* 三时钟：user 151.5M / ui 300M / lite 100M；S2MM 行为模型（AXIS→RAM 按 TKEEP，TLAST 结算，完成经 lite 域 2FF 拉 `s2mm_introut` 电平，清 IOC 由软核模型写）；软核行为模型（轮询 `{pending,toggle}`→编程 SA/LEN→清 IOC→翻 GO；含 fault 恢复序列）。
* 判据：每 commit 比对 `S2MM 模型 SA/LEN/beats`、DUT 槽表 `full_bit/len_tab`、槽内逐字节、尾拍外不写；另有 AXI 写口恒 0 监视、X 断言、T7 闸门监视。
* **结果：`=== R2 WR TB: PASS (0 errors) ===`**：101 commits / exp 101；T6 真实看门狗 `ui_cycles=16777221`（sim_time≈55.94ms，与 `24'hFFFFFF`@300MHz 理论值 55.9ms 吻合）后丢帧不停泊；T8 golden model cursor=320、100 帧中 90 commit/10 满槽拒收、stall 增量 10；T9 HALT/fault 观测+ACK 恢复+恢复后提交。原始日志 `sim/r2_wr_pos.log`、汇总 `sim/r2_wr_run.log`（另归档 `out/evidence_2026-10-17/R2_sim_r2_wr_tb_*.log`）。
* 负向对照（缺陷副本由 `sim/r2_neg_patch.py` 从冻结 RTL 文本注入，逐 patch 断言恰 1 处命中；冻结 hash 校验不过则硬失败）：
  * 负向①"被拒帧不推进游标" → `=== R2 WR TB: FAIL ===` 且判据行 `[FAIL-T4-CURSOR]`（请求槽号/提交超时指认）。
  * 负向②"尾拍 TKEEP 用满 64" → `FAIL` 且判据行 `[FAIL-KEEP-MASK]`（逐拍 TKEEP 期望掩码比对）。
  * 两负向均以 `-d R2_FAST` 编译（只跳过 T6 的 16.7M 拍等待，判据不变）。**两负向在正型轮均为 PASS 分支**（缺陷不影响无关用例：负向② T1 64B 整拍仍 PASS 等），符合坑 #43"命中面精确"。

### 7.2 既有三回归（Lead 授权的最小端口补齐）
| TB | 参数 | 判据 | 结果 |
|---|---|---|---|
| `bridge_dma_tb` | 直例化 `axi4_master_bridge` HAS_DMA=1 | 双读引擎（现均为 DMA 路径）+ 写→读逐字节 | 见 §7.3 补丁说明；`=== BRIDGE_DMA_TB: PASS ===`（P1（engine=0，2 帧写→读回）PASS、P2（DMA 往返，wm=3/rd_frame=3/outstanding=0）PASS、P3（第二笔 DMA 读逐字节）PASS；`==== BRIDGE_DMA_TB: 0 errors ====`） |
| `mem_bridge_tb` | `frame_mem_if HAS_DMA=0` | 六用例 + 计数基线（R1 基线：rd_frame=585 / rd_beats=8202） | `PASS (0 errors)`（计数与 R1 基线逐字一致：wm=wr_frame=rd_frame=585、rd_beats=8202、4k_violation=0、axi_proto_err=0；wstrb full=7655/partial_tail=547/illegal=0） |
| `w4_joint_tb` | 两实例 HAS_DMA=0 | 正向 PASS + 负向 DEFECT_ROUTING=1 应 FAIL/DEADLOCK | `正向 PASS (0 errors)；负向 DEFECT_ROUTING=1 按设计 FAIL（DEADLOCK）`（A/B 各 wm=wr=rd=148、stall/ill/drop/bresp/len_err 全 0；defect 轮复现死锁（`[FAIL] DEADLOCK: A_ost=1 B_ost=0 mon_wb=2 mon_rb=0`）⇒ 判据非恒真） |

日志归档：`out/evidence_2026-10-17/R2_sim_<tb>_run.log`（含命令与原始输出）。

> `bridge_dma_tb` 的"S2MM 服务模型"补丁已按 §7.3 实施并复跑 PASS；三条回归日志均由本轮实跑产生（非历史日志复用），时间戳见各文件头。

### 7.3 TB 补丁（Lead 授权"只加 tie，不改用例语义"——**其中 1 处订正**）
1. `sim/mem_bridge_tb.sv` / `sim/w4_joint_tb.sv`（HAS_DMA=0）：`frame_mem_if` 实例补 12 根 B3-2 端口 tie（`dma_wr_go/ack=0`、`s2mm_introut=0`、`dma_wr_t*` 输出悬空、`dma_wr_tready=0`、`ro_dma_wr_*` 等悬空）。**纯 tie，用例语义 0 改动**。
2. `sim/bridge_dma_tb.sv`（直例化 HAS_DMA=1）：**仅补 tie 不够** —— 该 TB 原以"写 n 帧后 `stat_wm` 递增、再按键读回"为语义，而 R2 的 HAS_DMA=1 写路径已换 S2MM：tie `dma_wr_go=0` 会使每帧在 WAITGO 等满 56ms 看门狗后丢弃、`stat_wm` 不增 ⇒ 用例必然 FAIL（且每次 56ms 仿真）。故按 Lead 授权"补端口"的同时，**补一个最小 S2MM 写引擎服务模型**（~45 行：请求→翻 GO→按 TKEEP 把流写进 TB 的 ddr[]→拉 introut→桥 commit；清 IOC 在下次请求前），读路径与断言 0 改动。**这是对"只加 tie 即可跑"的订正**：R2 写路径的契约变化使 HAS_DMA=1 的直例化 TB 必须带服务模型。
   * 注：该模型只为回归恢复"写提交"语义；R2 写路径的正式判据在 `r2_wr_tb`。

### 7.4 覆盖缺口 / 已知局限（诚实清单）
| # | 缺口 | 影响 | 处置 |
|---|---|---|---|
| G1 | 厂商 IP 的 TKEEP→WSTRB、IOC 时刻、多 burst 未在离线仿真中实例化真实 IP | 字节等价/退休时刻结论只到 L1 | 板验 S4（含 86B 尾拍）/S5/S7 覆盖；A9 保留 L1 |
| G2 | `WD_STREAM`/`WD_PUSH` 看门狗分支未被离线触发（T9 只触发 WAITDONE） | 两分支结构存在但行为未仿真验证 | 代码审查 [L1]；建议后续加 TB 用例（deassert tready 后 force stall_cnt） |
| G3 | `S2MM LENGTH < 实际流字节`/`>流字节` 的失配行为未离线验证 | 失配场景（软核编程错误）后果未知 | 属软核 SW 契约；板验 DMASR 错误位 + stat_wr_timeout 可观测 |
| G4 | 软核写服务协议（`serve_write_once`/fault 恢复序列）本报告未审计 | A4 残余窗口的 SW 兜底未验 | Lead 稍后定稿后另审（已约） |
| G5 | 真实 MIG 的 B 响应时序/仲裁插入未模拟 | 吞吐/时延结论不适用 | 归 R3 速率归因 |
| G6 | 随机帧长仅覆盖 16 个边界长度 + 84 个随机长度（seed 固定可复现） | 长度覆盖非穷尽 | 板验 S7 四档 + 10MB 质量档覆盖 |

---

## 8. 与设计草案的冲突/遗漏（每条给具体修改建议）

| # | 设计草案处 | 问题 | 建议 |
|---|---|---|---|
| D1 | §4.3 表"D_WAITDONE 超时 2^25≈112ms" | 与冻结 RTL（`24'hFFFFFF`≈56ms，`:782`）不一致 | 文档改为 2^24≈56ms；并注明"统一 24 位看门狗" |
| D2 | §4.3 异常表未写 fail-stop/HALT/ACK 恢复 | 冻结 RTL 已加 `WD_HALT + dma_wr_ack + +0x4C`，设计未同步 | 设计补"超时 fail-stop + 软核恢复序列"章节（同 A4/A6），并写明 WAITGO 超时是"良性丢弃不 halt" |
| D3 | §4.1 只列 `DMA_WR_REQ(+0x40)`/`DMA_WR_DBG(+0x44)`/`WR_GO(+0x48)` | RTL 另有 `+0x4C SET_WRACK(opcode 0x06)`（A6） | 设计寄存器表补 `+0x4C`，并在 SW 契约写明恢复序列（DMACR 0x4→0x1001、清 IOC、翻 WRACK） |
| D4 | §6.1/6.2 把 TKEEP→WSTRB 写为"需离线 TB 与板验各证一次" | 实际离线 TB **无法**证厂商 IP 行为（A9/G1） | 措辞改为"离线只证 DUT 输出流；厂商 IP 行为由板验 S4 证"，避免把 TB PASS 误当 L2 字节等价 |
| D5 | §9.3"既有回归：bridge_dma_tb … 全 PASS（既有 TB 不动）" | **不成立**：HAS_DMA=1 直例化 TB 的写路径契约已变，仅加 tie 会 56ms×N 超时 FAIL | 设计 §9.3 注明"bridge_dma_tb 需补最小 S2MM 服务模型（本报告 §7.3）"，或改判据为 mem_bridge/w4_joint + r2_wr_tb |
| D6 | §11 K2"IOC 与 BRESP 不等价"缓解 | 已加 fail-stop，但 WAITGO 超时的陈旧 GO 窗口仍在 | 设计 §4.3 明确"软核翻 GO 前必须二次确认 pending&&toggle"（A4 建议） |
| D7 | §12 依据等级"离线 TB + 回归 + OOC synth 取得 L2" | 离线 TB 不能把 A9 提升到 L2 | 分级更新：字节等价/退休时刻保持 L1，板验后 L3 |
| D8 | 全文未提 `lat_w` 在桥① 失效 | B3-0 口径易误用 | 设计/记录加注（A11） |

---

## 9. 依据等级汇总与板验承接

| 结论 | 等级 | 依据 |
|---|---|---|
| A1 真阻塞缺陷与修复 | L2 | 代码级+遮蔽可编译实测+xelab/TB/回归；**未板证** |
| A2–A6 修复 | L2 | 冻结 RTL 代码核对 + r2_wr_tb T1–T9 + 回归 |
| 规则号 1 逐项等价 | L2 | 代码逐项对照 + TB 101 commits 判据 |
| HAS_DMA=0 未被误伤 | L2 | git diff 0 删除行 + mem_bridge/w4_joint 回归 |
| A7 CDC 域归属 | L1 | 厂商 VHDL + 代码核对（未上板测量） |
| A8 burst/DRE | L1 | 厂商 IP 元数据 |
| A9 TKEEP→WSTRB / IOC 退休时刻 | L1 | 厂商仿真源码两形态，未确证本配置，**待板验 S4→L3** |
| 仲裁器 S00 复用不破坏 W4 响应路由 | L1 | W4 既有修复结论 + 接线审查；板验 S5/S10 复核 |
| 离线 TB PASS / 负向对照 | L2 | 本报告 §7 原始日志 |

**板验必须承接的项**：S4（含尾拍 86B 单帧逐字节 + DMASR 错误位）、S5（4 帧计数）、S7（四档多长度）、S8（10MB 100%+SHA）、S10（双桥计数对账 + `stat_wr_timeout/buf_drop/fault` 全 0）、S2/S3（身份+WR_REQ 可读）。任一 FAIL 按 §6a 硬规则 3 措辞（判据未取得 ≠ 判据通过）。

---

## 附录 A：r2_wr_tb 用例与判据（冻结版端口假设）

| 用例 | 内容 | 主要判据 |
|---|---|---|
| T1 | 单帧 len=64（整拍） | S2MM 模型 SA/LEN/beats、full_bit、len_tab、64B 逐字节、tkeep=全1/tlast |
| T2 | 尾拍 len=70 | 尾拍 tkeep=0x3F、tlast、6B 尾字节、槽内 70B 逐字节、70..127 未被写 |
| T3 | 背靠背 3 帧（96/130/64） | 3 槽号递增、模型收到 3 笔按序、字节逐字节 |
| T4 | 满槽拒收 | 不提交、字节/full_bit/len_tab 未改、`stat_wr_stall+1`、**游标推进**（下一帧请求槽号=满槽+1） |
| T5 | 超长 1600B 拒收 | 不提交、`stat_len_err+1`、slot 不置满；len==0 在 frame_mem_if 层不可达（空帧不发描述符）说明 |
| T6 | GO 缺失（真实等 `24'hFFFFFF` ui 拍） | `stat_wr_timeout+1`、不提交、fault 保持 0、下一帧正常提交（不停泊） |
| T7 | GO 先于清 IOC | 桥必须停 WAITGO（`[FAIL-T7-GO-GATE]` 监视）、清 IOC 后提交、无重复提交 |
| T8 | 规则号 1 golden model 随机 100 帧（强制游标 220，含 256 回绕+满槽拒收） | 每 commit 槽号/SA/len/len_tab/full_bit/逐字节；总 cursor=320、commit/refusal/stall 计数闭合 |
| T9 | WAITDONE 看门狗 fail-stop + 软核 ACK 恢复 | `stat_wr_timeout+1`、HALT/fault 观测、fault 清 0、超时帧不提交、恢复后提交；**力加速时基已在 TB 内注明** |

## 附录 B：本轮交付物与证据文件

| 文件 | 说明 |
|---|---|
| `out/evidence_2026-10-17/R2_rtl_audit.md` | 本报告 |
| `sim/r2_wr_tb.sv` | 独立 TB（白盒，含 S2MM/软核行为模型 + golden model） |
| `sim/run_r2_wr_tb.bat` | 一键正/负向（CRLF、ASCII、清 xsim.dir、日志汇总 `sim/r2_wr_run.log`） |
| `sim/r2_neg_patch.py` | 负向缺陷副本生成（冻结 hash 校验 + 逐 patch 唯一命中断言） |
| `sim/r2_neg_cursor/`、`sim/r2_neg_tkeep/` | 缺陷副本（生成物） |
| `sim/r2_wr_pos.log`、`r2_wr_neg_cursor.log`、`r2_wr_neg_tkeep.log`、`r2_wr_run.log` | TB 原始日志 |
| `out/evidence_2026-10-17/R2_sim_{bridge_dma,mem_bridge,w4_joint}_run.log` | 三回归日志归档 |
| `out/evidence_2026-10-17/R2_tb_patch_notes.md` | TB 补丁 diff 说明（本报告 §7.3 的展开） |

> 本报告不含板上证据；板验结论由 Lead 的 R2 S0–S11 场次另行给出。

### 7.5 固件写服务只读审计（`sw/src_j3/main.c`，blob `ee256c05`，ELF `1bc8088d`，50,896 B）

> 范围：只读审计 Lead 定稿固件中与 R2 写服务相关的 5 处；**未修改固件**。结论等级限于代码级 [L1]（未上板）。

**7.5.1 IOC 清除与 arm 顺序（A4 兜底的兑现）** — `serve_write_once()` `main.c:306-353`
* 实测顺序与设计 §4.2/§4.3 一致：`S2MM_DMASR=W1C(IOC)`(:337) → `S2MM_SA=SLOT_BASE+slot*4KB`(:338) → **二次确认** `dread(&R_WRREQ)` 校验 `pending==1 && toggle==tog`（:342-348，不满足打印 `[B2] WRABORT stale req` 并**不启动不翻 GO**）→ `S2MM_LENGTH=len`(:349，写即启动) → 记录 `g_wr_last_toggle`(:350) → `R_WRGO=1`(:351)。
* 字段位与 RTL 镜像布局一致：`pending=bit31`、`toggle=bit24`、`slot=bits23:16`、`len=bits15:0`（对应 `frame_mem_if.v:90` 的 `{pending[31],6'b0,toggle[24],slot[23:16],len[15:0]}`）。✓
* **残余窗口 [L1]**：二次确认与 GO 之间仍有 µs 级 TOCTOU 窗口（Lite 两次总线事务），若桥的 56ms WAITGO 看门狗恰在此窗口内到期，仍可能出现"已 LENGTH 启动、桥已丢帧"的错配。概率 = µs/56ms 量级，但后果见 7.5.3，故仍建议板验 S10 把 `fault/stat_wr_timeout` 是否 0 作为硬判据。

**7.5.2 fault 恢复序列（与 RTL WD_HALT 配对）** — `main.c:310-319` + `s2mm_channel_init()` `:290-303`
* 触发：先读 `R_WRDBG`，`bit31==1` 即进入恢复（与 pending 解耦，符合"桥已停 pending、只等 ACK"的 WD_HALT 语义）✓。
* 序列：`S2MM_DMACR=RESET(0x4)` → 等 `DMASR.Halted==1`（有界 4e6 次）→ `DMACR=IOCEN|RS(0x1001)` → 等 `Halted==0` → `DMASR=W1C(IOC)` → `g_wr_last_toggle=0xFFFFFFFF`（强制下个请求必 arm）→ 返回后 `R_WRACK=1`（翻 ACK，桥 WD_HALT 唯一出口）→ `busy_ms(1)`。
* 与 RTL `axi4_master_bridge.v:811-822` 的出口条件（`dma_wr_ack` 翻转）严格配对；顺序（复位→清 IOC→翻 ACK）与 RTL 注释一致 ✓。`busy_ms(1)` 实测≈0.15ms（坑 #51 板标定），远大于 ACK 2FF 的 ns 级传播 ✓。
* **低风险 [L1]**：恢复后不校验 fault 是否已清，而是靠下一圈再次读到 fault 再重试（自愈循环），逻辑可接受；建议 S10 对 `fault` 终值硬判 0。
* **操作注记**：fault 只在 `g_dma_mode==1` 时被服务（`serve_any()` 开头即返回若 0）；若故障后用户先发 `'d'` 退出 DMA 模式，写路径会保持 HALT 直至再次 `'d'`。板验脚本应避免"故障后先切引擎"的次序。

**7.5.3 读/写服务先后与写饿死（Q3）**
* `serve_any()` `:356-365`：**读优先**（`+0x34` sticky bit25 置位先 `serve_dma_once()` 并 return），否则 `serve_write_once()`。
* 服务点覆盖：主空闲环 `:523-525`；J3 写阶段等待环 `:382-384`；J3 读阶段每槽轮询 `:405-411`；'E' 轮 `:647-658`/`:691-694`。
* 饿死分析：写阶段 `R_MODE=RND` 且无 `R_SLOT` 命令 ⇒ 不产生读请求，写不会被读抢 ✓；读阶段每个读请求服务完 sticky 落零，轮询环下一圈即服务写，且读阶段无 ping 等入向数据帧 ⇒ 正常无饿死（与 Lead 的 K6 判断一致）✓。
* **残余饿死路径 [L1]**：若某笔读请求因 MM2S 异常**长期 sticky 不落零**，`serve_any()` 每圈都先尝试读并 return ⇒ 写服务被无限期推迟（读服务内有界 guard 但 sticky 未必清）。板验若见 `WM_WR` 冻结而 `R_ENGINE=1`，应先怀疑该路径；建议 S10 同时记录 `stat_wr_timeout/buf_drop`。

**7.5.4 `'U'` 三行解析布局（Q4）**
* `[B2] U wreq:`（`:589-593`）与 `U wdbg:`（`:594-598`）各打印 **3 个** 32-bit 值（`w3 w2 w1`，背靠背 dread 双读顺序），`U s2sr:`（`:599-603`）打印 **2 个**（`s2`、`s1`）——判据脚本解析时注意行间值个数不同。
* 布局与 RTL 一致：`wreq={pending,6'b0,toggle,slot,len}`；`wdbg={fault,7'b0,last_alloc_slot,last_commit_len}`；`s2sr`=S2MM DMASR 原始值（bit0 Halted / bit1 Idle / bit12 IOC）。与 7.5.1 二次确认使用的位域**同源一致** ✓。
* 新增三行遵循"先读完再打印"（坑 #44）✓；旧行（id/req/wmrd/stat/arl/emit 等）为交错读打印，属既有仪器行为，非本轮引入。

**7.5.5 其他观察（低）**
* 长度防御 `len==0 || len>1538` → `[B2] WRBADLEN` + `R_WRACK=1` 让桥丢弃(:330-336)：与 RTL `wd_badlen_n` 的双重防御一致；但桥侧 `stat_len_err` 与软核该分支可能重复计数（桥在 WD_IDLE 已计入），板验对账时注意口径。
* `'d'` 进入 DMA 模式初始化 `s2mm_channel_init()` 并**对齐 toggle 基线**（有挂起请求时 `last ^= 1`，:555-565）✓；退出 `'d'` 不复位 S2MM/不清 GO——若有在途写请求会由桥 WAITGO 看门狗丢弃（≈56ms），属良性丢弃，但**会产生 1 帧丢失**（板验 S2/S3 身份段注意：发 `'d'` 前先等 `wmwr` 稳定）。

**7.5.6 固件审计结论**
* **Q1（IOC/arm/二次确认）**：✅ 已按 A4 建议兑现（含 TOCTOU 残余 µs 窗口，可接受）。
* **Q2（fault 恢复 ↔ WD_HALT）**：✅ 严格配对；建议板验把 fault 终值 0 作为硬判据。
* **Q3（读优先/写饿死）**：✅ 正常场次无饿死；残余路径仅在读请求长期不落零时出现（[L1]）。
* **Q4（`'U'` 布局/位域一致）**：✅ 与 RTL/二次确认同源一致；注意 wreq/wdbg 3 值、s2sr 2 值。
* 总体等级：**[L1]（代码级只读审计，未上板；无 L2 对照实验条件）**。固件写服务与 RTL 协议的字段/顺序/恢复配对**未发现阻塞性缺陷**；3 条残余风险（7.5.1 TOCTOU、7.5.3 读饿死、7.5.5 退出 `'d'` 丢 1 帧）均需板上 S10 计数面兜底。

> **只读声明**：本节仅阅读 `sw/src_j3/main.c`（blob `ee256c05`），未修改任何 `sw/` 文件；审计依据 = 该 blob + RTL 冻结 hash（5f8786…/96d5b1…），两者可复算。
> **脚本编码说明（对任务书"bat 带 BOM"的落实）**：`run_r2_wr_tb.bat` 采用 **ASCII-only 注释 + CRLF、无 BOM**。
> 理由：本仓库 9 个既有 `run_*.bat` 均为无 BOM；AGENTS.md #17/#18 的 BOM 要求针对 `.ps1`（PS 5.1 解析）；
> 给 `.bat` 加 UTF-8 BOM 会使 cmd.exe 把首行 `@echo off` 当命令名解析（实测报错），破坏一键复现。
> `r2_wr_tb.sv` / `r2_neg_patch.py` 为 UTF-8（含中文注释、无 BOM），xvlog/Python 均正常解析。
