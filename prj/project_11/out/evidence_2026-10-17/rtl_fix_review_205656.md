# 独立复核报告：`axi4_master_bridge.v` 读引擎按 `HAS_DMA` 恢复

- 复核员：独立只读复核（未改仓库文件、未 commit、未碰硬件；未运行 xsct / vivado GUI / ping / 串口 / 全 TB 仿真）
- 时间：2026-10-17 20:56（Asia/Shanghai）
- 仓库／工程：`D:\FPGA`，`prj/project_11`，Vivado 2023.1（XCKU060）
- 复核对象：工作树未提交修改（`git status` 的 3 个文件）
  - `prj/project_11/rtl/axi4_master_bridge.v`：`+65 / -1`（blob `7fe880e`；HEAD/8afa168 为 `d0ed165`）
  - `prj/project_11/sim/mem_bridge_tb.sv`：`+1 / -1`（`.HAS_DMA(0)`）
  - `prj/project_11/sim/w4_joint_tb.sv`：`+2 / -2`（两处 `.HAS_DMA(0)`）
- 基线：退役前 `3f847e3`（bridge blob `d27089f`，846 行）→ 退役 `8afa168` → `5c9a8e9` → HEAD `96efc39`
- 方法：`git diff` / `git hash-object` / 逐信号驱动扫描 / 状态可达性枚举 / `xvlog`+`xelab`（临时目录，不污染仓库）/ 归档仿真日志复核
- **总判定：通过。未发现漏恢复、多驱动或语义差；修复对 `HAS_DMA=0` 实例与 `3f847e3` 逐字等价。** 仅有 3 条非阻塞项（注释、TB 标签、构建闸门），见 §8。

---

## 0. A–F 结论摘要

| 项 | 结论 | 一句话依据 |
|---|---|---|
| A 完备性 | **OK** | 清单 23 个信号 + `gen_no_dma` 6 个输出全部有驱动；`shim_frame_done` 新增 tie-0；无悬空、无新增多驱动 |
| B 正确性/参数化 | **OK** | `HAS_DMA` 在 always 内作常量合法（xvlog/xelab 0 warning，W2/W4 已 elaborate `HAS_DMA=0`）；`HAS_DMA=1` 时 R_AR/R_R/R_UNPACK/R_FIN 不可达，`HAS_DMA=0` 时 R_DRET 不可达；`dma_engine` 端口在模块内已无消费者（无 ELAB 告警，仅注释过期） |
| C 单一驱动 | **OK** | `out_inc` 只在写 FSM；`out_dec/rd_retire/stat_rd_frame/rd_seq_slot/brd_wr_*` 只在读 FSM；R_FIN 与 R_DRET 是同一 always 内互斥 case 臂，不构成重复驱动 |
| D 语义等价 | **OK** | 4 个恢复状态与 `3f847e3` **逐字节相同**；R_PRE 6 条赋值逐字相同；HAS_DMA=0 实际配置下仅多 `shim_frame_done=0` 与 `dma_engine`→`HAS_DMA` 守卫，行为无差 |
| E 桥①仅 DMA | **OK** | R_DRET 的退休字段与 R_FIN 逐项等价；SEQ 下 `dma_req_slot+1 ≡ rd_seq_slot+1`（指针在 R_DRET 期间冻结）；无 `brf_*` 旁路 |
| F 上板预测 | **可验证** | 4 条硬预测 + 判别性对照 + 失败矩阵（§7）；现有 ILA3 已含 `dbg_mem2_rd_frm/ost/wm`，无需改 RTL |
| G 缺陷/修正 | **无功能性缺陷** | 仅 3 条非阻塞建议（§8）；不需行号级代码修正 |

---

## 1. 事实基线与复核边界

### 1.1 工作树确实是“退役 RTL + 本次修复”

- `git hash-object axi4_master_bridge.v` = `7fe880e78a627f84493a31e6dece33220169fafd`；`HEAD:…` = `d0ed1655…`。
- `git log --oneline 8afa168..HEAD -- prj/project_11/rtl/axi4_master_bridge.v` 为空 ⇒ HEAD 的 bridge 与退役提交 `8afa168` 相同；工作树只多本次修复。
- `git diff 3f847e3 -- …/axi4_master_bridge.v` 的全部内容 = 退役 5 处（其中 2 处被本次修复按 `HAS_DMA` 重新守卫）+ 本次新增。`git diff --check` 无空白错误。
- `prj/project_11/rtl/aurora_mem_bridge.v` 的退役两处（`dma_tready` 恒接 shim、`u_dma_sink.s_tvalid=0`）已在 `8afa168/5c9a8e9` 提交，本次工作树**未再改**；不在本次修复范围内，其等价性已由 `out/evidence_2026-10-17/rtl_audit_204519.md` §2 Δ1/Δ2 审计。

