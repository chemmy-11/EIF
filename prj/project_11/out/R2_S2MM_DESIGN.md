# R2（B3-2）桥①写侧换层 S2MM —— 改动方案（Lead 起草，2026-10-17 晚）

> 状态：**设计草案 v1（待 RTL 审计复核后冻结）**。只描述方案与判据，不产生板上结论。
> 依据：AGENTS.md §6a/§九 #55；R1 记录 §三之二十（读侧收口 [L4]）；工作清单 §R2；B3 执行单 §〇 B3-2 行；W5 契约 §2（写槽规则号 1）。
> 判定等级：本文所有机制性描述均为 `[L1-设计]`，板验后按 §6a 重标。

---

## 0. 目标与判据（逐字取自工作清单 §R2）

- **任务**：桥①（INGRESS 写，HAS_DMA=1 实例 `u_mem`）的写路径由 `axi4_master_bridge` 硬件写 FSM 换成 AXI DMA **S2MM**（512b 流→DDR）。
- **判据**：① 四档零回归（ping 20/20、基础 12/12、槽深 12/12、稳定 300/300）；② **10MB 100%+SHA**；③ **双桥计数对账闭合**（口径同 J4：mem/mem2 各自 `wm=wr_frm=rd_frm`、错误计数全 0）；④ **DMA 描述符驱动的写槽规则与规则号 1 逐字等价**（Q2：写布局自由 ≠ 可丢地址信息）。
- **不回归**：R1 四条判据（S0–S8）必须在本位流上继续成立；桥②（`u_mem2`，`HAS_DMA=0`）的**写+读**两条硬件路径**一个字节都不许动**。

---

## 1. 规则号 1：现状与等价性定义（逐字等价的对象）

| 项 | 现状实现 | R2 必须保持 |
|---|---|---|
| 槽号分配 | `wr_slot_ptr[7:0]`，**接收时**（描述符弹出拍）推进，被拒帧同样推进（`axi4_master_bridge.v:308-315,396-420`） | 同一游标、同一推进点、同一被拒推进语义 |
| 槽地址 | `SLOT_BASE + {slot,12'b0}`（`:340`） | `S2MM_SA = SLOT_BASE + slot*4096`（软核按 {slot} 换算，见 §4） |
| 长度 | 描述符 `wd_data` = **实际进入字节 FIFO 的字节数**（`frame_mem_if.v:273-283,326-336`），提交时写 `len_tab`（`:226`） | S2MM `LENGTH` = 同一 `len`；`len_tab/len_beats_tab` 由同一 `wr_commit` 写 |
| 槽占用 | 写成功提交（旧：B 响应；新：S2MM 完成中断）后 `wr_commit` → `full_bit/full_bit_q/len_tab`（`:214-234`）；`out_inc`（`:364-380`） | 同一 `wr_commit` 脉冲语义与同一时刻（DDR 写已提交） |
| 拒收 | `full_bit_q[slot]` 满 → 整帧丢弃、`stat_wr_stall++`、**不覆盖未读槽**、游标仍推进（`:316,411-414,480-503`） | 同 |
| 坏长度 | `len==0 || len>MAX_LEN` → `stat_len_err++`、整帧丢弃（`:317,411-415`） | 同 |
| 数据布局 | 每帧从槽基址起逐字节原样写（含 8B 前导+SFD、尾 4B FCS；尾拍 WSTRB 精确掩码，`:434-471`） | S2MM：512b 流 + TKEEP（尾拍精确），字节图与 WSTRB 逐位一致（§6） |

⇒ **等价性定义**：对任意帧序列，R2 位流写入 DDR 的 `(slot, 起始地址, 每字节偏移→值, len_tab[slot], full_bit 置位时刻、拒收/错误计数语义)` 与 R1 位流**逐项相同**；槽号=帧计数 mod 256 且可由上位机本地复算（W5 契约 §2.2）。

---

## 2. 为什么用"软核逐帧编程 S2MM"（与读侧同构）

- B3 执行单决策 2/3 明确：**描述符由软核下发（源/目的 = 槽号换算地址）**；读侧 B3-1c 已用"桥 FSM 出 {slot,len} 请求 → 软核逐帧编程 MM2S"跑通 J3 四链与 E 轮 16/16，是已验证的成熟件。
- SG（循环描述符环）被 B3 设计记录标为"新的面积与配置风险点"；写侧每帧 LENGTH 变化且槽环复用需状态复位 ⇒ 本轮不引入 SG。
- 每帧 SA/LENGTH 必须变化（len 非 64 整数倍、槽号逐帧递增），故 direct-register 模式 + 逐帧编程是唯一现实方案；S2MM 完成中断（`s2mm_introut`）给硬件提供"写已提交"DDR 时刻，避免"slot 置 full 早于 DDR 写提交"的读后写竞争。
- 吞吐账：四档/10MB 质量档均为低速/带间隔发送（J3 写阶段 pace 1ms、质量档 1ms/帧），逐帧服务（µs 级）足够；**速率归因属 R3**（工作清单 R3 明确允许退化但须量化描述符开销/中断延迟）。

