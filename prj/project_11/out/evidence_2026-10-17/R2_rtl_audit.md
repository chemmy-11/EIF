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

---

## 11. R2 第二轮（时序修复 patch）复核 —— 发现并拦截"跨拍预取覆盖"功能回归

> 本轮对象：`rtl/axi4_master_bridge.v` 的 `g_wr_dma` 字节捕获 1 级流水（构建失败轮 WNS 修复）。
> hash 链：**round1 冻结 `5f878644…`（§1–§10 审计对象，TB PASS）** → **buggy round2 `740ab153…`（11:36 首版流水，TB 实测 FAIL）** → **fixed round2 `06e6bd72…`（Lead 采纳门控后重冻结，TB PASS）**。其余三文件 hash 全程不变（`96d5b136…` / `1885225f…` / `421df59c…`）。

### 11.0 结论（一句话）
**首版流水 patch（740ab153）存在阻塞性功能回归：每个非末拍 64B 边界丢 1 字节**（len≥66 的帧全部错位/无法完成）；我以"冻结版 TB FAIL + 机制对照 + 修复副本 PASS"三步定案 [L2]，Lead 采纳单门控修复后重冻结 `06e6bd72`；当前冻结版 **正型 PASS + 2 负向对照按设计 FAIL**，与第一场基线逐项一致（除每帧 +1 拍流水首拍，总计 +350.07 ns）。

### 11.1 patch 范围复核（只读 rtl/；[L2]）
* `git show HEAD:rtl/axi4_master_bridge.v`（HEAD=round1 冻结 `5f8786`）vs 工作区（fixed round2）：**diff 仅 95 行，全部落在 `g_wr_dma` 写路径**（新增 byte_q/byte_valid_q 声明、`wd_fill→wd_fetch`、WD_IDLE 清流水、WD_STREAM 消费/取字节重构 + 修复门控注释）。
* `g_wr_hw`（HAS_DMA=0 旧写 FSM）块：**HEAD 187 行 vs 工作区 187 行，逐字相同**；读 FSM 段（`// 4. read FSM`→`// 10.`）**14,927 B 逐字相同**；其余三文件 hash 不变 ⇒ 坑 #55 边界纪律满足。
* 负向 patch 文本锚点复核：游标锚（`wr_last_slot_r  <= wd_slot_next;` 后下一处 `wr_slot_ptr <= …+1`）仍唯一；TKEEP 锚正则 `wd_keep_r\[wd_bi\]\s*<=\s*1'b1;` 仍 1 命中 ⇒ 无需改动，`r2_neg_patch.py` 仅更新 `EXPECT_HASH` 为 `06e6bd72…`。

### 11.2 发现：跨拍预取覆盖（A16，阻塞；已修复）
**机制**（buggy 版 `740ab153`，[L2] 代码级+实测）：
* `wd_fetch = (wdst==WD_STREAM) && !wf_empty && ((wd_rxc + (byte_valid_q?1:0)) < wd_len)`（buggy :608-609）**缺少"流水槽本拍末将空出"门控**。
* 拍 N（offset 63 消费、`wd_bi==63`→`wd_beat_full<=1`）：同拍 `wd_fetch` 为真 → 把**下一拍首字节 offset 64** 取入 `byte_q`（跨拍预取，正确）。
* 拍 N+1（`wd_beat_full=1` 保持拍）：consume 被 `byte_valid_q && !wd_beat_full` 正确拦住（offset64 仍在 `byte_q`）；**但 `wd_fetch` 此时仍为真**（`(64+1)<len`）→ 把 offset 65 再取入 `byte_q`，**覆盖未消费的 offset 64**。
* ⇒ 每个非末拍丢 1 字节；`wd_rxc` 永远到不了 `wd_len` ⇒ **尾拍 TKEEP/TLAST 判据永不成立** ⇒ 该帧 56ms STREAM 看门狗后进 HALT（不提交）。len≤65 的帧不受影响（无跨拍预取），与实测一致。
**实测证据**（冻结 buggy 版 740ab153 + 独立 TB，FAST 省 T6；日志 `R2_sim_r2_wr_tb_round2_frozenFail_run.log`）：
* T1 len=64：PASS（单拍，无跨拍预取 —— 机制对照）；
* T2 len=70：**未提交**（`[FAIL-TIMEOUT] commit target=2 got=1`）→ 丢字节→尾拍不完成→HALT；
* T3 背靠背（96/130/64）：idx=1 len=70 **自 k=64 起逐字节错位** `got[k]=exp[k+1]`（k=64 exp=0xde got=0xc3；k=65 exp=0xc3 got=0xe4…），idx=2 整帧错位。
**修复（Lead 采纳，已进 06e6bd72）**：`wd_fetch` 增加 `&& !wd_beat_full`（冻结版 `:611`）——保持拍不再 fetch；正常连续流**无吞吐损失**（beat 完成拍 `wd_beat_full` 旧值=0，仍可预取下一拍首字节；PUSH 后首拍即消费预取字节）。
**修复验证**（`sim/r2_fix_check/` 副本 = 我提交给 Lead 的单门控修复，非 rtl/）：完整非 FAST TB（含 T6 真实 16.7M 拍）**PASS 0 errors**（`R2_sim_r2_wr_tb_round2_fixcheckFull_run.log`），T2/T3/T8 逐字节全对；同一副本上 2 负向对照仍按设计 FAIL（`…fixcheck_neg_cursor/_neg_tkeep`）。

### 11.3 功能等价复核五项（对 fixed `06e6bd72`；[L2] = 机制+TB 对照，[L1] = 仅推理）
1. **拍边界预取**：✅ 修复后严格正确——末字节消费当拍（`wd_beat_full` 旧值=0）预取下一拍首字节；保持拍禁取；PUSH 后下一拍 lane0 消费预取字节（T2/T3/T8 逐字节通过即证）。[L2]
2. **帧尾**：✅ 预取计数 `rxc+(valid?1:0) < wd_len` 严格不越过帧长（不预取下一帧）；`(wd_bi==63)||((wd_rxc+1)==wd_len)` 与旧版逐位一致；keep 仅在消费有效字节时置位、每拍后清 0 ⇒ 尾拍 TKEEP=len%64（T2=6 lane、T8 16 个边界长度全过）。[L2]
3. **超时/拒收/恢复**：✅ WAITGO→DRAIN 与流水无关（DRAIN 直接抽 FIFO）；STREAM 看门狗条件改为"既无 fetch 又无 consume"（保持拍会 +1 计数随后被 PUSH 清零，无害）；IDLE 每拍清 `byte_valid_q` ⇒ ACK 恢复/拒收后无残留（T4/T5/T9 通过）。[L2]
   * 残留说明：STREAM/PUSH 中途 HALT 时 `byte_q` 里已出 FIFO 未消费的 1 字节会在 IDLE 清除（该帧整帧本就丢弃，可接受）；帧剩余字节仍留 FIFO 属**既有缺口 G2**（旧版同病，非本轮引入）。