### 1.2 离线检查（全部在临时目录，不改仓库）

| 检查 | 命令 | 结果 |
|---|---|---|
| 语法 | `xvlog -sv axi4_master_bridge.v dma_rd_shim_v2.v` | exit 0，**0 warning** |
| Elaborate 默认 `HAS_DMA=1` | `xelab -debug typical axi4_master_bridge -s rev_h1` | exit 0，0 warning |
| Elaborate `HAS_DMA=0` | 由 W2/W4 归档日志证明 | `xsim_run.log:30`、`w4_joint_run.log:35` 均 `Compiling module work.axi4_master_bridge(HAS_DMA=0)` |
| W2 回归（`mem_bridge_tb`） | 归档 `sim/xsim_run.log`（20:48:26，晚于 RTL/TB mtime 20:47:49） | `PASS (0 errors)`；`rd_frame=585`，`rd_beats=8202` |
| W4 双桥回归（`w4_joint_tb`） | 归档 `sim/w4_joint_run.log`（20:49:10） | 正控 `PASS (0 errors)`；A/B 各 `rd=148`；负控 `DEFECT_ROUTING=1` 按预期 FAIL/deadlock |
| DMA 单桥回归（`bridge_dma_tb`） | 归档 `sim/bdma_run.log`（20:47:36） | `BRIDGE_DMA_TB: PASS`，P1/P2/P3 全过 |

> 说明：未重跑全 TB；只读了归档日志并做了单模块 `xvlog/xelab`。日志时间晚于三个源文件的 mtime，能证明“改后跑过”。

---

## 2. A — 完备性（逐信号）

### 2.1 清单信号：当前工作树全部有驱动

行号均指当前工作树（857 行，LF）；括号内为状态/用途。

| 信号 | 当前驱动点 | 结论 |
|---|---|---|
| `brf_wr_en` | 638(reset)、650(块顶默认清)、748(R_UNPACK) | OK，与 3f847e3 驱动集合相同 |
| `brf_wr_data` | 638(reset)、749(R_UNPACK) | OK |
| `rd_retire` | 643(reset)、648(默认清)、760(R_FIN)、779(R_DRET) | OK，单 always |
| `rd_retire_slot` | 643(reset)、761(R_FIN)、780(R_DRET) | OK |
| `out_dec` | 645(reset)、649(默认清)、762(R_FIN)、781(R_DRET) | OK，单 always（见 §4） |
| `stat_rd_frame` | 644(reset)、763(R_FIN)、782(R_DRET) | OK |
| `rd_seq_slot` | 643(reset)、666(R_IDLE 扫描)、764(R_FIN)、783(R_DRET) | OK |
| `brd_wr_en` | 638(reset)、651(默认清)、690(R_PRE 目标失败)、765(R_FIN)、788(R_DRET) | OK |
| `brd_wr_data` | 638(reset)、691(R_PRE 目标失败)、766(R_FIN)、789(R_DRET) | OK |
| `dbg_rd_beats` | 645(reset)、742(R_R)、784(R_DRET) | OK |
| `r_slot` | 639(reset)、711(R_PRE 硬件分支) | OK |
| `r_len` | 639(reset)、712(R_PRE 硬件分支) | OK |
| `r_beats` | 639(reset)、713(R_PRE 硬件分支) | OK |
| `r_beat` | 639(reset)、714(R_PRE 硬件分支)、753(R_UNPACK) | OK |
| `r_bi` | 639(reset)、741(R_R)、751/755(R_UNPACK) | OK |
| `r_beat_data` | 640(reset)、740(R_R) | OK |
| `m_axi_arvalid` | 637(reset)、660(R_IDLE)、724/726(R_AR)、776(R_DRET) | OK |
| `m_axi_rready` | 637(reset)、661(R_IDLE)、737/739(R_R)、777(R_DRET) | OK |

补充：`r_nbytes` 仍是 628–633 的组合 always（源自 `r_beat/r_beats/r_len`），随 R_UNPACK 恢复而重新被使用；`m_axi_araddr/arlen/arsize/arburst` 是 622–625 的组合 assign，未被删除。

### 2.2 `gen_no_dma` 输出：6 个全部有驱动

`axi4_master_bridge.v:568–575`：

```verilog
end else begin : gen_no_dma
    assign rf_wr_en   = brf_wr_en;      // 569
    assign rf_wr_data = brf_wr_data;    // 570
    assign rd_wr_en   = brd_wr_en;      // 571
    assign rd_wr_data = brd_wr_data;    // 572
    assign dma_s_tready = 1'b0;         // 573
    assign shim_frame_done = 1'b0;      // 574  ← 本次新增
end endgenerate
```