---

## 3. 目标架构（只描述变化点）

```
             user_clk(151.5M)                          ui_clk(300M)
 eth stack TX ──► 泵A ──► frame_mem_if 写侧 ──┬─► 字节FIFO(4KB) ──► 描述符FIFO(8深,len)
                         (槽号分配在桥内)      │
                                              └─(不变: CDC/拒收/WR policy)
 桥① HAS_DMA=1:
   axi4_master_bridge 写路径:  [旧] W_IDLE→W_WAIT→W_AW→W_FILL→W_PUSH→B  (AXI4 写, S00)
                               [新] D_IDLE→D_WAITGO→D_STREAM→D_WAITDONE (AXI4-Stream→S2MM)
   axi4_master_bridge 读路径:  R1 原样 (DMA-only, R_PRE→R_DRET, shim 独占流)
 桥② HAS_DMA=0:
   写路径 = 旧 W FSM 原样;  读路径 = R1 修复版硬件读 FSM 原样   ← 禁改
```

- **仲裁器不动结构**：R1 后桥① 的 AXI 主口只承担写（读已退役），故把 `axi_arb_3to1` 的 **S00 端口从桥① AXI 写口改接 axi_dma 的 M_AXI_S2MM**（S01=桥② 不变、S02=MM2S 不变、M=MIG 不变）。桥① `u_mem` 的 AXI 输出在 HAS_DMA=1 下钉 0、输入钉常量（顶层处理）。
- **新增 BD 端口**：`S_AXIS_S2MM`、`M_AXI_S2MM`、`s2mm_introut`；axi_dma 由 MM2S-only 改为 **MM2S+S2MM**（512b/512b，直通非 SG，控制口 100M、数据/流口 ui_clk=300M）。
- clock/reset：`s_axis_s2mm_aclk = m_axi_s2mm_aclk = ui_clk`；`s2mm_introut` 在 Lite 域(100M) → 顶层 2FF 到 ui。
- 不新增任何 CDC 形式（沿用 2FF/异步 FIFO 两合法形式；GO/请求镜像均 2FF）。

---

## 4. 握手协议（桥① ↔ 软核，全部经 `axi_lite_regs` 映射）

### 4.1 信号/寄存器

| 方向 | 名称 | 载体 | 语义 |
|---|---|---|---|
| 桥→软核 | `DMA_WR_REQ`（读 +0x40） | user 域镜像（2FF） | `{pending[31], 6'b0, toggle[24], slot[23:16], len[15:0]}`；`pending`=请求待服务；`toggle` 每发一笔新请求翻转（**杜绝"连续请求看不到低电平"漏服务**，见 §7） |
| 软核→桥 | `WR_GO`（写 +0x48，opcode 0x05，值 bit0=1 翻转） | user→ui 2FF | 软核完成 S2MM 编程后翻转；桥看到变化才启动流 |
| axi_dma→桥 | `s2mm_introut` | BD 端口→顶层 2FF(100M→ui) | S2MM 传输完成（IOC）。桥以 `introut==1` 作为"该帧 DDR 写已提交" **退休时刻**（与旧 B 响应同语义，见 §6.3） |
| 桥→软核 | `DMA_WR_DBG`（读 +0x44） | user 域镜像 | `{fault[31], 7'b0, last_alloc_slot[23:16], last_commit_len[15:0]}`（取证/`'U'` 用） |

### 4.2 每帧时序（happy path）

1. 桥 D_IDLE：弹出描述符 `len`；`slot=wr_slot_ptr[7:0]`，游标推进（含被拒）；满/坏长度 → 拒收/丢弃（同旧 W_DRAIN 语义）。
2. 桥置 `pending=1, toggle^=1, {slot,len}`（镜像到 user 域）→ **D_WAITGO**（同时等 `wf_level>=len`，同旧 W_WAIT）。
3. 软核驻留服务读到 `pending && toggle!=last` → 清 IOC（写 S2MM_DMASR bit12 W1C）→ 写 `S2MM_SA=SLOT_BASE+slot*4096`、`S2MM_LENGTH=len` → `WR_GO ^= 1`；记 `last=toggle`。
4. 桥见 GO 变化 →（确认 introut 已为 0，最多等 1 个软核服务周期）→ **D_STREAM**：从字节 FIFO 逐拍组 512b（尾拍 TKEEP=`len%64`，TLAST=尾拍）打给 `S_AXIS_S2MM`；全部拍握手完成 → **D_WAITDONE**。
5. S2MM 把数据写 DDR → 完成 → `s2mm_introut=1` → 桥 **D_WAITDONE 见 introut==1**：`wr_commit<=1`（slot,len）+ `stat_wm/stat_wr_frame/out_inc` + 清 `pending` → D_IDLE。（软核下一轮看到 pending=0；下一帧请求重新置位。）
6. 软核在轮询中看到 `pending=0`（或下一请求）→ 为下一帧清 IOC、编程、翻 GO。

