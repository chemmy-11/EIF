# R3C 探针方案复核（round3c：lite AXI 楔死观测 + S2MM 写引擎 GO/commit 观测）

- 产出：rtl-auditor（独立审计，只读；未碰板、未启动 Vivado 工程/综合/实现；Lead 的 round3c 综合在本文件写作期间进行中）
- 快照时间：2026-10-19 12:02–12:10（RTL/脚本仍在 Lead 手中变动；行号与 hash 均按该快照）
- 依据等级：L4 定案 / L3 板证 / L2 对照+代码或同版本实物 / L1 相容假说 / L0 猜测（AGENTS §6a）。本文件所有"判定"行注明等级；未闭环的一律写"假说/未验证"。
- 复核对象（Lead 已落地的实际方案，非任务书中的原 [1] 文本）：
  - `rtl/axi_lite_regs.v` 新增纯观测输出 `dbg_o[35:0]`（BD module ref 端口）
  - `scripts/create_bd_b.tcl` 新增 BD 外部端口 `dbg_l_bus[35:0]`
  - `rtl/aurora_mem_bridge.v` 顶层 alias + `u_mb_ctrl.dbg_l_bus`
  - `scripts/build_debug.tcl` / `build_synth_only.tcl` 新增 `u_ila_4 @init_clk`（probe0=36b、probe1=1b 触发）与 `u_ila_5 probe5=7b`
  - `rtl/frame_mem_if.v`、`rtl/axi4_master_bridge.v` 新增 mark_debug 别名（feed ILA5 probe5）

---

## 0. 结论速览

| 项 | 判定 | 等级 | 依据 |
|---|---|---|---|
| 原计划[1]（BD 内 `mark_debug` 别名 + 顶层按 net 名搜） | **不可靠，应弃用**（不是"物理上不可能"；否决理由需精确表述，见 §2.1） | L2（综合日志+工具语义） | `build_r2_synth.log:494/495/1108-1128/1227-1242`；UG835/UG894 |
| 现方案「BD 端口 `dbg_l_bus` + 顶层 alias」 | **可行**：BD regen 产物、OOC 新 wrapper、OOC 真综合均已核实 | L2（同版本实物+日志） | §2.2 |
| `u_ila_4 @init_clk` 时钟/域归属 | **合法**（全部探针在 aclk=init_clk 同域；仅 `rst_user_n` 为 2FF 同步后信号） | L2（代码+BD 时钟连接） | §3.1 |
| `u_ila_4` 位图/解码 | 基本正确；**0x34/0x40/0x44/0x0C/0x48/0x4C 六个偏移逐项核对通过**；但地址解码位在 `!valid` 时也随总线变化，判读需配合 valid 位 | L2 | §3.2 |
| `u_ila_4` 触发 `dbg_l_stuck_or` | **可抓 4 类卡死，漏 3 类**（AR 从未到 / AW-W 半锁存 / BVALID 未消费的"静默冰封"）；必须配 `R2_SNAPSHOT_ONLY` 楔死后快照 | L2（静态逻辑）+L1（漏测形态） | §3.3、§3.4 |
| `u_ila_5 probe5` | **可行**（`dbg_net` 按 leaf-name 解析，HAS_DMA=1 分支唯一）；触发 `go_ui==1` 必须在板验序列**之前** arm 才能抓到边沿 | L2（代码）+L1（上板行为） | §4 |
| ILA5 300MHz +7b | 时序风险**中低**：round3b 基线 +0.004 仅 4ps，BD regen 已换基线；不达标优先裁 probe5 的 `state[2:0]`（ILA3 已同源） | L1 | §4.3 |
| ILA0/ILA3 不动 | 合理（既有判据/时序余量） | L2 | — |

**高风险项置顶**：①`one_net dbg_l_stuck_or` 与 `bus_nets dbg_l_bus 36` 依赖顶层 alias 名不被综合改写（本轮已按 Lead 决定"跑完再看"，失败兜底=probe1 取 `[lindex $nets4 35]`，零名字依赖）；②`u_ila_5` 若在"GO 已翻"之后才 arm，触发为**电平即时触发**，只能当静态快照用，不能当边沿证据（见 §4.2）；③本轮 RTL 遗留 `rst_user_n` 2FF 缺 `ASYNC_REG`（规范缺口，round3d 必改，见 §6）；④**【已实测】`dbg_net dbg_wd_go_ui` 在 round3c 第 1 次构建中解析失败并 abort（§2.5），含最小修复代码**——第 2 次重试若未改脚本会同样失败。

---

## 1. 复核对象与快照

### 1.1 文件 hash（git blob 前 8 = 本项目口径；附文件 SHA256 前 8）