`gen_dma_engine`（549–567）一侧：`rf_wr_en/data` 来自 shim（563–564），`rd_wr_en/data` 来自 `brd_*`（566–567），`dma_s_tready`/`shim_frame_done` 由 shim 实例驱动（557/559）。generate 两分支互斥，每个 elaboration 只有一套驱动，无多驱动。

### 2.3 结论

- 退役删除的 4 个状态里驱动的所有 reg，本次都已恢复；**没有“只在被删状态里驱动、现在悬空”的信号**。
- 没有新增多驱动：`shim_frame_done` 只在 `gen_no_dma` 被 tie，`gen_dma_engine` 由 shim 输出驱动，互斥。
- 唯一“新增驱动”是 `shim_frame_done=1'b0`，它把退役后 `HAS_DMA=0` 实例里原本悬空的网变成确定 0；R_DRET 在该实例不可达，故无功能影响（见 §5）。

---

## 3. B — 正确性 / 参数化 / 可达性

### 3.1 `HAS_DMA` 在 always 块当常量：合法

- `parameter HAS_DMA = 1` 在 `axi4_master_bridge.v:65`；`HAS_DMA` 是 elaboration-time 常量，Verilog 允许在过程块 `if` 中使用常量表达式；Vivado 2023.1 会按实例常量折叠。
- 直接证据：`xvlog` 解析 0 warning；`xelab` 默认 `HAS_DMA=1` 0 warning；W2/W4 的 xsim 日志里明确编译了 `axi4_master_bridge(HAS_DMA=0)` 并跑完（`xsim_run.log:30`、`w4_joint_run.log:35/81`）。这比“语法可过”更强：**两种参数值都实际 elaborate + 仿真过**。
- 该 always 是时钟沿触发块，不存在 latch 推断；常量分支只会被综合剪枝。

### 3.2 状态可达性（逐个 `rstate <=` 赋值点）

全文件 `rstate` 赋值只有以下 11 处（无第二 always/无 assign）：

| 行 | 源状态 | 目标 | 条件 |
|---|---|---|---|
| 637 | reset | R_IDLE | `!rst_n` |
| 676 | R_IDLE | R_PRE | `rc_rd_en` |
| 693 | R_PRE | R_IDLE | `!p_target_ok` |
| 704 | R_PRE | **R_DRET** | `HAS_DMA=1` |
| 716 | R_PRE | **R_AR** | `HAS_DMA=0`（新增 else） |
| 727 | R_AR | R_R | AR 握手 |
| 743 | R_R | R_UNPACK | R 握手 |
| 752 | R_UNPACK | R_FIN | 最后一拍最后一字节 |
| 753 | R_UNPACK | R_R | 下一拍 |
| 767 | R_FIN | R_IDLE | 无条件 |
| 790 | R_DRET | R_IDLE | `shim_frame_done` |
| 793 | default | R_IDLE | 非法状态恢复 |

因此：

- **`HAS_DMA=1`**：进入 R_AR 的唯一入口是 716 的 `else` 分支，而它只在 `HAS_DMA=0` 时可达；R_IDLE 不会直接去 R_AR。⇒ **R_AR/R_R/R_UNPACK/R_FIN 对 `HAS_DMA=1` 不可达**（综合可剪枝）。
- **`HAS_DMA=0`**：进入 R_DRET 的唯一入口是 704 的 `if (HAS_DMA=1)` 分支。⇒ **R_DRET 对 `HAS_DMA=0` 不可达**；其 `shim_frame_done` 被 tie-0 后整个分支是常量假，综合剪枝。
- `default: rstate <= R_IDLE` 仍在（793），不会因新增/恢复状态产生锁死。

### 3.3 `dma_engine` 输入端口：模块内已完全未使用