### 4.3 异常/超时（防永久停泊，坑 #55/#20 纪律）

| 情形 | 处置 |
|---|---|
| D_WAITGO 超时（`24'hFFFFFF`≈56ms @300MHz；软核未驻留/未切 DMA） | 整帧丢弃（DRAIN 同旧语义）、`pending=0`、`stat_wr_timeout++`、游标已推进；**不置 fault、不停泊**（S2b 身份判据依赖该行为）。陈旧 GO 窗口由固件"写 LENGTH/翻 GO 前二次确认 pending&&toggle"兜底（审计 A4） |
| D_STREAM/D_PUSH 超时（`24'hFFFFFF`≈56ms） | **fail-stop**：`fault=1`、`pending=0`、停泊 `WD_HALT(6)`（不 commit、不覆盖未读槽）；唯一出口 = 软核复位 S2MM+清 IOC+翻 `ACK` |
| D_WAITDONE 超时（`24'hFFFFFF`≈56ms） | 同 fail-stop（不 commit）；软核恢复序列同上 |
| IOC 迟到/陈旧 | 协议保证软核每次 arm 前**先清 IOC**；桥在 D_WAITGO 见 GO 后要求 `introut==0` 才放流（否则等其落零，计入超时） |
| fault 恢复 | 软核：`S2MM_DMACR=0x4`(reset)→等 Halted=1→`0x1001`(RS+IOC)→清 IOC→写 `+0x4C` 翻 ACK；桥见 ACK 翻转→清 fault→IDLE |

---

## 5. HAS_DMA 参数化边界（坑 #55 复刻纪律）

| 模块/逻辑 | `HAS_DMA=1`（桥① `u_mem`） | `HAS_DMA=0`（桥② `u_mem2`） |
|---|---|---|
| 读 FSM | R1 原样：R_PRE→R_DRET（DMA-only，shim 消费流） | R1 修复版原样：R_PRE→R_AR→R_R→R_UNPACK→R_FIN |
| **写 FSM** | **退役**：新 D_* 状态机（S2MM 流 + 请求/GO/introut 协议），AXI 写口钉 0 | **旧 W_* 状态机原样，逐字节不动**（含 L2 提交队列/B 出队/槽游标/DRAIN） |
| AXI 写口 | 不驱动（顶层不接 S00；`m_axi_awvalid/wvalid=0`） | 原样驱动 → 仲裁器 S01 |
| `rf/rd` 读出口 | shim 独占 | 硬件读 FSM（R1 修复版） |
| 槽表/计数/outstanding | 同一套 `wr_commit/rd_retire` 语义 | 同 |
| 生成方式 | `generate if (HAS_DMA) ... else ...`，两分支**互斥 elaboration**；旧写 always 块整块移入 `else` 分支（文本逐字保留） |  |

验收方法（离线）：`git diff` 中 HAS_DMA=0 分支代码块必须与 R1 修复版**逐字节相同**；`mem_bridge_tb`/`w4_joint_tb`（均 `.HAS_DMA(0)`）回归 PASS 且计数逐字不变。

---

## 6. 字节/突发等价性（S2MM 512b 流 vs AXI4 512b 写）

1. **拍内映射**：AXI 写 wdata 字节 lane k = 帧字节偏移 k（小端）；AXI-Stream 512b tdata lane k 同 → S2MM 把 tdata 原样映射到 wdata（需离线 TB 与板验各证一次）。
2. **尾拍**：旧写 WSTRB[k]=1 当且仅当 k < len%64（`:447-457`）；新 S2MM TKEEP 同规则（尾拍仅有效 lane=1，其余拍全 1）。
3. **退休时刻**：旧 B 响应 = MIG 已受理写（**BRESP 回包**）；新 `s2mm_introut` = S2MM 传输完成（S2MM 必须收到全部 BRESP 才能置完成/错误位）⇒ 两者都满足"slot 置满前 DDR 写已提交"。**这条是 R2 的关键风险假设，需离线 TB（IOC 行为模型）+ 板上 S4/S5 计数+回显联合验证**。
4. **帧边界**：旧 AWLEN=beats-1 单 burst；新 S2MM 自行拆 burst（>16 拍可能分两笔），仲裁器 S00 事务级轮转不受影响（每笔独立授权；响应按授权锁存路由，与 ID 无关——W4 修复已定案）。
5. **8B 前导+4B FCS**：写侧不增删任何字节（`len` 原样），填槽内容 = 线上字节流 + 前导/FCS（读侧 R1 已证明槽内即此布局）。