| 文件 | git blob（快照） | 文件 SHA256 前 8 | 备注 |
|---|---|---|---|
| `rtl/axi_lite_regs.v` | `631d45ec` | `FECCEC0F` | round3c 新增 dbg_o（HEAD 基线 `d5d16d46`=fix2） |
| `rtl/aurora_mem_bridge.v` | `9dd02789` | `1AB8953A` | 顶层 alias + u_mb_ctrl.dbg_l_bus（HEAD 基线 `6150212e`） |
| `rtl/axi4_master_bridge.v` | `d09cc155` | `ED8D7F59` | 12:08:08 修正 `dbg_wd_go_ok` 声明位置（generate 块首，Verilog-2000 合规）；HEAD 基线 `c92c20c7` |
| `rtl/frame_mem_if.v` | `064d26ac` | `7D1DE3A6` | probe5 三别名；HEAD 基线 `96d5b136` |
| `scripts/create_bd_b.tcl` | `faca8052` | `3F102A3E` | +dbg_l_bus BD 端口 |
| `scripts/build_debug.tcl` | `5f9e12c8`（修复后） | `1A643EC1` | +ILA4、ILA5 probe5、`dbg_net`；12:17 按本审计建议修 `dbg_net`+probe1 兜底（修复前 `ebc7cd85`） |
| `scripts/build_synth_only.tcl` | `ecc1aa31`（修复后） | `81382DC1` | 同上（两份同步；修复前 `ffb1d976`） |

### 1.2 Hub 产物（BD regen 已跑，exit 0；Lead 12:03–12:05）

- `out/r3c_regen_bd.log`：`BD_STEP: round3c dbg_l_bus[35:0] connected`；`BD_DONE: wrapper=.../hdl/mb_ctrl_wrapper.v top=aurora_mem_bridge`。
- `vivado/prj11.gen/sources_1/bd/mb_ctrl/synth/mb_ctrl.v:446,518,765`：`module mb_ctrl` 端口表含 `dbg_l_bus`；`output [35:0]dbg_l_bus;`；`assign dbg_l_bus[35:0] = axi_lite_regs_0_dbg_o;`。
- `vivado/prj11.gen/sources_1/bd/mb_ctrl/hdl/mb_ctrl_wrapper.v:63,135,282`：wrapper 端口与例化连接同步。
- `vivado/prj11.gen/sources_1/bd/mb_ctrl/ip/mb_ctrl_axi_lite_regs_0_0_10/synth/mb_ctrl_axi_lite_regs_0_0.v:103,172,219`：module-ref wrapper 新增 `output wire [35:0] dbg_o;` 与内部 `.dbg_o(dbg_o)`。
- `vivado/prj11.runs/mb_ctrl_axi_lite_regs_0_0_synth_1/runme.log`：12:05:24 起为**真综合**（`__synthesis_is_running__`、RTL Component Statistics），**不是 IPCACHE 复用旧 DCP**。
- BD 地址图不变（regen 日志）：lite `0x44A0_0000`、DMA `0x44A1_0000`、UART `0x4060_0000`。
- **12:23 attempt-3（apply §2.5 修复后）**：`SYNTH_STATUS: synth_design Complete!`、`ILA5_PROBE5: 7 nets`、`ILA4_CLK_NET: init_clk`、`ILA4_PROBES: probe0=36 + probe1=1`、`SYNTH_ONLY_DONE`；`pre_impl_debug.dcp` 已更新（12:23:32）。**4 核 debug core 创建成功** ⇒ 本轮探针方案（BD 端口 + 顶层 alias + ILA4/ILA5）在 2023.1 上**集成面闭环 [L2]**。实现/时序结果由 Lead 本轮构建给出（本审计未等 impl 完成）。

---

## 2. 原计划[1]复核：BD module-ref 内 `mark_debug` + 顶层按 net 名搜

### 2.1 综合日志证据的精确解读（L2）

`out/archive/b31b_r2_2026-10-19_round3b/build_r2_synth.log`（round3b，与 round3c 同构）：

- `:494-495` `synthesizing module 'mb_ctrl_axi_lite_regs_0_0' [.../mb_ctrl_axi_lite_regs_0_0_stub.v:6]` —— 顶层 synth_1 综合时把 module ref 当 **stub/black box**。
- `:1108-1128` `Report BlackBoxes` 列 `mb_ctrl_axi_lite_regs_0_0` = 1 实例。
- `:1227-1242` `INFO: [Project 1-454] Reading design checkpoint ... mb_ctrl_axi_lite_regs_0_0.dcp for cell 'u_mb_ctrl/axi_lite_regs_0'` —— **`open_run synth_1` 时会把 OOC DCP stitch 进设计**（在 open_run 完成前，`:1372` 的 `open_run: Time` 之前）。
- `:1373-1376` `ILA0_CLK_NET / ILA3_CLK_NET / ILA5_PROBES` —— ILA 创建发生在 open_run **之后**。

因此严格表述：**"synth_1 综合阶段看不见 module ref 内部 net"是事实；"open_run 后也一定看不见"则未被日志证明** —— OOC netlist 会被 stitch 进来，内部 net 在原理上可能存在。原计划被否决的**真正不可靠点**是三个未验证假设：