- 当前文件里 `dma_engine` 的可执行引用 = **0**；只有端口声明 `axi4_master_bridge.v:172` 和 3 处注释（527、698）以及 generate 标号名 `gen_dma_engine`（549）含该子串。
- 这不是本次修复引入的：退役提交 `8afa168` 把 R_PRE 的 `else if (dma_engine)` 改成无条件 R_DRET 后，该端口就已无消费者；本次只是把它明确成 `HAS_DMA`。
- **ELAB 影响**：`xelab` 对默认 `HAS_DMA=1` 与 W2/W4 的 `HAS_DMA=0` 均无 warning/error；Vivado 对未使用的 input 端口通常不报 warning（最多综合时静默剪枝），不会产生 ELAB 失败。
- **顶层影响**：`frame_mem_if.v:471` 仍把 `dma_engine_q` 接到该端口（现在空载，2FF 可被剪）；但 `frame_mem_if.v:502` 的 `ro_dma_req[24]` 仍用原始 `dma_engine`，所以 Lite 回读的 engine 位仍然有效、net 不悬空。⇒ **无功能影响，但存在“观测语义 vs RTL 行为”不一致**：软件写 `R_ENGINE=0` 后 `req[24]=0`，桥① 的读 FSM 仍走 DMA（因为 `HAS_DMA=1`）。这是退役的有意结果，不是本次修复的缺陷；建议改注释/文档（§8）。
- 端口注释 `axi4_master_bridge.v:172`（“0 = 桥硬件读，1 = DMA+软件读”）已与实现不符；`527–530`、`695–699` 也有同类过期表述。

### 3.4 综合/时序影响

- 对 `u_mem`（HAS_DMA=1）：新增的 4 个状态是不可达 case 臂，Vivado 会常量剪枝；netlist 应回到“退役版 + 少量死代码”，不会重新引入 `len_beats_tab` 的读锥（该表在 HAS_DMA=1 实例仍无读者，被剪）。退役位流已以 0.000/+0.004 WNS 建过，风险低。
- 对 `u_mem2`（HAS_DMA=0）：shim 分支本就不例化，R_DRET 被 tie-0 剪枝；R_AR..R_FIN 与 `3f847e3` 的绿版完全同构，绿版曾收敛。⇒ 时序上应不劣于两台已有实现；但仍需构建闸门（§6.3、§7.1）。
- 已知 Vivado 2023.1 “Mimic Skeleton” 崩溃的触发条件是**死 shim 实例/特定结构**（文件 62–64 行注释、R_PRE2 先例），不是普通不可达 case 臂；本次没有新增/删除实例，风险低但应看综合日志（§8）。

---

## 4. C — 单一驱动纪律（AGENTS #25/#34）

`AGENTS.md:182`（#25）与 `AGENTS.md:191`（#34）：同一 reg 不得被两个 always 块写；拆块后必须复核驱动归属，综合 `MDRV-1` 必须为 0。

本次复核结果：

| 信号 | 驱动 always 块 | 行 | 其它块 |
|---|---|---|---|
| `out_inc` | 写 FSM（348 起） | 356/362/371 | 无 |
| `out_dec` | **读 FSM（635–796）** | 649/762/781 | 无 |
| `rd_retire` | 读 FSM | 648/760/779 | 无 |
| `rd_retire_slot` | 读 FSM | 761/780 | 无 |
| `stat_rd_frame` | 读 FSM | 644/763/782 | 无 |
| `rd_seq_slot` | 读 FSM | 643/666/764/783 | 无 |
| `brd_wr_en/data` | 读 FSM | 651/690/765/788 等 | 无 |
| `brf_wr_en/data` | 读 FSM | 650/748、749 | 无 |

- `R_FIN`（759–768）与 `R_DRET`（775–792）是**同一个 `case (rstate)` 的两个互斥臂**，都在 635–796 的同一个 always 块内；同一拍只会命中一个状态，综合成一个寄存器多路选择，**不是多驱动**。
- `out_dec` 的块顶默认清零（649）也在同一 always，符合该块注释（241–251）声明的“read FSM 独占 out_dec”。
- `full_bit/full_bit_q` 的清零由 `rd_retire` 消费（229–232），`rd_retire` 仍是单驱动；`stat_outstanding` 由 `out_inc/out_dec` 消费（252–258），也无第二驱动。
- 结论：**C 通过**。仍需在综合后确认 `MDRV` 计数为 0（这是纪律要求，不是本次发现的缺陷）。

---

## 5. D — 语义等价（HAS_DMA=0 vs `3f847e3`）

### 5.1 恢复代码与退役前逐字节相同

用脚本按 `begin/end` 配平提取四个状态块，与 `git show 3f847e3:…` 比较：

| 状态 | 当前行 | 3f847e3 行 | 逐字节 |
|---|---|---|---|
| R_AR | 723–729 | 712–718 | **完全相同**（含缩进/尾随空白） |
| R_R | 731–745 | 720–734 | **完全相同** |
| R_UNPACK | 747–757 | 736–746 | **完全相同** |
| R_FIN | 759–768 | 748–757 | **完全相同** |

R_PRE 的 6 条硬件分支赋值：当前 711–716 与 3f847e3 的 703–708 **逐字相同**（`r_slot/r_len/r_beats/r_beat/dbg_rd_slot/rstate<=R_AR`）。

### 5.2 除 `shim_frame_done` tie-0 外的全部差异