---

## 7. 桥①↔软核请求镜像为何用 toggle（不是电平 sticky）

读侧用"电平 sticky"可行，因为**读请求由软核触发**、退休后电平清零无新请求竞争。写侧不同：帧到达是外部驱动，软核完成第 N 帧后第 N+1 帧请求可**在同一 2FF 窗口内**紧接置位 ⇒ 若只看电平，软核可能永远看不到低电平而漏服务。故写侧请求采用 **toggle（每请求翻转）+ pending 电平** 双字段：软核按 toggle 变化识别新请求；pending 只作启动初始化/诊断。

---

## 8. 改动清单（文件级）

| # | 文件 | 改动 | 不动边界 |
|---|---|---|---|
| 1 | `rtl/axi4_master_bridge.v` | 端口 + 写侧 generate 分支（新 D_* FSM、S2MM 流口、请求/GO/introut 握手、`stat_wr_timeout`/fault 计数）；旧 W 写块整体移入 `if(!HAS_DMA)` 分支（文本不动） | 读 FSM 四态与 R_DRET 原样；槽表/outstanding 语义不动 |
| 2 | `rtl/frame_mem_if.v` | 端口新增：`dma_wr_go`(user)、`s2mm_introut`(100M)、S2MM 流输出、`ro_dma_wr_req`/`ro_dma_wr_dbg`(user 镜像)、新计数输出；DMA 写请求镜像（toggle+pending，2FF）；`dma_wr_go` 2FF ui；introut 2FF ui | 写侧 gather/拒收/字节 FIFO/描述符 FIFO 语义不动；读侧 PRIME 不动；`HAS_DMA=0` 时新增输出钉 0 |
| 3 | `rtl/axi_lite_regs.v` | 读表 +0x40 `DMA_WR_REQ`、+0x44 `DMA_WR_DBG`；写 +0x48 opcode 0x05 → `cfg_wr_go` 翻转；新端口 | 既有寄存器地址/语义不动（+0x34/+0x38/+0x3C 不变） |
| 4 | `rtl/aurora_mem_bridge.v` | 仲裁器 S00 改接 S2MM；`u_mem` AXI 口钉常量；新 BD 端口接线；新 ILA 探针（`dbg_s2mm_*`、`dbg_wr_timeout`） | 桥② u_mem2/泵A/泵B/pack/unpack/Aurora/MIG 接线不动 |
| 5 | `scripts/create_bd_b.tcl` | axi_dma 加 S2MM（512b/512b）、外引 `M_AXI_S2MM`/`S_AXIS_S2MM`/`s2mm_introut`、新时钟网、lite_regs 新 pin 外引 | 既有 MM2S/地址/互联不动 |
| 6 | `scripts/build_debug.tcl`（及 `build_synth_only.tcl` 同步） | ILA3 加 ui 域 S2MM 写路径探针（状态/一二位/计数，控制位宽防拥塞，坑 #47/W6 纪律） | ILA0/1/2 与既有 ILA3 探针不动 |
| 7 | `sw/src_j3/main.c`（→ 同步 `sw/j3_soft/src/main.c`，坑 #53） | 写服务 `serve_write_once()`（S2MM 清 IOC/编程/GO）、`serve_any()` 合并读+写；守候环/轮内等待循环调用；`'d'` 初始化 S2MM；`'U'` 追加 WR_REQ/WR_DBG 打印 | 读服务 `serve_dma_once` 语义不动；串口/轮命令行为不动 |
| 8 | `sim/` | 新 `r2_wr_tb.sv`（S2MM 流模型 + 规则号 1 golden model + 字节逐字节）；`run_r2_wr_tb.bat`；W2/W4/bridge_dma 回归复跑 | 既有 TB 不动（除新增 .HAS_DMA(0) 已就位） |

---

## 9. 离线验证（构建前硬门槛）

1. **R2 WR TB（新）**：DUT = `frame_mem_if(HAS_DMA=1)` + 新写路径；S2MM 用行为模型（收 AXIS → 写 512b AXI4 RAM，B 响应后拉 introut）。用例：
   - T1 单帧 len=64（整拍）、T2 len=70（尾拍 6 lane TKEEP）、T3 背靠背 3 帧不同槽、T4 满槽拒收（full_bit 保持、游标推进、不覆盖）、T5 len=0/超长拒收、T6 GO 缺失超时→丢帧且不停泊、T7 完成/1 帧后 introut 清除再下一帧、T8 **规则#1 golden model**：随机 100 帧后逐槽比对 `full_bit/len_tab/槽地址/字节内容` 与参考模型（参考模型直接复刻旧 W FSM 语义）。