1. **`get_nets <leaf>` 默认只搜 current_instance（顶层）**（UG894 "By default, the get_* commands only return objects from the top-level of the design"；UG835 `get_nets`：`-hierarchical` 才 "Search level-by-level in current instance"）。案例脚本 `one_net`/`bus_nets` 全部是裸名 → 对 BD 内 net **必落空**，与是否 stitch 无关。
2. **OOC synth 的 net 名不保证**：module ref 由独立 run `synth_design -top mb_ctrl_axi_lite_regs_0_0 -mode out_of_context` 生成（`.../mb_ctrl_axi_lite_regs_0_0.tcl:...`），`mark_debug` 别名在 flatten/rename 后是否保名没有本工程实证（既有先例全部是**顶层 RTL** alias，见 `aurora_mem_bridge.v` 的 `dbg_*`）。
3. **在 OOC-stitch cell 内部插入 debug core 属未验证流程**：官方文档只覆盖"module ref + mark_debug + BD 内 Debug Hub 的 insertion 流"（UG909 DFX 章节，2025.1），本工程是 `open_run synth_1` 后脚本 `create_debug_core`+`connect_debug_port`（top-level 流程），二者组合没有本版本实证。

**结论**：弃用原计划正确。代价对比：BD 端口方案 = 顶层 36 根走线 + 1 个 BD 外部端口（已落地），换取**端口级确定性**，远优于依赖 3 个未验证假设。

### 2.2 现方案可行性证据（L2）

见 §1.2。补充：

- `create_bd_b.tcl:191-197`：`create_bd_port -dir O -from 35 -to 0 dbg_l_bus` + `connect_bd_net [get_bd_pins axi_lite_regs_0/dbg_o] $dbgport`（UG835 `create_bd_port`/`connect_bd_net` 用法正确）。
- `rtl/aurora_mem_bridge.v:708` `wire [35:0] dbg_l_bus_w;`；`:784` `.dbg_l_bus(dbg_l_bus_w)`；`:1473-1474` 顶层 `(* mark_debug *) wire [35:0] dbg_l_bus = dbg_l_bus_w;` 与 `dbg_l_stuck_or = dbg_l_bus_w[35]`。
- 与既有 12 组顶层 mark_debug alias 完全同型（`dbg_mem_*`/`dbg_s2mm_*`，见 `aurora_mem_bridge.v:1377-1464`）——这些 alias 在 round2f/round3/round3b 均被 `one_net`/`bus_nets` 成功解析并进入 ltx（wed2 日志 `R2CAP_PROBE(UI/USER)` 逐项列出），**mark_debug 保名流程有本工程 3 轮实证**。

### 2.3 风险表（含兜底方案）

| # | 风险 | 等级 | 判据/后果 | 兜底 |
|---|---|---|---|---|
| R1 | 顶层同一信号双 alias（`dbg_l_bus[35]` 与 `dbg_l_stuck_or`）被综合合并/改名 `_1` → `one_net dbg_l_stuck_or` 或 `bus_nets dbg_l_bus` error | **风险消除（12:23 实测）** | Lead 已改用 `[lindex $nets4 35]` 作为 probe1（零名字依赖）；attempt-3 日志 `ILA4_PROBES: probe0=36 ... probe1=1` 证明成功 | 后续若再需要单名 alias，保留 `one_net` 失败 fallback 到 bus bit35 的写法 |
| R2 | ILA4 时钟 `get_nets init_clk` 命中 0 或多 | L1 | 0→fallback `-hier -filter NAME=~*init_clk`；>1→`connect_debug_port` 传 list 报错（fail-fast，无静默错误） | 建议显式 `if {[llength $c100_net] != 1} { error ... }`（当前 12:02 版本只在 ==0 时 fallback；多匹配会报错但提示不清晰） |
| R3 | OOC/IP cache 复用旧 netlist（坑 #35） | L2 已排除 | `..._10/synth/*.v` 带 `dbg_o`；`runme.log` 为真综合；`MODULE_REF_RESET: mb_ctrl_axi_lite_regs_0_0_synth_1` 已在 r3c_synth.log:37 出现 | 构建后核对 OOC DCP 时间戳 > RTL mtime（坑 #35 判别法） |
| R4 | BD regen 使 OOC run 名/编号变化（旧 `_9`→新 `_10`） | L2 已覆盖 | `get_runs -filter {NAME =~ mb_ctrl_*}` 命中；当前日志已见 MODULE_REF_RESET | 若新增 run 名不含 `mb_ctrl_` 前缀则 reset 会漏——目前命名规则未变 |
| R5 | XSA/地址图 | L2 已核 | 新端口非 AXI；地址 0x44A00000/0x44A10000 不变；`write_hw_platform` 在 bit 成功后执行（`build_debug.tcl:309`） | 板验/固件不依赖新端口，旧 XSA 亦可用 |
| R6 | ILA5 probe5 的 4 个嵌套 net 名（`dbg_net`）解析失败 | **已实测命中 → 已修复 → 已闭环（12:23 attempt-3 PASS）** | 实测失败于 `dbg_net dbg_wd_go_ui: cands=1 hit=0`；apply §2.5 修复后 `DBG_NET_FUZZY(...)` 4 条全部命中并 `ILA5_PROBE5: 7 nets` | 修复代码见 §2.5；根因=generate 块内 net 名 `<inst>/<gen>.<net>` 的 `.` 分隔 |
| R7 | 300MHz ILA5 多 7b + BD regen 换基线 → WNS 跌破 0 | L1 | 门限拒写 bit（`build_debug.tcl:299-314`） | 先裁 probe5 的 `state[2:0]`（ILA3 已同源）→ 4b；ILA3 深度已到 1024 下限（坑 #67），不能再降 |