| 差异 | 当前 | 3f847e3 | 对 HAS_DMA=0 实际实例的影响 |
|---|---|---|---|
| `HAS_DMA=0` 时 `shim_frame_done` | 574 行 `assign …=1'b0` | **无驱动**（`gen_no_dma` 未接） | 3f847e3 中 R_DRET 对该实例不可达（`dma_engine` 顶层 tie 0），悬空网从未被采样；tie-0 只是把 X 变确定 0，**无行为差** |
| R_PRE 引擎选择 | `else if (HAS_DMA)`（694） | `else if (dma_engine)`（~701） | u_mem2 的 `.dma_engine(1'b0)`（`aurora_mem_bridge.v:956`）⇒ 两者都走硬件分支，**等价** |
| `gen_dma_engine` 的 shim 门控/合并 | 555/563–564 退役形态 | `dma_engine & s_tvalid`、`brf|shim` | `HAS_DMA=0` 时该 generate 分支根本不例化，**无影响** |
| `gen_no_dma` 其余 5 个输出 | 569–573 | 568–572 | 逐字相同 |
| `HAS_DMA=0` + `dma_engine=1` 的非实际组合 | 走硬件路径 | 走 R_DRET（且 `shim_frame_done` 悬空→挂死） | 顶层 u_mem2 恒 0；TB 也 tie 0/不接。该组合本来就没有 shim、绿版本身就是坏的；当前实现反而更确定 |

### 5.3 仿真证据

- W2（`mem_bridge_tb`，HAS_DMA=0）：585 帧，`rd_frame=585`，`rd_beats=8202`，`0 errors`；T1/T2/T3/T4/T5/T6 全 PASS。恢复的 R_AR→R_R→R_UNPACK→R_FIN 路径被 585 帧真实走过。
- W4（`w4_joint_tb`，两个 HAS_DMA=0 实例）：A/B 各 `rd=148`，P1/P2/P3/P4/P5 全 PASS，负控按预期死锁 ⇒ 测试非空转。
- `bridge_dma_tb`（HAS_DMA=1）：P1/P2/P3 PASS，证明 DMA 路径退休仍成立。

**D 结论：HAS_DMA=0 实例恢复后的可观测行为与 3f847e3 一致；未找到任何信号级差值（除 tie-0 这个“把未采样悬空网变确定”的改进）。**

---

## 6. E — 桥① 是否只需 DMA；R_DRET 与 R_FIN 的结算等价性

### 6.1 桥① 没有依赖 `brf_*` 的旁路

| 检查点 | 桥①（HAS_DMA=1）实际来源 | 是否有 R_FIN 专属依赖 |
|---|---|---|
| 读字节流 `rf_wr_en/data` | `gen_dma_engine`：`assign rf_wr_en = shim_rf_wr_en`（563–564） | 否；`brf_*` 无读者 |
| 读描述符 `rd_wr_en/data` | `assign rd_wr_en = brd_wr_en`（566–567）；`brd_*` 由 R_PRE 目标失败 / R_DRET 驱动 | 否；R_DRET 也驱动 |
| `full_bit` 退休 | `rd_retire/rd_retire_slot`（229–232）由 R_DRET 驱动 | 否；R_DRET 等价 |
| `out_dec` / `stat_outstanding` | R_DRET 驱动 `out_dec`（781），252–258 消费 | 否；R_DRET 等价 |
| `rd_seq_slot` | R_DRET 783 | 否；见 6.2 |
| `stat_rd_frame` | R_DRET 782 | 否 |

`gen_dma_engine` 里 `rf_wr_en` 已不再 OR `brf_wr_en`，且 R_UNPACK 对 HAS_DMA=1 不可达 ⇒ `brf_wr_en ≡ 0` 是结构可证的，不是“看起来为 0”。

### 6.2 R_DRET vs R_FIN 结算字段逐项对比

| 字段 | R_FIN（759–768） | R_DRET（775–792） | 等价？ |
|---|---|---|---|
| `rd_retire` | 1 | 1 | 是 |
| `rd_retire_slot` | `r_slot` | `dma_req_slot` | 是（两者都 = R_PRE 的 `p_eff`） |
| `out_dec` | 1 | 1 | 是 |
| `stat_rd_frame` | +1 | +1 | 是 |
| `rd_seq_slot`（SEQ） | `rd_seq_slot + 1` | `dma_req_slot + 1` | 是，见下方证明 |
| `brd_wr_en` | 1 | 1 | 是 |
| `brd_wr_data` | `{1'b0, r_len, r_slot}` | `{1'b0, dma_req_len, dma_req_slot}` | 是（`r_len/r_slot` 与 `len_tab[p_eff]/p_eff` 同源） |
| 额外 | — | `dma_req_new<=0`、`dbg_rd_beats+1` | 非退休字段；`dbg_rd_beats` 是“按帧”计数（R_FIN 路径按拍在 R_R 计），仅调试语义差，绿版 DMA 路径本来就如此 |