2. **负向对照**（坑 #43 纪律）：注入"槽游标被拒时不推进"与"尾拍 TKEEP 用满 lane"两个缺陷副本，TB 必须 FAIL 且指认到具体判据行。
3. **既有回归**：`mem_bridge_tb`(HAS_DMA=0)/`w4_joint_tb`(HAS_DMA=0)/`bridge_dma_tb`(HAS_DMA=1 读路径) 全 PASS，计数与 R1 基线逐字一致（日志归档）。
4. **单模块 OOC 综合**（坑 #27 纪律）：`axi4_master_bridge`/`frame_mem_if` 各跑一次 mini synth，过则进工程级综合。

---

## 10. 构建与上板（R2 判决序列草案）

**构建**（离线，Lead）：create_bd_b.tcl 重建 BD → build_synth_only.tcl（synth+ILA→pre_impl_debug.dcp）→ build_v5_sweep.tcl（place 指令扫描，WNS/WHS≥0 出位流）。产物立即归档 `out/archive/b31b_r2_2026-10-17/` 并核 SHA256。

**上板**（Lead 亲自；硬件在环不委派）：
- S0 离线：bit/ltf/xsa/ELF hash + 构建日志 `SWEEP_*: WNS/WHS` + DRC 0；产物身份钉死。
- S1 **不做绿基线烧录**（板卡当前在役 = R1 修复配置；直接烧 R2 对，前一步记录在位配置即 S1 替代）——若需要对照再回烧。
- S2 **身份判据**：新烧 R2 位流 + 新 ELF，**不发 `'d'`**：ping 必须 0/1、`wmwr` 不增（写路径未服务=身份）；同时 `'U'` 可读 WR_REQ（pending 应=1 表示第一帧已挂起）。
- S3 `'d'` 后 `'U'` 双确认：读引擎位（沿用）+ **WR_REQ/WR_DBG 出现合法 slot/len 且 pending 落 0**（写路径真被服务）。
- S4 单帧端到端：`ping -n 1` → 1/1、NIC `ReceivedBytes +74`、`WM_WR +1`/`WM_RD +1`。
- S5 ping×4：4/4、Bytes +296、`WM_WR/WM_RD 各 +4`。
- S6 桥级 ILA（S7 同口径）：桥② `rd_frm` 随 ping +4、`ost` 恒 0；桥① 写提交计数 `dbc_mem_wr_frm` 与 `wm` 同步。
- S7 四档：`udp_verify_ddr.py`（prj10 prj_loop/scripts）`DDR_VERIFY: PASS`（20/20·12/12·12/12·300/300）。
- S8 **10MB 100%+SHA**：质量档（1ms 间隔）`json_storm.py testdata/session_full.jsonl`（prj9/prj10 脚本，PC 侧）+ 逐字节/SHA 判定；记录实际速率（R3 基线）。
- S9 J3 四链（带 `--dma`，`out/j3_fourchains.ps1`）+ `manual_round 256` 旁证。
- S10 **双桥计数对账闭合**：ILA 抓 mem/mem2 `wm/wr_frm/rd_frm/ost`，要求各自 `wm=wr_frm=rd_frm`、错误计数（bresp/len_err/stall 按语义）为 0；与 J4 口径一致地给出对账表。
- S11 写槽规则复算：按 `WM_WR` 基线 + 帧序号本地复算槽号，抽 N 槽用 RND 读回内容比对（J3′ 集合一致已覆盖）。
- 全程原始日志落 `out/evidence_2026-10-17/R2_*`；任何 `FAIL/NOT_OBTAINED` 按 §6a 硬规则 3 措辞。

---

## 11. 风险清单