### 2.4 构建前/后检 checklist（建议 Lead 用日志 grep）

构建中/后必须看到的 marker（任一缺失即异常）：

```
MODULE_REF_RESET: mb_ctrl_axi_lite_regs_0_0_synth_1   # OOC 不缓存旧网表
SYNTH_STATUS: synth_design Complete!
ILA4_CLK_NET: init_clk                                 # 时钟解析成功
ILA4_PROBES: probe0=36 (lite AXI/fsm/mbox/reset/stuck[35:0]) + probe1=1 ...
ILA5_PROBE5: 7 nets (go_ui/ack_ui/intr_ui/go_ok/state)
ILA5_PROBES: tdata64=64 tkeep8=8 + tvalid/tready/tlast + probe5=7
WNS_GATE: >=0 / WHS_GATE: >=0 / W5_BUILD_OK / DBG_BUILD_DONE
（失败形态：net not found / dbg_net ... / invalid command name）
```

ltx 期望（4 核）：ILA0 probe0=101+probe1=9、ILA3 probe0=152、ILA5 probe0=64+probe1=8+probe2/3/4=1×3+probe5=7、ILA4 probe0=36+probe1=1。板验脚本的 `R2CAP_EXPECT_PROBE_TOTAL=5` 等旧断言需按 4 核更新（另见 task-2 的 r3c_cap.tcl）。

### 2.5 【本轮实测更新 2026-10-19 12:14】第 1 次 round3c 综合的失败点与最小修复

**事件**（只读复核 Lead 物证）：

- `out/r3c_synth_2364.backup.log`（attempt-1，pid 2364）：`:1619 SYNTH_STATUS: synth_design Complete!`、`:1739 open_run: Time ...`、`:1740/1742 ILA0_CLK_NET: user_clk / ILA3_CLK_NET: ui_clk`，随后
  `:1743 dbg_net dbg_wd_go_ui: not uniquely found (cands=1 hit=0)`，
  `:1744-1754` 栈回溯 → `(file ".../scripts/build_synth_only.tcl" line 232)` → 进程退出。
- `scripts/pre_impl_debug.dcp` 时间戳仍为 0:13:15（未被本次写）⇒ **失败发生在 debug core 创建前，无产物**。
- 成因：`dbg_net` 只接受 "leaf 名精确等于 token" 或 "`token_[0-9]+$`"；本次 `cands=1`（全设计唯一一个含 token 的 net）但 leaf 名被综合改成了非 `_N` 形态 ⇒ 两级匹配都失败。**这正是 §2.3 R6 预警的形态**，且 `cands=1` 反过来证明"`frame_mem_if` 双实例/`HAS_DMA` 分支唯一性"假设成立。

**最小修复（两份 build 脚本的 `dbg_net` 同改；build_synth_only.tcl 与 build_debug.tcl）**：

```tcl
proc dbg_net {token} {
    set cands [get_nets -hier -quiet -filter "NAME =~ *${token}*"]
    set exact {}
    foreach n $cands {
        set ln [lindex [split [get_property NAME $n] /] end]
        if {$ln eq $token} { lappend exact $n }
    }
    if {[llength $exact] == 1} { return [lindex $exact 0] }
    if {[llength $exact] > 1} { error "dbg_net $token: [llength $exact] exact matches" }
    # ★round3c 实测修复：全设计唯一候选就直接用（token 足够独特），并打印实际名留痕
    if {[llength $cands] == 1} {
        set n [lindex $cands 0]
        puts "DBG_NET($token): [get_property NAME $n]"
        return $n
    }
    set hit {}
    foreach n $cands {
        set ln [lindex [split [get_property NAME $n] /] end]
        if {[regexp "${token}[._][0-9]+\$" $ln]} { lappend hit $n }   ;# 放宽后缀
    }
    if {[llength $hit] == 1} { return [lindex $hit 0] }
    error "dbg_net $token: not uniquely found (cands=[llength $cands] hit=[llength $hit])"
}
```

**同时一次改到位的 ILA4 probe1 兜底（R1）**：

```tcl
set n4trig [get_nets -quiet [list dbg_l_stuck_or]]
if {[llength $n4trig] != 1} { set n4trig [lindex $nets4 35] }   ;# 同网：bus bit35
connect_debug_port u_ila_4/probe1 [list $n4trig]
```