**SEQ 等价性证明（行号级）：**

1. `p_eff = pre_eff`，`pre_eff` 在 R_IDLE 锁存为 `c_eff`（608、674）。
2. 对 SEQ 命令（`pre_rnd=0`），`c_eff = rd_seq_slot`（608）；R_PRE 把 `dma_req_slot <= p_eff`（701）。
3. 关键：R_IDLE 的扫描自增（665–666）与命令接收（667–677）同拍时，对 SEQ 不会同时发生：
   - `rc_rd_en` 要求 `seq_ok = full_bit_q[rd_seq_slot] | (stat_outstanding==0)`（618、620）；
   - 扫描自增要求 `!full_bit_q[rd_seq_slot] && stat_outstanding!=0`（665）；
   - 两者条件互斥 ⇒ 接收 SEQ 命令的那一拍 `rd_seq_slot` 不变。
4. 进入 R_PRE/R_DRET 后，`rstate != R_IDLE`，扫描不再执行；R_FIN 对 HAS_DMA=1 不可达，R_DRET 之外无第二写者 ⇒ `rd_seq_slot` 在 R_DRET 全程冻结。
5. 所以 frame_done 时 `dma_req_slot ≡ rd_seq_slot`，`dma_req_slot + 1 ≡ rd_seq_slot + 1`；8 位回绕也一致。

这正是绿版 DMA 路径一直在用的写法；本次修复没有改 R_DRET。

### 6.3 残余风险（不是本次修复的缺陷，但上板判据必须带上）

1. **R_DRET 无超时**（775–792 唯一出口 `shim_frame_done`）：DMA 少一拍 TLAST / shim 被复位 / 长度不符时，桥① 会永久停泊，`dma_req_new` 保持 1。该结构在绿版同样存在（审计 §5 H6）。本次修复未触碰。
2. **桥① 变成“DMA 服务强依赖”**：固件 `g_dma_mode=0` 时主循环不调用 `serve_dma_once`（`sw/j3_soft/src/main.c:412–413`）；此时桥① 收到读命令会停在 R_DRET，直到按 `'d'` 打开服务（电平请求，可恢复）。`'d'` 再按一次会关掉服务 ⇒ **不要按两次**。这是退役的设计后果，不是本次修复引入。
3. **`cfg_mode` 必须是 SEQ 才有自动读命令**：`aurora_mem_bridge.v:323–327`；`M/A/B` round 收尾把 `cfg_mode` 留在 RND（审计 §5 H1），ping 期间不会自动发读。`'d'` 会顺手置 SEQ（`main.c:443–444`），所以“先 `'d'` 再 ping”是正确序列。
4. **`req[24]` 观测语义过期**：软件仍能读到 engine 位，但 RTL 已不看它（§3.3）。不要再用 bit24 判断桥① 实际读引擎。
5. **`dbg_rd_beats` 语义**：DMA 路径按帧 +1（784），硬件路径按 AXI 拍 +1（742）；跨配置比较该计数器会误判，非功能问题。

---

## 7. F — 给上板判据的预测

> 前提：新位流必须由当前工作树（bridge blob `7fe880e`）重建，不能用旧 DCP/旧 bit。下面“观察手段”尽量用**现有** Lite `'U'` 与**现有 ILA3**（`scripts/build_debug.tcl:241–265` 已把 `dbg_mem2_wm/dbg_mem2_rd_frm/dbg_mem2_ost` 挂进 u_ila_3），不需要改 RTL。

### 7.1 构建闸门（先过这个，否则预测无意义）

1. 综合/实现日志：`MDRV-1`/`8-6859`/`8-6858` = 0；无 2023.1 “Mimic Skeleton” 崩溃；WNS/WHS ≥ 0（门限脚本会拒）。
2. 确认综合读的是 `7fe880e` 版本（`report_property`/文件 mtime/构建日志），排除坑 #35 DCP 缓存。
3. 可选：`report_cell u_mem2/u_bridge/rstate_reg[*]` 或 `get_nets u_mem2/u_bridge/m_axi_arvalid`，确认 HAS_DMA=0 实例保留了 R_AR 状态机（不是被误剪）。

### 7.2 上板序列（严格按此，避免 H1 污染）

上电 → 串口发 **一次** `'d'`（回显应为 `DMA`，`'U' mode=1`）→ **不要先跑 M/A/B round** → `ping -n 4 <FPGA_IP>` → 再读 `'U'`。若要跑 round，ping 前补发 `'S'`（回 SEQ）或再确认 `cfg_mode=SEQ`。