| # | 风险 | 缓解 |
|---|---|---|
| K1 | S2MM 512b 直通模式的**尾拍 TKEEP/多拍长度**行为与模型不符（B3-1a MM2S 曾卷出"确定性装配偏移"） | 离线 TB 只能证本侧；上板先 S4 单帧逐字节（ping payload 已知）→ 再四档覆盖各类尾余数；必要时用 ILA1 probe1 抓槽读回字节 |
| K2 | IOC 中断与"BRESP 已收"不等价（提前退休→读后写竞争） | S4/S5 差分（WM 与 NIC 双向一致）+ J3 逐字节+SHA 覆盖；若 S4 偶发错误再改用 B 响应计数方案 |
| K3 | 每帧软核服务延迟拖慢 ping/四档（尤其 `rd_reg` 含 busy_ms） | 轮内等待循环用 dread+serve_any；服务质量先保功能；速率归因留 R3 |
| K4 | BD 加 S2MM 后时序更紧（当前 +0.004）、构建扫描轮次 | 按 K1 风险预算：每轮 1.5–2.5h × 1–3 掷；ILA 新探针控制位宽（W6 教训） |
| K5 | HAS_DMA=0 被误伤（坑 #55 复刻） | 旧写块整块文本搬入 `else` 分支；W2/W4 TB 回归 + 审计 diff 逐字 |
| K6 | 软核服务与轮内调度死锁（读服务等待时写请求堆积） | 写 FIFO 4KB=2.7 帧；J3 写阶段 pace 1ms、读阶段无写请求；若出现堆积计 `stat_wr_timeout/buf_drop` 可观测 |

---

## 12. 依据等级与待证清单（构建/板验前必读）

- `[L0]`（禁写结论）：S2MM TKEEP→WSTRB、IOC 时刻、S2MM 拆 burst 细节均为**厂商文档/经验推断**，未经本板实测。
- 构建前必须取得 `[L2]`：离线 TB + 两个既有回归 + OOC synth。
- 板验后才允许写 `[L3]/[L4]`：S0–S11 原始日志 + 对照矩阵。

---

## 13. v1.1 冻结变更（2026-10-17 22:2x，独立 RTL 审计 A1–A6 回填）

> 审计报告（首轮）见 `out\evidence_2026-10-17\R2_rtl_audit.md`；本节记录方案随审计的最终变化，以 RTL 为准。

| 审计项 | 结论 | 最终实现 |
|---|---|---|
| **A1（阻塞，L2）** | g_wr_dma 分支内同名 `reg wr_slot_ptr` 遮蔽模块级信号 ⇒ 读侧 c_clamp/c_in_rng/p_target_ok 断源（xvlog 不报错=静默缺陷） | **删局部声明**，写引擎直接驱动模块级 `wr_slot_ptr`；读路径同源恢复 |
| **A2（高，L2）** | HAS_DMA=1 下 7 根 AXI4 写口输出无驱动 | g_wr_dma 内显式 `assign m_axi_awaddr/awlen/awsize/awburst/wdata/wstrb/wlast = 0`；顶层 u_mem 这些口**悬空**、不再接 S00/不再 assign |
| **A3（高，L1）** | STREAM/PUSH 无看门狗，tready 长低可永久停泊 | 加 24 位 stall 看门狗（≈56ms@300MHz）→ `stat_wr_timeout++`、`fault=1`、进 **WD_HALT** |
| **A4（高，L1）** | 超时后陈旧 GO/IOC 误同步窗口 | 超时（STREAM/PUSH/WAITDONE）一律 **fail-stop 进 WD_HALT**，停收新帧；WAITGO 超时仍为良性丢帧（不发流；S2b 身份测试依赖该行为；风险窗口 = 软核读-臂间隙 µs ≪ 56ms） |
| **A5（中）** | 超时值与设计不一致 | 统一 24 位 0xFFFFFF ≈56ms（四类看门狗同值） |
| **A6（中）** | fault 无清除路径 | 新增写寄存器 **+0x4C（opcode 0x06）→ 翻 `cfg_wr_ack`**；桥 WD_HALT 见 ack 翻转 → 清 fault 回 IDLE。软核恢复序列 = S2MM DMACR reset → RS+IOC → 清 IOC → 写 ACK |
| **A7（域纠正）** | — | `dma_wr_go/ack` 源在 axi_lite_regs 的 **user_clk(151.5M) 段**（非 100M），frame_mem_if 做 user→ui 2FF；`s2mm_introut` 在 Lite 100M 域，frame_mem_if 做 100M→ui 2FF |
| **A8（信息）** | S2MM burst=16 拍 ⇒ 1538B=25 拍拆 16+9 两笔；DRE 512b 不可用 ⇒ SA 必须 4KB 对齐 | 与设计一致（SA 恒 4KB 对齐），仲裁器按事务授权不受影响 |
| **A9（信息，L1）** | TKEEP→WSTRB 在厂商 datamover 内部有两种形态，本板配置未证 | 保留 [L1]；板验 S4 单帧（len=86，尾拍 22 lane）逐字节 + 记 S2MM DMASR；四档/J3 覆盖多长度。若 S4 字节错而 wmwr 正常 ⇒ 优先怀疑 TKEEP 语义 |