**为什么这样改是安全的**：`go/ack/intr/go_ok` 四个 token 都是本设计独有前缀，`cands=1` 时唯一候选必然是目标 net；打印实际名可让归档 ltx/日志可追溯；若未来出现 `cands>1` 仍会 error（不静默错连）。

**实测结果（attempt-3，apply 修复后，12:23）——`out/r3c_synth.log`**：

```
:3021 ILA0_CLK_NET: user_clk
:3023 ILA3_CLK_NET: ui_clk
:3024 DBG_NET_FUZZY(dbg_wd_go_ui):  u_mem/gen_wr_dma_obs.dbg_wd_go_ui
:3025 DBG_NET_FUZZY(dbg_wd_ack_ui): u_mem/gen_wr_dma_obs.dbg_wd_ack_ui
:3026 DBG_NET_FUZZY(dbg_wd_intr_ui): u_mem/gen_wr_dma_obs.dbg_wd_intr_ui
:3027 DBG_NET_FUZZY(dbg_wd_go_ok):   u_mem/u_bridge/g_wr_dma.dbg_wd_go_ok
:3028 ILA5_PROBE5: 7 nets (go_ui/ack_ui/intr_ui/go_ok/state)
:3030 ILA4_CLK_NET: init_clk
:3031 ILA4_PROBES: probe0=36 (lite AXI/fsm/mbox/reset/stuck[35:0]) + probe1=1 (stuck_or trigger)
:3039 SYNTH_ONLY_DONE          （pre_impl_debug.dcp 更新为 12:23:32，21.57MB）
```

⇒ **根因精确定位**：generate 块内 net 的 `NAME` 形如 `<inst>/<gen_block>.<net>`（层次分隔符在一段内出现 `.`），`split "/" end` 得到 `gen_wr_dma_obs.dbg_wd_go_ui`，精确匹配与 `_N` 两级均不命中 —— `cands==1` 唯一候选法正是对的最小兜底。长期更稳的写法：命中判据用 `[lindex [split [string map {. /} [get_property NAME $n]] /] end]`（把 `.` 归一为层次分隔）再去比对 token。
⇒ **4 核 debug core 创建全部成功**（ILA0/3/5 + ILA4 probe0=36/probe1=1），A 文档 §2.3 的 R1（双名 alias）因 Lead 已改用 `[lindex $nets4 35]` 兜底而**不成立（风险消除）**；R6 已闭环。


---

## 3. `u_ila_4 @init_clk` 逐项复核

### 3.1 时钟/域归属（L2）

- ILA4 clk = `init_clk`（顶层 BUFG 输出，100MHz；`aurora_mem_bridge.v:170,369-371`），与 BD `clk_100m` 同一物理网（`u_mb_ctrl/.clk_100m(init_clk)`，`:708`）。
- `dbg_o[35:0]` 全部来自 aclk 域：AXI 端口信号、`lwst/lrst`、aclk 侧邮箱寄存器（`a_req/a_ack_s/r_req/r_ack_s/d_req_s/d_ack`）、`aresetn`、`l_rstuser_s2`（clk_user 域 `rst_user_n` 经 2FF 进 aclk）、粘滞位/计数器（`axi_lite_regs.v:558-641`）。
- ⇒ **无跨域采样**（AGENTS §五.2 满足）；ILA4 与所有探针同域。
- 唯一 CDC 路径 = `rst_user_n → l_rstuser_s1/s2`（`:590-601`），属 AGENTS §5.1 合法形态②（2FF）；**缺陷：缺 `(* ASYNC_REG = "TRUE" *)`**（同文件既有 `a_ack_s/r_ack_s/d_req_s` 都有，`:130-131`）。本轮不改 RTL，记 round3d（§6）。

### 3.2 位图正确性（L2，逐项核对）

| bit | 信号 | 复核 |
|---|---|---|
| 0-9 | `arvalid/arready/rvalid/rready/awvalid/awready/wvalid/wready/bvalid/bready` | 与 RTL 端口一一对应（`:558-567`） |
| 10 | `araddr[7:2]==6'h0D` = **+0x34 DMA_REQ 读** | ✓（0x34>>2=0x0D） |
| 11 | `==6'h10` = **+0x40 WR_REQ**（round3b 挂死地址） | ✓ |
| 12 | `==6'h11` = +0x44 WR_DBG | ✓ |
| 13 | 其它读地址 | ✓（组合，见下注） |
| 14 | `awaddr[7:2]==6'h03` = +0x0C SET_ENGINE | ✓ |
| 15 | `==6'h12` = **+0x48 SET_WRGO（GO 写）** | ✓ |
| 16 | `==6'h13` = +0x4C SET_WRACK | ✓ |
| 17 | 其它写地址 | ✓ |
| 18-21 | `lwst[1:0]`/`lrst[1:0]`（0=IDLE,1=EXEC/RACK,2=CLOSE/DRQ,3=DACK） | ✓（`:164,257`） |
| 22-27 | `a_req/a_ack_s[1]/r_req/r_ack_s[1]/d_req_s[1]/d_ack` | ✓（aclk 侧） |
| 28 | `aresetn` | ✓ |
| 29 | `rst_user_n` 经 2FF 进 aclk | ✓ |
| 30 | `rst_user_evt`（曾低，sticky，仅 aresetn 清） | ✓；**解读注意**：上电初期 `link_ok` 未起时 `rst_user_n=0`，该位必为 1，不能单独当"楔死时刻复位"证据；要靠 bit29 与 ILA 波形时标 |
| 31-34 | `[31] lrst!=IDLE≥256；[32] lwst!=IDLE≥256；[33] arvalid&&!arready≥256；[34] rvalid&&!rready≥256` | ✓ 纯观测（`:607-640`） |
| 35 | `|stuck[3:0]`（触发位） | ✓ |