4. **吞吐**：✅ 稳态 1 B/cycle（消费与取字节同拍并行）；帧完成**拍数**不变（TB 逐帧 `beats==ceil(len/64)` 全过）；每帧多 1 拍 STREAM 入口填流水（总仿真时间 round1→round2 差 +350.07 ns，见 11.4）。[L2]
5. **不改 rtl/**：✅ 本轮我未写 `rtl/`；修复由 Lead 落地（hash `06e6bd72`），我的验证副本在 `sim/r2_fix_check/`。[L2]

### 11.4 冻结版（06e6bd72）TB 与负向结果 + 与第一场基线差异
**正型**（完整非 FAST，含 T6 真实等待；`R2_sim_r2_wr_tb_round2_pos_run.log`）：
* `=== R2 WR TB: PASS (0 errors) ===`，commits=101 / exp=101 / wm=101；
* T6：`ui_cycles=16777221`、`sim_time=55935252000 ps`（≈55.94ms）——与 round1 **逐字相同**；
* T8：cursor=320、cmt_total=100、refused=10、stall=11——与 round1 **完全一致**；
* T9：timeout=2、HALT/fault/ACK 恢复+恢复后提交 OK。
**负向对照**（`-d R2_FAST -d R2_NEG_*` 早停；判据不变）：
* ①游标被拒不推进 → `FAIL (2 errors) [NEG-CURSOR early stop]` 且 `[FAIL-T4-CURSOR]`（请求槽号+提交超时指认）；
* ②尾拍 TKEEP 满 lane → `FAIL (1 errors) [NEG-TKEEP early stop]` 且 `[FAIL-KEEP-MASK] sa=0x00101000 beat=1 off=64 exp=0x…3f got=0xffff…ffff`；
* 套件：`=== R2 WR TB SUITE: PASS (positive PASS + 2 negative controls FAIL as designed) ===`（exit 0）。
**与第一场基线（round1 5f8786）差异**：commit 数、每帧 beats、T6/T8/T9 计数全部逐字一致；唯一差异 = 总仿真结束时间 `56,683,676,135 ps` vs round1 `56,683,326,065 ps`，**差 +350.07 ns ≈ 105 ui 拍**，与"101 个提交帧 + 少量丢弃帧各多 1 拍流水首拍"的理论量级吻合（每帧 +1 拍，不影响功能/带宽判据）。**无功能差异证据**。

### 11.5 遗留风险/板验承接（本轮不新增）
* A9（TKEEP→WSTRB / IOC 退休时刻）仍 [L1]，必须板验 S4（尾拍 86B）→L3；
* G2（STREAM/PUSH 中途 HALT 的 FIFO 残字节）、WAITGO 超时 TOCTOU（固件已二次确认）维持原判；
* 新建构的 ILA 探针表（`r2_ilacap.tcl` 属 Lead 文件，我不越权修改）：**请把新 ltx 的 probes 发我/告知路径，我按冻结 RTL 信号名逐项对齐并出探针核对表**（新加 `wd_fetch/byte_valid_q/byte_q` 建议进 ui 域 ILA，控制位宽防坑 #47）。

### 11.6 本轮证据文件（全部在 `out/evidence_2026-10-17/`）
| 文件 | 内容 |
|---|---|
| `R2_sim_r2_wr_tb_round2_pos_run.log` | 冻结版 06e6bd72 完整正型 PASS |
| `R2_sim_r2_wr_tb_round2_neg_cursor_run.log` / `…_neg_tkeep_run.log` | 2 负向对照 FAIL+判据行 |
| `R2_sim_r2_wr_tb_round2_suite_run.log` | 一键套件汇总（SUITE PASS） |
| `R2_sim_r2_wr_tb_round2_frozenFail_run.log` | **buggy 740ab153 的拦截证据**（T2 未提交、T3 k=64 起错位） |
| `R2_sim_r2_wr_tb_round2_fixcheckFull_run.log` | 修复副本完整 PASS（修复验证） |
| `R2_sim_r2_wr_tb_round2_fixcheck_neg_{cursor,tkeep}_run.log` | 修复副本上负向仍按设计 FAIL |
| `R2_probe_map.md` | 探针↔RTL 信号↔域↔位宽 纸面核对表（ILA0 374→376 / ILA3 179→184）+ 新 ltx 核对清单 + 不可观测项（`stat_wr_timeout`） |

---

## 12. round2b 构建策略：ILA 探针裁剪复核（**RTL 不变，TB 无需重跑**）

> 背景：round2 综合已过，但 place/route 首掷 `ExtraTimingOpt` 布后 WNS −0.147 → 尾判 **−0.135**（WHS +0.004）；失败轮 worst 路径族扩散（`gray→FSM state CE`：桥② 读/写状态、`u_mem2` 的 `pre_eff/r_len` 等 + 新写引擎 lane CE），route 占 57–77%，`AggressiveExplore` 布局失败 ⇒ Lead 判断主因为**拥塞/资源密度**（[L1]，Lead 归因；本报告只记录裁剪事实与其可核对影响）。
> 决策：**不改 RTL**（仍冻结 `06e6bd72…`），只裁 ILA 探针集 → 重综合重掷。

### 12.1 事实：裁剪后的探针集（来自 12:49:08 的 `build_synth_only.tcl` / `build_debug.tcl`，两文件 ILA 段逐行一致）
| ILA/probe | 原（round2） | **现在（round2b）** | 保留/移除明细（脚本行号） |
|---|---|---|---|
| `u_ila_0/probe0` @user_clk | 376 bit | **92 bit** | 保留：`dbg_mem_u_wr/u_rd/u_drop`(16×3)+`dbg_mem_rden`(1)+`dbg_mem_ost_s`(9)+`dbg_mem2_u_wr/u_rd`(16×2)+**`dbg_s2mm_reqpend`+`dbg_wr_fault`**（:89-98）；其余 user 域探针（rx/up/pk/prev/ch/cmd/lite 等）全部移除 |
| `u_ila_0/probe1` @user_clk | 9 bit | **9 bit（不变）** | `dbg_mem_rden` + `mem_rd_data[7:0]`（:100-107，S8c 发射字节流证据保留） |
| `u_ila_1` @eth_rxc | 111 bit | **整核移除** | :109（仅注释） |
| `u_ila_2` @user_clk_b | 101 bit | **整核移除** | :111（仅注释） |
| `u_ila_3/probe0` @ui_clk | 184 bit | **152 bit** | 保留 `dbg_calib`+`mem wm/wr_frm/rd_frm/stall/len_err/ost`+`mem2 wm/wr_frm/rd_frm/ost`+**`dbg_s2mm_state[2:0]/tvalid/tready`**（:132-157）；drop `dbg_mem_bresp`(:139 注释)、`dbg_mem_wslot/rslot`(:141 注释) |

* 位偏移（纸面，[L2]，详见 `out/evidence_2026-10-17/R2_probe_map.md`）：ILA0 probe0 新位 **90=`dbg_s2mm_reqpend`、91=`dbg_wr_fault`**；ILA3 probe0 新位 **149:147=`dbg_s2mm_state[2:0]`、150=`tvalid`、151=`tready`**。
* 资源收益纸面：ILA0 −284 bit、ILA3 −32 bit、ILA1+ILA2 两整核（−212 bit + 2 套核/触发/时钟负载）。**裁 ILA ≠ 时序保证**，收敛以新一轮 place/route 实测为准。

### 12.2 对 R2 判据口径的影响（[L2] 纸面逐条对 DESIGN §10）
1. **S10 的 bresp 项不可观测（A18，需改判据措辞）**：DESIGN §10（`out/R2_S2MM_DESIGN.md:167`）要求"错误计数（bresp/len_err/stall 按语义）为 0"，但 `dbg_mem_bresp` 已从 ILA3 移除 ⇒ **bridge② 的 bresp_err 不可观测**（桥① 在 S2MM 下 bresp 本就不可见/无意义）。⇒ S10 改为："`len_err/stall`（及 wm/wr_frm/rd_frm/ost 对账）按语义为 0；**bresp 项改 INFO/判据未取得**"，不得写"错误计数全 0"（§6a 硬规则 3：判据未取得 ≠ 判据通过）。
   * **交叉核对（独立读 Lead 工具，[L2]）**：`out/r2_counter_recon.py` 已按同一口径实现——bresp/wslot/rslot 归为 INFO/NOT_OBTAINED（该文件 :20-24 / :107-110 / :112-114）、错误硬判 = `len_err/stall`(桥①) + `dbg_wr_fault`；`out/r2_ilacap.tcl` :50-67 亦声明 ILA0 374→92 / ILA3 184→152 与期望探针宽度。⇒ **判据工具无需改**，仅需订正 DESIGN 两处文档（§10 S10 的 bresp 措辞、§11 K1 的 ILA1→ILA0 probe1）。
2. **S6/S10 其余项保留**：桥② `rd_frm`（ping +4）、`ost=0`、桥① `wm/wr_frm/rd_frm/ost`、`len_err/stall` 均在新 ILA3 列表内 ✓。
3. **S8c 发射字节流**：ILA0 probe1 9 bit 保留 ✓（不受影响）。
4. **ILA1/ILA2 移除**：逐条核对 R2 S0–S11 **未引用**（S2/S3 用 'U'/ping/NIC；S6/S10 用 ILA3；S8c 用 ILA0 probe1）⇒ 判据无影响；但 R2 板场次失去 eth 域/B 域交叉观测，若 S4/S5 出物理层疑点需回烧 R1 位流或临时加 ILA（记入板验风险备注）。
5. **文档订正（D9）**：DESIGN §11 K1（同文件 :177）缓解措施写"必要时用 **ILA1 probe1** 抓槽读回字节"——ILA1 本轮已移除，且"发射字节流"探针实为 **ILA0 probe1**（:100-107）⇒ 该处应更正为 ILA0 probe1。
6. `dbg_wr_timeout` 仍不可观测（A17 维持）：`stat_wr_timeout` 无 ILA/无 Lite 读回；板验替代口径=`dbg_wr_fault`+`state==6(HALT)`+`WM_WR` 停滞。

### 12.3 其他影响
* **RTL 未变**（`06e6bd72…`，其余三文件 hash 亦未变）⇒ 独立 TB `r2_wr_tb` 无需重跑（其 DUT 只例化 `frame_mem_if`，不含 ILA；hash 守卫仍匹配）。最近一次 suite（11:42，RTL=06e6bd72）`SUITE: PASS` 仍有效。
* 本轮改动在 `scripts/`（Lead 拥有），我不写；纸面核对表已按新口径更新：`R2_probe_map.md`（round2b 版，ILA0 92/probe1 9/ILA3 152，ILA1/2 移除，§5 新 ltx 核对清单保留）。
* **若本轮 sweep 仍不过门限**（[L1] 候选，Lead 决策）：在 RTL 冻结前提下还可 (a) 继续裁 ILA3 桥②组 `dbg_mem2_wm/wr_frm/rd_frm/ost`（57 bit，S6/S10 需要 → 需先给替代判据）；(b) ILA 深度 2048→1024/512（省 BRAM/布线）；(c) 与 ILA 无关的结构性手段属 RTL 改动，不在本轮策略内。任何进一步裁剪都会扩大"判据未取得"清单，建议每裁一项同步更新 S 判据表。

---

## 13. round2c 时序修复（新增 `WD_ARM=7`，新 blob `f43267db…`）复核

> round2b（裁 ILA）首掷仍 WNS −0.127/WHS +0.003；Lead 用 post-route dcp 逐级路径把根因定位到代码级 [L2 来源：Lead 的 `path_dbg.rpt` 逐级路径报告]：
> `u_mem/u_wr_bytes/wr_gray_s2_reg[7]` → gray2bin → `rd_level_carry`(3×CARRY8) → `ub_rl[9]` → `wdst[2]` 次态 → LUT6 → `g_wr_dma.wd_data_r_reg[410]/CE`。
> 机制：`WD_WAITGO` 完成条件 `wf_level >= wd_len[12:0]`（12b 比较）**同时**驱动"进入 STREAM 当拍清 512 位 `wd_data_r/wd_keep_r`"的使能 ⇒ level 比较锥进入 512 CE（30/30 最差路径同族）。
> 修法：新增 **`WD_ARM=3'd7`** 一拍（保留 `WD_HALT=6` 编码不变）：WAITGO 完成只置 `wdst<=WD_ARM`；ARM 拍由状态译码清拼帧寄存器后进 STREAM。
> **我未改 `rtl/`**；本节为独立复核。新 blob 实测 `git hash-object` = **`f43267db82b84305cfeb519adcfa76f79443f6b3`**（与 Lead 通知一致），其余三文件 hash 未变。

### 13.1 patch 范围（可复核）
* 基线重建（审计方法）：用上一轮 suite 生成的 `sim/r2_neg_cursor/axi4_master_bridge.v`（= `06e6bd72` + 已知 1 行游标缺陷）**回退该已知缺陷**重建 `06e6bd72` 原文，`git hash-object` = `06e6bd72…` 逐字命中 ⇒ 基线可信。
* `06e6bd72` → `f43267db` 全量 diff = **60 行**，只涉及：`localparam` 加 `WD_ARM=3'd7` + 注释；`WD_WAITGO` 完成分支由"7 个清零赋值 + wdst<=STREAM"改为"wdst<=WD_ARM"；新增 `WD_ARM` 状态块（清 7+1 个寄存器后 `wdst<=WD_STREAM`）。**无其他改动**（ARM 块之外 0 删除/新增行）⇒ 与 Lead 描述一致。patch 原文归档：`out/evidence_2026-10-17/R2_round2c_patch.diff`。

### 13.2 功能等价性复核（逐项，[L2] = 代码级+TB 对照；[L1] = 仅推理）

1. **ARM 清零集合是否覆盖 WAITGO 原有全部清零项** — ✅ **完全覆盖**：
   旧 `06e6bd72` WAITGO 完成拍清：`wd_beat, wd_bi, wd_rxc, wd_beat_full, wd_data_r, wd_keep_r, wd_stall_cnt`（7 项）+ `wdst` 转换；
   新 `WD_ARM` 清上述 7 项 + `byte_valid_q`（第 8 项）。`byte_valid_q` 原本在 `WD_IDLE` 每拍清、进入 WAITGO 时已为 0 ⇒ ARM 再清是**冗余但安全**（防未来路径残留），无遗漏项。其余帧起始量（`wd_slot/wd_len/wd_beats/wd_pop/…`）原本就在 `WD_IDLE` 弹描述符时初始化，不属于 WAITGO 转换职责，未被改动。**逐项对照通过。**
2. **+1 拍是否改变对外协议时序** — ✅ **无协议变化，只有设计内延迟**：
   `m_axis_s2mm_tvalid = (wdst==WD_PUSH)` ⇒ WAITGO/ARM 期间流不 valid；`tdata/tkeep` 在进入 STREAM 前已清（ARM 拍末清零），STREAM 首拍行为与原版一致（ARM 清除 `byte_valid_q`，STREAM 首拍先 fetch 再消费，与此前 WAITGO 后首拍相同）；`pending/toggle/s2mm_introut/commit` 协议完全不变。**每帧 +1 个 ui 拍（≈3.33ns）延迟**，无时序/握手/顺序改变。
3. **HALT/超时/恢复路径是否经过 ARM 产生副作用** — ✅ **不经过**：
   WAITGO 超时仍直接 `wdst<=WD_DRAIN`（不进 ARM，保持"GO 缺失=良性丢帧不 halt"语义）；STREAM/PUSH/WAITDONE 看门狗仍进 `WD_HALT(6)`；HALT 出口仍为 `dma_wr_ack` 翻转→清 fault→IDLE。ARM 只能由 `wd_go_ok && wf_level>=wd_len && !s2mm_introut` 成功条件进入 ⇒ 与所有故障路径结构隔离，无副作用。
4. **state=7 是否与现有 TB/探针断言冲突** — ✅ **无冲突**：
   TB `r2_wr_tb.sv` 不含任何"wdst/ro_dbg_wr_state 只能是 0..6"的断言；它只判 `ro_dbg_wr_state==3'd4`(T9 等 WAITDONE)、`==3'd6`(T9 HALT-latch)、以及 T7 闸门对 `2/3` 的监视，`7=ARM` 仅瞬态 1 拍/帧不会被误判。探针/板验工具：`out/r2_counter_recon.py` 对未知状态值只作 INFO 打印（不参与硬判，其代码注释"未知值原样返回 ?<v>。仅用于 INFO 打印"）⇒ 板验工具安全；`R2_probe_map.md` 已更新 `dbg_s2mm_state` 解码为 **7=ARM 瞬态（板验忽略）**。
   **建议（Lead 文件，非阻塞）**：若希望 ltx 抓到的 ARM 拍不打印 `?7`，可把 7 加入 `r2_counter_recon.py` 的状态解码表；不加也不影响 PASS/FAIL。
5. **对带宽/帧完成拍数** — ✅ 与设计一致：+1 拍/帧（`dbg_wr_cycles` 亦 +1/帧，仅观测）；1538B 帧占约 25 拍 stream + 软件服务 µs 级 ⇒ 带宽影响 <0.1%，R2 吞吐本就服务延迟主导（R3 归因）。

### 13.3 冻结版（f43267db）TB 与负向结果
* **正型（完整非 FAST，含 T6 真实 16.7M 拍）**：`=== R2 WR TB: PASS (0 errors) ===`，commits=101/exp=101/wm=101；
  * T6：`ui_cycles=16777221`（与上一基线**逐字相同**）、`sim_time=55935253000 ps`（上一基线 55935252000 ps；**ui 周期数一致**，1ns 差为 TB 采样粒度，无语义差异）；
  * T7：`done cmt=10 timeout=1`（无重复提交）；T8：cursor=320 / cmt_total=100 / refused=10 / stall=11（与上一基线逐字相同）；T9：timeout=2、HALT/fault/恢复+恢复后提交 OK。
* **2 负向对照**（`-d R2_FAST -d R2_NEG_*` 早停，判据不变）：
  * ①游标被拒不推进 → `FAIL (2 errors) [NEG-CURSOR early stop]`，判据行 `[FAIL-T4-CURSOR]`；
  * ②尾拍 TKEEP 满 64 → `FAIL (1 errors) [NEG-TKEEP early stop]`，判据行 `[FAIL-KEEP-MASK] sa=0x00101000 beat=1 off=64 exp=0x…3f got=0xffff…ffff`。
  * 套件：`=== R2 WR TB SUITE: PASS (positive PASS + 2 negative controls FAIL as designed) ===`（exit 0）。
* 负向 patch 文本锚点在新 blob 上仍唯一（游标锚/`wd_keep_r[wd_bi]<=1'b1` 锚各 1 命中），`r2_neg_patch.py` 的 `EXPECT_HASH` 已更新为 `f43267db…`（守卫在 RTL 变化时会硬失败）。
* 日志归档：`R2_sim_r2_wr_tb_round2c_{pos,neg_cursor,neg_tkeep,suite}_run.log`。

### 13.4 与上一冻结基线（06e6bd72）差异
| 指标 | 06e6bd72（round2 修复版） | **f43267db（round2c）** | 判定 |
|---|---|---|---|
| commits / exp / wm | 101 / 101 / 101 | **101 / 101 / 101** | 一致 |
| T6 WAITGO 看门狗 ui 周期 | 16,777,221 | **16,777,221** | 一致 |
| T8 cursor / refused / stall | 320 / 10 / 11 | **320 / 10 / 11** | 一致 |
| T9 timeout / HALT 恢复 | 2 / OK | **2 / OK** | 一致 |
| TB 总仿真结束时间 | 56,683,676,135 ps | **56,684,046,209 ps** | **+370,074 ps ≈ +111.0 个 ui 拍** |
| 帧完成拍数 | 基线 | **+1 拍/帧**（ARM） | 设计内延迟 |

**+111 拍的解释（[L2] 实测+推理）**：ARM 进入次数 = 有流帧数 = 101 提交 + 1 例 T9 "流已发/intr 被扣"帧 = **102**（理论 +340.0ns）；实测 +370.07ns，多出 ≈9 拍，来源为 TB 喂帧相位与 STREAM 等字节时序的耦合抖动（TB 侧时序，非 RTL 语义；commit 数/TKEEP/beat 数/看门狗周期全部不变可佐证）。**结论：功能等价，仅设计内 +1 拍/帧延迟。**

### 13.5 结论
* `f43267db` 的 `WD_ARM` 修法**语义等价**（清零集合完整覆盖、故障路径结构隔离、对外协议不变、state=7 瞬态与现有 TB/板验工具不冲突）[L2]。
* 独立 TB：**正型 PASS + 2 负向对照按设计 FAIL**；差异仅为设计的 +1 拍/帧延迟。[L2]
* **TB 绿灯，可由 Lead 交板验**。板验注意：`dbg_s2mm_state` 若抓到 **7=ARM 属正常瞬态**（不判故障）；`6=HALT` 才是 fail-stop。

---

## 14. 构建产物实物核对（位流 `28921C6B…` + ltx `4AC25546…`）

> 对象：`out/archive/b31b_r2_2026-10-18/`；对应冻结 RTL **`06e6bd72`→ round2c `f43267db…`**（详见 §13）。本节只写可复算事实。

### 14.1 文件/哈希核对（[L2] 直证）
| 项 | 实测 | 与 Lead 通知 |
|---|---|---|
| `aurora_mem_bridge_r2_28921C6B.bit` | 10,266,180 B，SHA256 `28921C6B38BE92447950B8C81405F278945529BB007E94461EC2CEEF0D324627` | ✅ 一致 |
| `probes_r2_28921C6B.ltx` | 64,593 B，SHA256 `4AC2554667F94BC3E052E0A652FF2DE322E2CE51FEE2B47399A108DF9E6B7C33` | ✅ 一致 |
| 别名/ canonical | `aurora_mem_bridge_r2.bit`、`out/aurora_mem_bridge.bit` 与上述 bit **同 hash**；`probes_r2.ltx` 与上述 ltx 同 hash | ✅ |
| **bit↔RTL 绑定** | 归档 `rtl_axi4_master_bridge.v` `git hash-object` = `f43267db82b84305cfeb519adcfa76f79443f6b3`；另三文件 = `96d5b136…/1885225f…/421df59c…` | ✅ 与冻结 blob 逐一一致 |
| 归档清单 `SHA256.txt` | 21 条文件行逐条复算 **21/21 OK** | ✅（但见 A19） |

### 14.2 构建日志独立复核（不采信摘要，直接读 log/rpt）
* `build_r2_sweep2_console.log` 尾判：**`V5_SWEEP2_OK: directive=ExtraTimingOpt wns=0.004 whs=0.004 bit=…`**（与 Lead 通知一致）。
* `rpt2_ExtraTimingOpt.timing_summary.rpt`：**`All user specified timing constraints are met.`**；汇总 WNS=**0.042**、WHS=**0.004**（后布）。Lead 表述"后布 +0.042 → 尾判 +0.004"与两份来源一致（尾判值取 sweep 门限 marker）。
* DRC：**0 Errors / 22 Warnings**（`INFO: [Vivado 12-3199]`），warning 均为 dbg_hub/BRAM advisory 等已知类；`write_bitstream completed successfully`。
* ⇒ 构建产物与"过门限"声明 **独立复核成立 [L2]**。

### 14.3 ltx 探针逐项核对（对应 `R2_probe_map.md §5/§5.1`）
* **全部期望项通过**：仅 2 个 ILA 核（`u_ila_0`/`u_ila_3`）；ILA0 probe0=**92**（位序逐条一致）、probe1=**9**；ILA3 probe0=**152**（位序逐条一致）；末 5 bit=`state[2:0]`/`tvalid`/`tready` 且 state subnets=`[2],[1],[0]`；`dbg_mem_bresp/wslot/rslot`（及历史未挂 ill/nofrm/wbeats/rbeats）**均不出现**。
* **非阻塞事实 1（命名）**：ILA0 probe0 bit48 的实际 net 名为 **`dbg_mem_rden_1`**（`dbg_mem_rden` 同时挂 probe0 与 probe1，Vivado 自动加 `_1`）；功能同源；若离线解析按精确名匹配 probe0 列需兼容 `_1`（当前 recon 未用该列）。
* **非阻塞事实 2（时钟）**：ltx 不记录 ILA 时钟网名（全文仅 `dbg_hub.clk_input_freq_hz=74999998`；`user_clk/ui_clk/clock` 字串 0 次）⇒ **ltx 无法直证 ILA0@user/ILA3@ui 的时钟关联**。旁证链：build 脚本 :81-83（ILA0 clk←`user_clk`）/ :124-130（ILA3 clk←`ui_clk`）+ RTL 域归属逐信号核对（ILA0 全 user 域、ILA3 全 ui 域）⇒ 语义可用；**板端时钟关联建议在 S0/S3 用 hw_manager `get_hw_ilas` 侧确认一次**（一次性，不影响探针数据解读）。

### 14.4 新发现：归档清单 `SHA256.txt` 头部 RTL blob 陈述过期（A19，[L2] 直证；建议修正）
* 文件头写："RTL 冻结: axi4_master_bridge.v blob **`06e6bd72…`**；其余三文件同 round1"；生成时间 14:45:09。
* 但归档 `rtl_axi4_master_bridge.v` 实际 hash = **`f43267db…`**（round2c），且 manifest 该文件行 SHA256 `B64300B4…` 与**实际 round2c 文件**一致（21/21 行复算无误）。
* ⇒ **仅头部文字陈述过期**（归档脚本模板未按 round2c 更新），文件级哈希链是自洽的。**建议 Lead 修正 `SHA256.txt` 头部（或归档脚本模板）后再"钉 hash"**，否则后续板验记录/审计引用 manifest 头会与位流 RTL 配对矛盾。属**文档溯源缺陷，不影响位流功能**，但在板验归档前修掉最稳妥。
* 同类检查：若 `out/r2_archive_round2.py` 等归档脚本内硬编码旧 blob，建议一并改为"从 `git hash-object rtl/…` 现算写入"（避免下次换版再漂移）。

### 14.5 结论
* 位流/ltx/归档 RTL 三者哈希链**自洽且与冻结 RTL 配对** [L2]；构建过门限声明经日志独立复核成立 [L2]。
* ltx 探针布局与 `R2_probe_map.md` 期望**逐项一致**（含裁剪项缺失验证）；`R2_probe_map.md` 的 `[待核对]` 已升级为**实物直证**，仅"时钟网名"留 `[待上板 hw_manager 确认]`（非判据项）。
* **可交板验**；唯一建议先修的文档项 = A19（`SHA256.txt` 头部过期 blob），不阻塞上板。

---

## 15. round2d：`axi_lite_regs` AXI 握手修复合入 + TB 冻结 hash 体系说明

> 依据：Lead 2026-10-18 17:0x 通知（已合入我在 `R2_rtl_audit §13`/分析文件 `R2_rtl_lite_regs_wedge_analysis_20261018.md §0` 给出的 `R2_axi_lite_regs_fix.v`）。本节记录**可核对的 blob/守卫事实**与**新 bit/ltx 核对顺序**，不含板验结论（板证待新位流）。

### 15.1 blob 事实（本机实测 `git hash-object`）
| 文件 | 旧冻结（round2c，bit 28921C6B） | **round2d 现状** | 变化 |
|---|---|---|---|
| `rtl/axi4_master_bridge.v` | `f43267db…` | `f43267db82b84305cfeb519adcfa76f79443f6b3` | 不变 |
| `rtl/frame_mem_if.v` | `96d5b136…` | `96d5b136305e81ee9d4cc716e60c5034581d027d` | 不变 |
| `rtl/aurora_mem_bridge.v` | `1885225f…` | `1885225ffac800c71187aa428f3d4908f7e3f975` | 不变 |
| `rtl/axi_lite_regs.v` | `421df59c…` | **`d133b508f80480bb8fa70a7f4a7953a07d8cb230`** | **= 我的 fix 副本 blob（逐字一致）** |
* 交叉验证：`git hash-object out/evidence_2026-10-18/R2_axi_lite_regs_fix.v` = `d133b508…`（与合并后 `rtl/` 完全相同）⇒ **合入无额外改动** [L2]。
* 固件候选终版：ELF **`f8cf4022`**（50,920 B；`dread` 保留 3 读作板验期防御、去掉 1ms 限速）。位流/ltx 待重建。

### 15.2 TB 冻结 hash 体系（现状 + 本轮更新）
1. **`sim/r2_neg_patch.py`（唯一的 hash 守卫处）**：
   * 原有：`EXPECT_HASH = f43267db…`，对象 `rtl/axi4_master_bridge.v`，不符即 **FATAL 拒绝生成缺陷副本**；
   * **本轮新增**：`EXPECT_FMI_HASH = 96d5b136…`，对象 `rtl/frame_mem_if.v`（TB 的 DUT 例化 fmi；fmi 变化同样改变仿真语义）→ 同样 FATAL；suite 日志现在打印 4 行（bridge/fmi 各 frozen+expected）。
2. **`sim/r2_wr_tb.sv` / `run_r2_wr_tb.bat`：不含任何 hash 常量**（grep 已核；verdict 字符串里的 "expected" 不是 hash 校验）⇒ 守卫集中在 patch 脚本，单点可审计。
3. **TB 的编译依赖**（bat 的 xvlog 列表）：`async_fifo.v`、`dma_rd_shim_v2.v`、`axi4_master_bridge.v`、`frame_mem_if.v`、`r2_wr_tb.sv` ——**不含 `axi_lite_regs.v`、不含顶层 `aurora_mem_bridge.v`**。
4. ⇒ **round2d 的 lite_regs 合入不改变 TB 编译/仿真语义**；bridge/fmi 未变 ⇒ 正型/2 负向判据不变、suite 可原样复跑。已按新守卫复跑一次：**正型 PASS + 2 负向按设计 FAIL + SUITE PASS**（日志 `R2_sim_r2_wr_tb_round2d_*`，见 §15.4）。
5. **更新规则（以后冻结变更时）**：
   * bridge 或 fmi 变 → 更新 `EXPECT_HASH`/`EXPECT_FMI_HASH` → 复跑 suite → 归档新日志（负向副本会自动按新文件重新生成）；
   * 顶层 `aurora_mem_bridge.v` 或 `axi_lite_regs.v` 变（如 round2d）→ **本 suite 无需改守卫/无需重跑**（不在依赖内）；但若顶层改动触及探针连线/实例化，需要更新 `R2_probe_map.md` 并重核 ltx；
   * 可选残留：`dma_rd_shim_v2.v`、`async_fifo.v` 也是 TB 编译依赖，当前**未加 hash 守卫**（稳定少动；如要更严可再加两条）。

### 15.3 新 bit/ltx 出来后的核对顺序（不阻断 Lead，仅列清单）
1. bit/ltx SHA256 实测 vs Lead 通知；
2. 归档 RTL 四副本 `git hash-object` = **round2f 四文件集合**（bridge `c92c20c7…`，见 §16.7；round2d 旧集合已随 `4d1c50c7` 废弃，勿混）；
3. ltx 探针：**期望与 round2c 完全一致**（ILA0 probe0=92、probe1=9、ILA3 probe0=152、仅 2 核、裁剪项不出现）——lite_regs 修复不改变裁剪后探针列表（列表里没有 lite_* 探针）；
4. 时钟网名仍需上板 `hw_manager` 一次性确认（ltx 不含时钟网）；`dbg_mem_rden_1` 命名注记仍适用；
5. `u_ila_5 @eth_rxc` **先不加**：等 Lead PC 侧零成本判别（`Get-NetAdapterStatistics` ReceivedErrors/Discarded + 可选 pcap）决定 C（TX 无帧）是否需要 eth 探针，避免再一轮重建；
6. 板端首要验证顺序：'U' 读滞后是否随 RTL 修复消失（2 读即可，3 读仅防御）→ 最小序列 'd'+1 ping 不楔死 → 再 S0–S11 / S4 86B 逐字节。

### 15.4 本轮证据
* `R2_sim_r2_wr_tb_round2d_{pos,neg_cursor,neg_tkeep,suite}_run.log`（新守卫下 suite 复跑结果：PASS/FAIL/FAIL + SUITE PASS）。
* AXI 缺陷/修复证据：`R2_sim_lite_proto_{frozen,fix}_{r,w}.log`、`R2_axi_lite_regs_fix.{diff,v}`（见分析文件 §0）。
* 状态：**AXI 楔死根因记 [L2]（RTL 缺陷：RVALID/BVALID 多拍 → 重复握手；读滞后同源）**；板证待 round2d 位流。修复后若仍有楔死，则按 §0.2 的次级窗口（arready 丢失 AR）/复位失配/互连行为继续二分。

---

## 16. round2e：`WD_WAITGO` 注册判据 patch（`4d1c50c7…`）复核 —— **原 patch 有功能 bug，已给出并验证修正版 fix2**

> 背景：round2d（lite_regs 修复）首掷 place/route WNS=-0.096 门限拒；30/30 最差路径 = `u_mem/u_bridge/full_bit_q_reg[179]` → `g_wr_dma.wd_wait_cnt_reg[*]/CE`（route 80%）。
> Lead patch（blob **`4d1c50c7efe013d7038cbe2f2981f20fd2703bb1`**）：IDLE 接收只注册判据（`wd_noroom/wd_badlen_r/wd_arm_pend`），请求/拒收执行移到 WAITGO 首拍。
> 结论（[L2] 代码级+独立 TB 直证）：**该 patch 在"一次 WAITGO 超时之后"会永久丢弃后续所有帧**（完整正型 TB FAIL）；根因=WAITGO 首拍的 arm 分支与等待逻辑被写成**两个并行 if 语句**（非互斥），首拍用残留寄存器值参与等待判定。

### 16.1 失败证据（完整正型 TB，非 FAST，`R2_sim_r2_wr_tb_round2e_fail_pos_run.log`）
```
[T6] WAITGO watchdog fired ui_cycles=16777037 (基线 16777221, -184 拍 = 从上一帧残留计数起步)
[FAIL-TIMEOUT] commit target=8 got=7  frame len=200 slot=9 not committed
[T6] not stalled: next frame committed cmt=7   ← 期望 cmt=8
[T7]/[T8] 之后所有帧连续 [FAIL-TIMEOUT]（永久性，cmt 停在 7）
```
负向对照（cursor/tkeep 文本缺陷）仍按设计 FAIL（判据本身无问题）。

### 16.2 根因（`axi4_master_bridge.v` 旧 `WD_WAITGO`，代码级 [L2]）
新结构把首拍 arm 与等待逻辑写成**并行**：
```
if (wd_arm_pend) begin ... wd_wait_cnt<=0; ... end
else if (!wd_go_ok && ...) ...
if (wd_go_ok && level>=len && !intr) ... 
else if (wd_wait_cnt == 24'hFFFFFF) ...超时→DRAIN...
else wd_wait_cnt <= wd_wait_cnt + 1;      // ← 同一拍也执行, 覆盖 arm 的 <=0
```
1. 首拍 `wd_wait_cnt<=24'd0` 被后面的 `+1` 覆盖（Verilog 非阻塞"最后赋值生效"）⇒ 计数器不清零、从上一帧残留值起步（T6 -184 拍印证）；
2. 首拍 `else if (wd_wait_cnt==24'hFFFFFF)` 用**旧**计数判断：上一帧 WAITGO 超时后残留 0xFFFFFF（超时分支不清它）⇒ **下一帧首拍立即误超时→DRAIN**；如此每帧首拍都误超时 ⇒ **永久静默丢帧**；
3. 潜伏：首拍旧 `wd_go_ok`（上一帧 commit 后常为 1）会被同拍独立 GO 判定使用（当前仅被 `!s2mm_introut` 偶然挡住），语义上首拍不应参与等待判定。

### 16.3 修正版 fix2（已独立 TB 全绿；候选用）
**改法**：`WD_WAITGO` 内 arm/wait 互斥 —— `if (wd_arm_pend) begin 首拍只 arm（含 wd_go_ok<=0、wd_go_seen<=dma_wr_go、wd_wait_cnt<=0、拒绝判据执行） end else begin GO/level/超时/计数 end`。
* 保持时序目标：`full_bit_q[slot]` 仍只驱动 `wd_noroom/wd_badlen_r` 两个 FF；等待链 CE 仍只由 状态译码 + `wd_arm_pend` FF 驱动。
* **候选 blob**：`c92c20c7fb1884cb6238daf6e03dd69daa93f172`（= `R2_axi4_master_bridge_fix2.v` 逐字拷贝；Lead 若采纳请以此为新冻结值，我据此更新 `EXPECT_HASH`）。
* 文件：`out/evidence_2026-10-17/R2_axi4_master_bridge_fix2.{v,diff}`（diff 已标注与 4d1c50c7 的差异只在 WD_WAITGO 结构 + arm 首拍归位）。

### 16.4 等价复核（Lead patch 中**正确**的部分，fix2 全部保留）
* 拒绝帧不置 pending/toggle、不覆盖未读槽 ✓；规则号 1：槽号只在 IDLE 接收时单点推进（被拒帧同样消耗）✓；
* `wd_beats`/`wd_req_len_r` 改用 `wd_len`、`wd_req_slot_r` 用 `wd_slot` 与旧 `wd_data/wd_slot_next` **等价**（IDLE accept 同拍锁存）✓；
* badlen 统计移到 WAITGO 首拍、`wd_badlen_r` 复位正确 ✓；`wd_noroom` 复用不变 ✓；
* 每帧 +1 拍（拒收帧也 +1，`dbg_wr_cycles` 仅观测）——与 ARM 修复同类，可忽略 ✓。

### 16.5 fix2 独立 TB 结果（`R2_sim_r2_wr_tb_fix2_*_run.log`）
* **正型（完整非 FAST）**：`=== R2 WR TB: PASS (0 errors) ===`；commits=101/exp=101/wm=101；T6 `ui_cycles=16777222`（基线 16777221，+1 = 首拍 arm 语义）；**T6 恢复帧 cmt=8**；T7/T8 计数逐字同基线；T9 恢复+提交 OK；总仿真 `56,684,046,209 ps` 与 round2c 基线逐字相同（+1 拍被 TB 软核轮询粒度吸收，无吞吐可观测差异）。
* **负向对照（从 fix2 文件生成缺陷副本）**：cursor → `[FAIL-T4-CURSOR]` FAIL(2)；tkeep → `[FAIL-KEEP-MASK]` FAIL(1) —— 判据对 fix2 仍有效。

### 16.6 状态与建议
* **Lead 已采纳 fix2**（2026-10-18 18:2x）：buggy `4d1c50c7` 的 place/route 已 kill，`rtl/axi4_master_bridge.v` 用 `R2_axi4_master_bridge_fix2.v` **逐字替换**，实测 blob = **`c92c20c7fb1884cb6238daf6e03dd69daa93f172`**（与候选一致）；xvlog 0 err，重综合已启动。
* mini TB 补"WAITGO 超时帧 → 后接正常帧"用例已被 Lead 采纳（下轮加入并留痕）。
* **`4d1c50c7` 不得烧录/归档为通过版**（永久丢帧），仅作失败复现。

### 16.7 round2f（fix2 采纳后）冻结与 TB 证据
* **新冻结四文件集合**：bridge **`c92c20c7…`** / fmi `96d5b136…` / top `1885225f…` / lite `d133b508…`；ELF `f8cf4022`；新 bit/ltx 待重建。
* suite 守卫已更新：`EXPECT_HASH = c92c20c7…`、`EXPECT_FMI_HASH = 96d5b136…`；**复跑通过**：
  `frozen rtl hash : c92c20c7…` / `expected hash : c92c20c7…` / `frozen fmi : 96d5b136…` →
  `POS_PASS=1 NEG1_CURSOR_FAIL=1 NEG2_TKEEP_FAIL=1` + `=== R2 WR TB SUITE: PASS ===`（exit 0）；
  正型：commits=101/exp=101/wm=101、T6 `ui_cycles=16777222`、**T6 恢复帧 cmt=8**、T8 cursor=320/refused=10/stall=11、T9 恢复+提交 OK、total `56,684,046,209 ps`（与 fix2 验证跑一致）。
  负向：`[FAIL-T4-CURSOR]`（FAIL 2）与 `[FAIL-KEEP-MASK]`（FAIL 1）按设计。
* 日志：`R2_sim_r2_wr_tb_round2f_{pos,neg_cursor,neg_tkeep,suite}_run.log`；fix2 源/diff：`R2_axi4_master_bridge_fix2.{v,diff}`。
* 结论：**round2f TB 绿灯**；等 Lead 新 bit/ltx 做实物核对（期望 ltx 探针与 round2c/2d 完全一致：92/9/152、仅 2 核、裁剪项不出现），板验先最小序列确认 lite 修复 + 写路径，再 S0–S11。

---

## 17. round3 冻结（lite fix2 合入 + 探针扩容）核对与 bit/ltx 待办

> Lead 2026-10-18 21:1x：round3 重综合已启动（r2j）。本节记录**已可核对事实**与 ltx 到达后的核对清单。

### 17.1 四文件冻结（本机 `git hash-object` 实测）
| 文件 | round2f | **round3 现状** | 变化 |
|---|---|---|---|
| `rtl/axi4_master_bridge.v` | `c92c20c7…` | `c92c20c7fb1884cb6238daf6e03dd69daa93f172` | 不变（fix2 写引擎） |
| `rtl/frame_mem_if.v` | `96d5b136…` | `96d5b136305e81ee9d4cc716e60c5034581d027d` | 不变 |
| `rtl/aurora_mem_bridge.v` | `1885225f…` | **`6150212e18ba76cf5ecba0b7aa7d1bb21903f021`** | **仅 +6 行 mark_debug alias（无逻辑）** |
| `rtl/axi_lite_regs.v` | `d133b508…` | **`d5d16d46bd14c3f3c9f40f0d5e89815503046027`** | = 我的 `R2_axi_lite_regs_fix2.v` **逐字一致**（blob 实测相等） |

* **top diff 复核 [L2]**：round3 top vs round2f 归档 top 全量 diff = **13 行（6 行新增 alias + 注释/上下文）**，新增内容仅：
  `dbg_pfwd_data[7:0]=pump_fwd_data`、`dbg_pfwd_en=pump_fwd_en`、`dbg_s2mm_tdata64=s2mm_tdata[63:0]`、`dbg_s2mm_tkeep8=s2mm_tkeep[7:0]`、`dbg_s2mm_tlast_w=s2mm_tlast` ⇒ **探针专用，无功能改动**。
* lite fix2 = 已仿真验证版（单读/单写 PASS；背靠背 2 写 2/2/2 PASS；见 §E.1/分析文件 E.1），合入无额外改动。

### 17.2 构建脚本纸面核对（`build_synth_only.tcl` 与 `build_debug.tcl` 行号逐行一致）
* ILA0 probe0：`nets0` = 93-104 行 = 16+16+16+1+9+16+16+1+1（旧 92b）+ `bus_nets dbg_pfwd_data 8`（:103）+ `dbg_pfwd_en`（:104）= **101b**；位偏移：追加段 **92..99 / 100**（与 §5.4.2 草案一致）。
* ILA0 probe1 = 9b 不变；ILA3 probe0 = 152b 不变（:143-170）。
* **u_ila_5（:177-203）**：@`$uiclk_net`（ui_clk）、`C_DATA_DEPTH 1024`、`C_INPUT_PIPE_STAGES 1`、probe0=64 `dbg_s2mm_tdata64`、probe1=8 `dbg_s2mm_tkeep8`、probe2=1 `dbg_s2mm_tvalid`、probe3=1 `dbg_s2mm_tready`、probe4=1 `dbg_s2mm_tlast_w` ⇒ **64/8/1/1/1=75b**。
* 判读口径沿用 §E.2：**INDET_BTT=1（网表 GEN_INDET_BTT 生效）⇒ WSTRB 来自 TKEEP、TLAST 终止**；beat0 期望 `tdata=0xD555555555555555`/`tkeep=FF`；beat1 `tkeep` 低 22 lane（低 8 位=0x3F）、`tlast=1`。
* 硬件触发（ILA5，逐 probe）：`probe2==1 && probe3==1 && probe4==0`（首拍）；或 `probe4==1`（尾拍）。深度 1024 窗口足够覆盖 2 拍。

### 17.3 板验工具/判据口径同步（Lead 文件，草案已给）
* `out/r2_ilacap.tcl:117` 的 `R2_EXPECT_PROBES` 最终建议值：
  `dbg_s2mm_reqpend,dbg_wr_fault,dbg_s2mm_state,dbg_s2mm_tvalid,dbg_s2mm_tready,dbg_pfwd_data,dbg_pfwd_en,dbg_s2mm_tdata64,dbg_s2mm_tkeep8,dbg_s2mm_tlast_w`
* `R2_ILA_MATCH_EXTRA = dbg_s2mm_tdata64`（脚本已支持该 env；不设置也能工作，只是不会自动匹配 ILA5）。
* 注意：现有 `r2_ilacap` 抓取用 `-trigger_now` 快照；**ILA5 需要 probe 触发采集**（`set_property TRIGGER_COMPARE_VALUE`/`run_hw_ila` 路径），建议为 ILA5 单独加一条捕获流程或手工在 hw_manager 里设触发，别用 trigger_now 盲抓。
* S 判据不受影响（`R2_EXPECT_PROBES` 仍 WARN-only）。

### 17.4 TB 影响
* `r2_wr_tb` 的 DUT 依赖 = async_fifo/dma_rd_shim_v2/axi4_master_bridge/frame_mem_if；**不含 lite_regs、不含 top** ⇒ round3 的 lite/top 变化**不影响 suite 语义**，bridge/fmi blob 未变 ⇒ suite 上轮 PASS 仍有效、守卫无需改（也无需重跑；如需档案新鲜可 3 分钟复跑）。
* 若后续 board 验证显示 lite fix2 有效并去掉 busy_ms，不影响本 TB。

### 17.5 新 bit/ltx 到位后的核对清单（§5.4.5 摘要）
1. bit/ltx SHA 实测 vs Lead 通知；
2. 归档 RTL 四副本 = **round3 集合**（bridge `c92c20c7`/fmi `96d5b136`/top `6150212e`/lite `d5d16d46`）做 bit↔RTL 绑定；
3. ltx：**3 个 ILA 核**（u_ila_0/u_ila_3/u_ila_5，无 ILA1/2）；ILA0 probe0=**101**（bits 0..91 与 round2f 完全同、新 8+1b 在 92..100）、probe1=9；ILA3 probe0=152；ILA5 = **5 probe 64/8/1/1/1**；
4. net 名按实际实现：`dbg_pfwd_data[i]`/`dbg_pfwd_en`/`dbg_s2mm_tdata64[i]`/`dbg_s2mm_tkeep8[i]`/`dbg_s2mm_tvalid`/`dbg_s2mm_tready`/`dbg_s2mm_tlast_w`（Vivado 可能加 `_1` 类后缀，按 ltx 实际为准）；
5. 时序注意：ILA5@300MHz +75b 是下轮唯一实质时序风险；若 sweep 不过按约定降深度（ILA5 1024→512 → ILA3 2048→1024 → 不裁判据探针）。

> **脚本编码说明（对任务书"bat 带 BOM"的落实）**：`run_r2_wr_tb.bat` 采用 **ASCII-only 注释 + CRLF、无 BOM**。
> 理由：本仓库 9 个既有 `run_*.bat` 均为无 BOM；AGENTS.md #17/#18 的 BOM 要求针对 `.ps1`（PS 5.1 解析）；
> 给 `.bat` 加 UTF-8 BOM 会使 cmd.exe 把首行 `@echo off` 当命令名解析（实测报错），破坏一键复现。
> `r2_wr_tb.sv` / `r2_neg_patch.py` 为 UTF-8（含中文注释、无 BOM），xvlog/Python 均正常解析。