**最终接口（v1.1 冻结，写进 TB/判据）**：`frame_mem_if` 新增
`dma_wr_go`(user) · `dma_wr_ack`(user) · `s2mm_introut`(100M) · `dma_wr_tdata/tkeep/tlast/tvalid`(ui 出) · `dma_wr_tready`(ui 入) ·
`ro_dma_wr_req`(user) · `ro_dma_wr_dbg`(user) · `ro_stat_wr_timeout`(ui) · `ro_dbg_wr_state`(ui, 0..6, 6=HALT)。
`axi_lite_regs` 新增 +0x40/+0x44 读、+0x48/+0x4C 写；RTL 文件冻结 hash 见 2026-10-17 22:3x 消息/证据索引。

**固件（`sw/src_j3/main.c`，ELF `1bc8088d`，50,896 B，blob `ee256c05`）**：`s2mm_channel_init()`（DMACR reset→RS+IOC→清 IOC）、`serve_write_once()`（按 pending/toggle 变化 arm；写 LENGTH/翻 GO 前**二次确认请求仍有效**——A4 残余窗口兜底；fault 时恢复序列）、`serve_any()`（读优先，写请求并入空闲环/轮内写等待环/'E' 轮）。"GO 前二次确认"用于兜底 WAITGO 超时后软核迟到的旧帧服务（审计 A4 建议）。

---

## 14. v1.2 文档对齐（2026-10-17 23:0x，独立审计 §8 D1–D8 回填；RTL 未变）

> 审计报告：`out\evidence_2026-10-17\R2_rtl_audit.md`（TB 正型 PASS 0 errors / 101 commits；负向对照 2/2 按设计 FAIL 且指认判据行；三回归见其 §7）。以下为**文档口径**订正，避免后续误读：

1. **D1/A5 超时值**：统一 **24 位 `0xFFFFFF` ≈56ms@300MHz**（WAITGO/STREAM/PUSH/WAITDONE 同值）；§4.3 原"WAITDONE 2^25≈112ms"作废。
2. **D2/A4 异常表**：补 fail-stop：STREAM/PUSH/WAITDONE 超时 → `fault=1` + 停泊 **WD_HALT(6)**，唯一出口 = 软核复位 S2MM+清 IOC+翻 `ACK(+0x4C)`；**WAITGO 超时 = 良性丢帧不 halt**（S2b 身份判据依赖），其陈旧 GO 窗口由固件"GO 前二次确认"兜底。
3. **D3/A6 寄存器表**：补写 `+0x4C`（opcode 0x06）= 翻 `ACK`；恢复序列 = `S2MM_DMACR=0x4`→等 Halted→`0x1001`(RS+IOC)→清 IOC→翻 ACK。
4. **D4/A9 措辞**：离线 TB **只证 DUT 输出流**满足设计（TKEEP/TLAST/字节），**不证厂商 IP 的 TKEEP→WSTRB/IOC 行为**；后者归板验 S4→L3。A9 保持 [L1]。
5. **D5/A13 回归范围**：`bridge_dma_tb`（HAS_DMA=1 直例化）写路径契约已变，仅补 tie 会 56ms×N 超时 FAIL ⇒ 该 TB 由审计补了"最小 S2MM 服务模型"（~45 行）后复跑；`mem_bridge_tb`/`w4_joint_tb`（HAS_DMA=0）纯 tie 即可。
6. **D6/A4**：见 §2;固件已在写 LENGTH/翻 GO 前二次确认 `pending==1 && toggle==saved`。
7. **D7 等级**：离线可证到 [L2] 的是：A1–A6 修复、规则号 1 等价、HAS_DMA=0 未误伤、TB/负向/回归；**A7/A8/A9/S00 复用**保持 [L1]；板验后升 [L3/L4]。
8. **D8/A11 `lat_w`**：桥① AXI 写口退役后 `ro_lat_w` 在 `u_mem` **恒 0**（B3-0 口径仅对桥②/HAS_DMA=0 有意义）；**禁止**用 `GET_LATENCY` 的桥① 值做判据。
9. **A12 取证字段语义**：`WR_DBG.last_alloc_slot` = 最近**分配**槽号；`last_commit_len` = 最近**提交**帧长（分配≠提交）。
10. **A3/G2 覆盖缺口**：STREAM/PUSH 看门狗分支离线未触发（T9 只触发 WAITDONE 同构路径）；结构存在由代码审查判 [L1]，板验靠 `dbg_s2mm_state=6/HALT`+fault 观测承接。

---

## 15. 构建结果（2026-10-18 00:5x 收尾，**NO_BITSTREAM**）