**注（判读纪律）**：bit10-17 是**当前总线地址的组合解码**，不 gate `valid`；在 `!arvalid/!awvalid` 时这些位仍可能随总线变化 → 判读"这笔读/写是 +0x40"时必须同时看 bit0/bit4（valid）与 bit1/bit5（ready）。同理 bit35 的 sticky 永不自动清，一轮里出现过一次正常"慢事务"后触发位保持，需按"首次置位时刻"解读。

### 3.3 卡死检测判据复核（L2 静态）

- 门限 256 aclk 周期 = 2.56µs。正常 4 相邮箱往返在该设计约 10–30 aclk（aclk 100MHz ↔ user 151.5MHz，2FF×2 方向 + 状态机），余量 ≥8×；**正常背压不会误触发**。
- 可能"真触发但非目标故障"的场景：`rst_user_n` 被拉低（Aurora link 掉线）期间，任何 in-flight Lite 事务都会悬置 >256 拍 → 触发。这本身是 H1 候选（§B 文档），需靠 bit29/30 与波形区分，不是误报。
- **漏测清单（重要）**：
  1. **AR 根本没到 lite_regs**：`stuck[2]` 需要 `arvalid=1`；若 MCU/互联没发 AR，4 个 sticky 全 0，`stuck_or` 永不触发 → ILA4 NO_TRIGGER ≠ 通路正常（AGENTS §6a 硬规则 3）。
  2. **`bvalid=1 && bready=0`**（B 响应无人消费）：无检测位；而 fix2 的读门控含 `!s_axi_bvalid`（`axi_lite_regs.v:290`），该形态会让**后续读永远不受理** → 与本次楔死高相关。
  3. **`aw_pending|w_pending` 半锁存**（AW 已收、W 永不到）：无检测位；会让 ARREADY 永远不升。
  4. `awvalid&&!awready` / `wvalid&&!wready` 长期悬置：无检测位（只要主端也持续举 valid，可被 bit33 之外的形态漏掉）。
  5. 写通道 `bvalid` 卡住时若主端也不举 AR（纯写挂），bit33 不触发。

### 3.4 预期 ILA4 签名（供上板对号；判读表同 B 文档 §4）

| 形态 | ILA4 预期（bit 号见 §3.2） | 结论方向 |
|---|---|---|
| **H-ARnever**（AR 没到 lite_regs） | `[0]=0,[1]=1,rvalid=0,lwst=lrst=0`，邮箱 22-27 全 0；`[28]=1`；快照时 `[29]` 看 rst；**无触发** | 上游（MCU/互联）挂；非 lite_regs |
| **H-acklost**（邮箱等不到回程） | `lrst=1`(LR_RACK) & `[24]r_req=1` & `[25]r_ack_s1=0`，或 `lrst=2`(LR_DRQ) & `[26]d_req_s1=0`；写侧同理 `lwst=1` & `[22]a_req=1` & `[23]a_ack_s1=0`；bit31/32 置位 | 跨域复位失配/4 相邮箱死等 |
| **H-bstuck**（B 未消费冰封读） | `[8]bvalid=1,[9]bready=0,lwst=2(CLOSE)`；`[0]arvalid=1,[1]arready=0`；bit33 置位、bit31/32 不置位 | fix2 串行化门控被 B 卡住 |
| **H-rvalid**（响应已回主端不取） | `[2]rvalid=1,[3]rready=0,lrst=3(DACK)`；bit34 置位 | 互联/主端未收响应 |
| **H-false-hs**（假握手） | `awvalid&awready` 同拍而 `lwst!=0`；或 `arvalid&arready` 同拍而 `lrst!=0`（fix2 后理论上不应出现；无专用 sticky，需看原始波形） | lite_regs 协议残余缺口或互联非法推进 |

---

## 4. `u_ila_5` 新增 probe5 复核

### 4.1 网络与唯一性（L2）