### 7.3 可验证预测（至少 3 条；按“硬/软”排序）

| # | 预测 | 观察手段 | 判据/阈值 |
|---|---|---|---|
| P1（最关键，PC 侧） | 4/4 回包 | PC `ping -n 4`；网卡收包 delta | 4/4，0% loss，delta +4（若栈重发 ARP 则另有 1 帧 ARP，但 ICMP 回包仍 4） |
| P2（桥①，现有 `'U'`） | `WM_WR` 与 `WM_RD` 各 +N | `'U' wmwr / wmrd`（0x08/0x0C） | N = 本轮到线出向帧数（通常 4；含 ARP 则 5）；`wmrd` 必须真的前进（上次失败轮 `WM_RD` 冻结） |
| P3（桥① DMA 退休） | `req` bit25 回到 0；桥① outstanding 回 0；`emit` 更新到最后一帧 | `'U' req`（0x34，bit25）、`'U' emit`；桥① outstanding 看 ILA3 `dbg_mem_ost` | 静默窗内 bit25=0；`dbg_mem_ost` 回 0；无“请求挂死”；slot 递增 |
| P4（桥②，现有 ILA3） | `dbg_mem2_wm` +N，`dbg_mem2_rd_frm` +N，`dbg_mem2_ost` 回 0 | u_ila_3（ui_clk；`build_debug.tcl:260–263`） | `rd_frm` 增量 = `wm` 增量（允许 ±1 采样边界）；`ost` 不得停在 256 |
| P5（泵B，现有 ILA0） | `dbg_prev_wr`（= `pump_rev_wr`）+N | u_ila_0（`build_debug.tcl:103`） | 与 P4 的 `rd_frm` 同量级；若 P4 涨而 P5 不涨 ⇒ 断在 mem2_rd_data→泵B 写侧 |
| P6（四档） | 标准四档回归 PASS | PC 四档脚本（`udp_verify_ddr.py` 或 prj11 对应版本）；`DDR_VERIFY: PASS` | 链路 ping 20/20 + 基础/槽深/稳定全过；前提仍是 `'d'` 已开、`cfg_mode=SEQ` |
| P7（判别性对照） | 新旧位流的差只在桥② | 同一 `'d'`→ping 序列，分别跑退役 `3aa600aa`/`0ecb8438` 与新位流，读 ILA3 | 退役：`dbg_mem2_wm` 可能涨但 `dbg_mem2_rd_frm` **冻结**、`ost` 可能升到 256、ping 0/4；新：`rd_frm` +N、`ost` 回 0、ping 4/4。**桥① `wmwr/wmrd` 两者应相同** |

### 7.4 失败矩阵（新位流仍失败时，30 秒定位）

| 现象 | 最可能断点 | 下一步 |
|---|---|---|
| `'U' wmrd` 不涨（`wmwr` 涨） | 桥① 没收到读命令：`cfg_mode` 还在 RND / DMA 服务没开 / 命令 FIFO 空 | 发 `'S'`、确认 `'d'` 只按一次、看 `req[25]` |
| `wmrd` 涨但 ILA3 `dbg_mem2_wm` 不涨 | Aurora RX / `axis_word_unpack` / 桥② 写侧（第二跳上游），不是本次修复目标 | 查 `link_ok/channel_up_b`、`unpack_en`、`mem2_wr_frame` |
| `dbg_mem2_wm` 涨但 `dbg_mem2_rd_frm` 不涨 | 桥② 读 FSM 仍停（构建没带上修复 / `HAS_DMA` 实例接错 / `u_mem2` 的 `mem2_rd_req` 没来） | 查构建 blob、`mem2_rd_req`、`mem2_rd_busy`、`R_AR` 是否在网表 |
| `dbg_mem2_rd_frm` 涨但 ILA0 `dbg_prev_wr` 不涨 | mem2_rd_data→泵B 写侧（FIFO/满/复位） | 查 `mem2_rd_en`、`pump_rev_wr/drop`、`~aurora_rst` |
| `dbg_prev_wr` 涨但线上无帧 | 泵B 读侧 / `cmd_takeover` / 末级 mux / PHY | 查 `pump_rev_en`、`cmd_takeover`、`rgmii_tx_en_o`、`link_ok` |
| 4/4 但偶发丢 1 帧 | R_DRET 超时缺失（H6）或 DMA/服务竞争 | 看 `req[25]` 是否卡 1；这是绿版已有风险 |