- place/route 5 掷全部被时序门限（WNS≥0 & WHS≥0 @ ui_clk 300MHz）拒收：`ExtraTimingOpt` 最好 **WNS −0.098 / WHS +0.004**；`Default` MIG 瞬态；`AggressiveExplore` 布局失败；`WLDrivenBlockPlacement` −0.225；`ExtraPostPlacementOpt` −0.175。失败轮**不写位流、不覆盖在库产物**（现役仍 R1 `c8cd3a32`）。
- **失败诊断 `[L2]`**（失败轮最差路径报告）：30 条最差路径中 25 条 = `u_mem/u_wr_bytes/wr_gray_s2` → `u_mem/u_bridge/g_wr_dma.wd_data_r_reg[*]/CE`（本设计新写引擎的**字节捕获锥**：gray 比较 8 级 → 64:1 lane 译码 → 512 CE，route 占 56.6%）；另 5 条 = 桥② 旧写 FSM 同族（未被 R2 改动）。
- **修复建议（下次开工第一步）**：新写引擎字节捕获加 1 级流水（`byte_q`/`byte_valid_q`，CE 改由寄存器驱动；`wf_rd_en` 仍由 `!wf_empty` 控制；吞吐不变；不动 `HAS_DMA=0` 分支）。备选：裁 ILA3 低价值探针 ~48b / 换指令取方差 / `build_debug.tcl` 单掷。详见归档 `out/archive/b31b_r2_2026-10-17/BUILD_STATUS.md`。
- 板验未执行（`NOT_OBTAINED`，用户要求收尾+断电；板卡未被触碰）。

---

## 16. 构建轮次 2（2026-10-18 上午，时序修复后重掷）

- **时序修复（[L2] 离线，独立审计 A16 复现/复核）**：`g_wr_dma` 字节捕获改为 **1 级流水**（`byte_q`/`byte_valid_q`；`wd_fetch` 只在非满拍保持拍取字节）——把失败轮 25/30 的 `gray→lane 译码→512 CE` 8 级锥从关键路径移走，吞吐仍 1B/cycle。首版流水（blob `740ab153`）有"满拍保持拍重复 fetch 覆盖跨拍预取字节"缺陷（每非末拍丢 1 字节，len≥66 帧尾拍永不成立 → 56ms HALT），由独立 TB 在冻结 hash 上抓到（T1 len=64 PASS vs T2 len=70 不提交/T3 自 k=64 逐字节错位 = 机制对照）；修法 = `wd_fetch` 加 `&& !wd_beat_full`（beat 完成拍旧值=0 仍可跨拍预取，无吞吐损失）。
- **冻结 RTL（round2c 最终）**：`axi4_master_bridge.v` blob **`f43267db82b84305cfeb519adcfa76f79443f6b3`**（在 round2b `06e6bd72` 基础上再加 `WD_ARM=3'd7` 一拍：把 WAITGO 完成条件 `wf_level>=wd_len` 的 12b 比较从 512 位数据/keep 寄存器的 CE 上移走，改为状态译码清零；HALT 仍=6；每帧 +1 拍）；其余三文件不变（`96d5b136`/`1885225f`/`421df59c`）；`g_wr_hw`（HAS_DMA=0 旧 FSM）与读 FSM 逐字节未动（坑 #55 边界 ✅）。
- **离线复验（审计 `R2_rtl_audit.md` §13，59,552 B）**：完整非 FAST 正型 **PASS 0 errors（commits=101）**、T6 真实 16.7M 拍、T8/T9 全过；2 负向对照按设计 FAIL；基线差异仅帧完成 +1 拍/帧（设计预期）。
- **ILA 裁剪（round2b）**：ILA1/ILA2 整核移除；ILA0 probe0 374→**92**、probe1 9；ILA3 probe0 184→**152**（裁 bresp/wslot/rslot）；审计 §12 复核 + `R2_probe_map.md §5.1` ltx 实物直证（仅 2 核、92/9/152、末 5bit 正确、裁剪项缺席）。
- **place/route（round2c，`ExtraTimingOpt`）**：后布 WNS **+0.042** → phys_opt 后 **WNS +0.004 / WHS +0.004** ⇒ **过门限**；**DRC 0 Errors / 22 Warnings**；`V5_SWEEP2_OK`；`write_bitstream` 成功。
- **构建产物（`out/archive/b31b_r2_2026-10-18/`，21 文件 + SHA256.txt）**：bit `aurora_mem_bridge_r2_28921C6B.bit`（10,266,180 B，SHA256 `28921C6B…324627`）；ltx `probes_r2_28921C6B.ltx`（64,593 B，SHA256 `4AC25546…6B7C33`）；xsa `16A4F01F…`；ELF `1bc8088d`（50,896 B）。
- 板验：**进行中**（10-18 下午，用户上电后烧 R2 对 → S0–S11；S0 dry-run 已 PASS：WNS/WHS/DRC/hash 全过）。