- `dbg_wd_go_ui/dbg_wd_ack_ui/dbg_wd_intr_ui`：声明在 `frame_mem_if.v:514-518` 的 `generate if (HAS_DMA)` 分支；本工程 `frame_mem_if` 有 **2 个实例**（`aurora_mem_bridge.v:817 u_mem` HAS_DMA=1、`:974 u_mem2` HAS_DMA=0），HAS_DMA=0 分支不生成同名 net ⇒ 全设计**唯一**。
- `dbg_wd_go_ok`：`axi4_master_bridge.v:559-562,888-889` 的 `g_wr_dma`（HAS_DMA=1）分支；`u_mem2` 的 `u_bridge` 走 `!HAS_DMA` 分支 ⇒ 唯一。
- `dbg_s2mm_state[2:0]`：顶层 alias（`aurora_mem_bridge.v:1454`），与 ILA3 同源，复用合法。
- `dbg_net`（`build_debug.tcl:74-90`）：`get_nets -hier -filter "NAME =~ *token*"` + leaf 名精确匹配 + `_N` 后缀兜底 + 多匹配 error。**设计合理**；残余风险是综合给 net 起完全不同的名字（不止 `_N` 后缀）→ error fail-fast，不是静默错连。等级 L1（未上板）→ 若编译期 marker `ILA5_PROBE5: 7 nets` 出现即升 L2。

### 4.2 触发策略（重要）

- Probe5 的第 1 位是 `dbg_wd_go_ui`（GO 翻转后的 ui 域电平）。若触发条件 `eq1'b1`：
  - **在板验序列（'d'→ping）之前 arm**：可抓到 GO 上升沿 + 其后约 1024×3.33ns≈**3.4µs** 的引擎反应（WAITGO→ARM→STREAM→…）——这是判别"GO 到了没有/引擎反应"的主证据。
  - **楔死后才 arm**：GO 若已翻，触发**立即**发生，capture 只是当前静态电平（仍可读 go/intr/state 值，但没有边沿信息）；GO 若未翻，NO_TRIGGER。
- 建议（写进 runbook）：ILA5 先在 `'d'`/`ping` 前 arm；楔死后再用 `R2_SNAPSHOT_ONLY=1` 抓一次静态快照；两次都在同一 batch 会话内完成（arming 易失，AGENTS §六.2）。
- 引擎忙态可再补一次**第二触发**（`dbg_s2mm_state != 0` 或 `tvalid==1`）以抓 STREAM/PUSH 窗口；否则 3.4µs 窗口在 GO 后可能被 ARM/STREAM 前几拍占满。

### 4.3 覆盖缺口（影响 B 判读）

probe5 只覆盖 `go/ack/intr/go_ok/state`。**没有** `wf_level[12:0]`（WD_WAITGO 完成条件之一）、`wd_len`、`stat_wr_timeout`（WAITGO 超时唯一痕迹，桥内 `wr_timeout_r`）。因此：
- Z2（`wf_level < wd_len`，条件永不满足）只能靠"state 长时间停在 WAITGO(1)"间接判；
- Z5（WAITGO 超时→DRAIN→IDLE）在 `wr_fault=0`、`state=0` 时与"从未启动"不可区分。

round3d 建议：扩 dbg_o 或加 1b sticky（`stat_wr_timeout!=0`）到 ILA5 probe5（+1b，成本极低），必要时再加 `wf_level[12:0]`（300MHz 风险，优先只加 sticky）。

---

## 5. 任务书探针清单逐项判定