> **重要边界**：本次修复只恢复“桥② 硬件读 FSM + rf 数据源”。它**不能**修复 H1（测试序列使读侧根本不启动）、H3（Aurora/泵B/末级 mux）、H6（R_DRET 无超时）或构建缓存问题。上表 P7 的“桥① 两版相同、只有桥② 变”是判定本次修复是否按预期生效的最干净证据。

---

## 8. G — 是否发现修复缺陷；最小修正建议

**未发现功能性缺陷。** 不需要行号级的 RTL 代码修正；本次修复满足“完备、最小、语义等价”。以下 3 条为非阻塞项，建议在提交/上板前顺手处理，但不属于“修复缺陷”：

1. **注释过期（`axi4_master_bridge.v:168–172、527–530、695–699`）**
   - 端口注释仍写“0 = 桥硬件读，1 = DMA+软件读”，实现已改为 `HAS_DMA` 决定，且 `dma_engine` 无消费者。
   - 最小改法：把 172 行注释改成“遗留端口；本模块已不使用（HAS_DMA 决定读引擎）”，把 527–530 的 “engine=1” 改 “HAS_DMA=1”，把 695–699 的“已删除”改“在本实例不可达”。**只改注释，不动逻辑。**

2. **`sim/bridge_dma_tb.sv` 的 P1 标签过期（第 5 行 vs 294–323 行）**
   - 第 5 行写 “P1 engine=0 (桥硬件读)”，但 294 行已改成 DMA 路径，P1 实际调 `serve_dma` 走 shim；该 TB 对本次恢复的 R_AR/R_R/R_UNPACK/R_FIN **零覆盖**（它始终 `HAS_DMA=1`，见 113 行）。
   - 最小改法：把第 5 行标签改为“P1 engine=0（DMA 路径，HAS_DMA=1）”；若要补覆盖，另加一个 `HAS_DMA(0)` 实例或明确注明“硬件读路径由 W2/W4 覆盖”。**不改 RTL。**

3. **构建闸门（不是代码改动）**
   - 新位流必须来自 `7fe880e`，综合/实现日志 `MDRV=0`、WNS/WHS ≥ 0、无 2023.1 Mimic Skeleton 崩溃；否则“预测”不成立。
   - 可选独立改动（不要塞进本次最小修复）：给 R_DRET 加超时/看门狗（审计 H6），解决桥① 单笔 DMA 丢失后的永久停泊。

---

## 9. 附录：复现命令与证据索引

```powershell
# 1) 工作树事实
git -C D:\FPGA status --short
git -C D:\FPGA hash-object prj/project_11/rtl/axi4_master_bridge.v   # 7fe880e…
git -C D:\FPGA diff --numstat -- prj/project_11/rtl/axi4_master_bridge.v
git -C D:\FPGA diff --check

# 2) 与退役前逐块比较（脚本，临时目录）
python review_bridge.py   # 4 个状态块 exact=True；驱动集合对比

# 3) 语法/elaborate（临时目录，不改仓库）
xvlog -sv D:\FPGA\prj\project_11\rtl\axi4_master_bridge.v D:\FPGA\prj\project_11\rtl\dma_rd_shim_v2.v
xelab -debug typical axi4_master_bridge -s rev_h1
```

证据文件：

- `prj/project_11/sim/xsim_run.log:30`（`Compiling module work.axi4_master_bridge(HAS_DMA=0)`）、`:57–58`（`rd_frame=585`、`rd_beats=8202`）、`:62`（PASS）
- `prj/project_11/sim/w4_joint_run.log:35–38`（HAS_DMA=0 两实例编译）、`:111–113`（A/B `rd=148`，PASS）
- `prj/project_11/sim/bdma_run.log`（`BRIDGE_DMA_TB: PASS`，P1/P2/P3）
- `prj/project_11/out/evidence_2026-10-17/rtl_audit_204519.md`（退役 5 处逐 hunk、H1–H6）
- `prj/project_11/scripts/build_debug.tcl:241–265`（ILA3 已含 `dbg_mem2_wm/rd_frm/ost`）
- `prj/project_11/rtl/aurora_mem_bridge.v:772/917/956`（u_mem 默认 HAS_DMA=1；u_mem2 HAS_DMA=0 且 `dma_engine=1'b0`）
- `prj/project_11/rtl/frame_mem_if.v:439/471/502`（HAS_DMA 透传、dma_engine 2FF、`ro_dma_req` bit24）
- `prj/project_11/sw/j3_soft/src/main.c:412–413/436–444`（`'d'` 与 DMA 驻留服务）

---

**最终结论：本次修复正确、最小、完备；A/B/C/D/E 全部通过（B 的 `dma_engine` 未使用是退役的既有结果，非本次引入）；F 的预测与失败矩阵见 §7。**