| 清单项 | 判定 | 依据 |
|---|---|---|
| [1] 在 `rtl/axi_lite_regs.v` 增 mark_debug 别名（BD 内），`u_ila_4 @init_clk` 按 net 名搜 | **否决**（Lead 已改为 BD 端口方案）：裸名搜不到层级内 net；OOC 内 alias 保名未验证；insertion 流程未验证 | §2.1 |
| [1'] 实际方案：`dbg_o[35:0]` 全局输出 → BD 端口 → 顶层 alias → ILA4 | **通过**（附 R1/R2 兜底） | §2.2、§2.3 |
| [1''] 位图（10..17 地址解码、18..21 FSM、22..27 邮箱、28..30 复位、31..35 卡死） | **通过**；缺 4 个盲区位（round3d） | §3.2、§3.3 |
| [2] ILA5 probe5=7b（go_ui/ack_ui/intr_ui/go_ok/state） | **通过**（唯一性/域正确）；触发需在序列前 arm；覆盖缺口见 §4.3 | §4 |
| [3] ILA0/ILA3 探针不变 | **合理**（时序余量 +0.004；ILA3 深度已 1024 下限） | §4.3、坑 #67 |

---

## 6. 本轮遗留（round3d 必改清单）

1. **`l_rstuser_s1/s2` 补 `(* ASYNC_REG = "TRUE" *)`**（`axi_lite_regs.v:590`；本轮不改 RTL 以保持"归档 RTL=位流 RTL"）。
2. **lite 邮箱超时 → SLVERR + sticky**（比 round3b 建议更优先）：`LR_RACK/LR_DRQ/LW_EXEC` 加 ~4096 aclk 超时，超时清邮箱并向 AXI 返回 `SLVERR`（读 `rresp=2'b10`、写 `bresp=2'b10`），同时置 sticky 位；用户侧用一个 2FF 同步的 `mbox_err` 脉冲把 `ust/urst/a_ack/r_ack/d_req` 复位（只复位邮箱 FSM，不动 cfg 寄存器）。目标：**把"只能重配 FPGA"的楔死降级为可观测、可恢复的错误**。
3. **补 4 个观测位**：`bvalid&&!bready`、`awvalid&&!awready`、`wvalid&&!wready`、`aw_pending|w_pending` 悬置（≥256 拍）+ sticky，并纳入 `dbg_l_stuck_or` 的 or。
4. **S2MM 侧补 1b sticky**：`stat_wr_timeout != 0` 进 ILA5 probe5（区分 Z5/从未启动）；如时序允许补 `wf_level[12:0]`。
5. **固件纪律**（不是 RTL）：`LENGTH` 写之后**立即**写 GO（round2f/round3b-v4 口径），所有诊断读（含 `rd_reg` 的哑写）一律放到 GO 之后 + 20ms 静默；永不在 LENGTH 与 GO 之间插入 Lite 访问（round3b 16D06BD3 的 5 个 `rd_reg` 就是这个形态，见 B 文档 §1）。
6. 若本轮 ILA4 出现 H-bstuck/H-acklost 签名，优先按 §5 判读矩阵修对应的 fix2 门控/邮箱。

---

## 7. 官方依据（两件套：URL + 本工程落点）

| 依据 | URL | 本工程落点 |
|---|---|---|
| `get_nets` 默认只搜 current_instance，`-hierarchical` 才逐层搜 | https://docs.amd.com/r/2023.1-English/ug835-vivado-tcl-commands/get_nets | 原计划[1] 否决理由①；`one_net/bus_nets` 用法 |
| `get_*` 默认只返回顶层对象；带层级名 pattern 才跨层 | https://docs.amd.com/r/2023.1-English/ug894-vivado-tcl-scripting/Getting-Objects-By-Name | 同上；ILA5 嵌套 net 必须用 `dbg_net -hier` |
| MARK_DEBUG 保证 net 不被复制/retime/删除/优化（RTL 或 post-synth 标注） | https://docs.amd.com/r/2023.1-English/ug949-vivado-design-methodology/Retaining-Names-of-Debug-Probe-Nets-Using-MARK_DEBUG | 顶层 alias 保名（§2.2）；BD 内 alias 未验证（§2.1） |
| MARK_DEBUG 行为控制（默认不优化 debug net） | https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging/Managing-mark_debug-Behavior-Post-Synthesis | 同上（该节 2023.1 亦有，查到的返回块 version 以 2025.2/2026.1 为主 → 结论按"语义一致"用，标 L2 不标 L3） |
| RTL mark_debug 加入 BD module ref 的 insertion 流程（DFX 上下文，需 BD 内 Debug Hub） | https://docs.amd.com/r/en-US/ug909-vivado-partial-reconfiguration/Insertion | 原计划[1] 的"唯一官方支持形态"与本工程流程不同（§2.1 假设③） |
| Debug Hub 时钟必须 free-running；ILA 时钟须与探针域同步 | https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging/Vivado-Hardware-Manager-Clocking-Related-Error-Messages | ILA4 @init_clk（与 aclk 同源）合法性（§3.1）；ILA5 @ui_clk 不变 |
| `create_bd_port` / `connect_bd_net` 用法 | https://docs.amd.com/r/2023.1-English/ug835-vivado-tcl-commands/create_bd_port | `create_bd_b.tcl:195-196` |

（版本提示：2023.1 专属页面未返回的条目按"语义跨版本一致"采用，等级不高于 L2；已逐条核对返回块 `family:/version:`，未把 2026.1 专属行为当 2023.1 结论。）

---

## 8. 复核命令留痕

```
# 原计划否决证据
Select-String build_r2_synth.log -Pattern 'synthesizing module|BlackBox|Reading design checkpoint|open_run:'
# 现方案证据
Select-String prj11.gen/sources_1/bd/mb_ctrl/synth/mb_ctrl.v -Pattern 'dbg_l_bus'
Select-String prj11.runs/mb_ctrl_axi_lite_regs_0_0_synth_1/runme.log -Pattern 'IPCACHE|synth_design|__synthesis_is_running__'
# 构建 marker 检查
Select-String out/r3c_synth.log -Pattern 'MODULE_REF_RESET|SYNTH_STATUS|ILA4_CLK_NET|ILA4_PROBES|ILA5_PROBE5|ILA5_PROBES|WNS_GATE|W5_BUILD_OK|DBG_BUILD_DONE|net not found|dbg_net'
```

*本文件由 rtl-auditor 产出，只读审计，不修改 rtl/scripts/sw/docs。等级：L2=代码级/同版本实物；L1=未验证假说；本文件不含 L4 定案。*
