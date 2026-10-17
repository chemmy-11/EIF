# 离线 RTL 审计：退役 RTL vs 绿 RTL（engine=1 等价性复核 + 发射口之后路径重建）

- 审计员：离线只读（未改仓库、未 commit、未碰硬件；全部结论来自 git + 源码 + 归档日志）
- 时间：2026-10-17 20:45（Asia/Shanghai）
- 仓库：`D:\FPGA`（master），工程 `prj/project_11`，Vivado 2023.1 / XCKU060
- 工作树 RTL 与 `5c9a8e9` **逐 blob 相同**（已证实：`git hash-object` 对比
  `aurora_mem_bridge.v`=5d944d53、`axi4_master_bridge.v`=d0ed1655、`frame_mem_if.v`=e93aceee、
  `frame_fifo_pump.v`=9d001c90、`dma_rd_shim_v2.v`=…、`dma_sink.v`=8b243c12 全部一致）

**证据等级约定**（AGENTS §6a）：`已证实` = 可复现的源码/git/日志事实；`推断` = 由事实推出但
未被独立测量确认；`L0/L1/L2` = 假设置信度（L2 高 / L1 中 / L0 低）。本报告**不把相容假说写成判定**。

---

## 0. 结论摘要（先看这段）

1. **【已证实】退役 RTL 相对绿 RTL 的改动只有 2 个文件、5 处实质变更**（13 增 64 删），全部集中在
   `axi4_master_bridge.v` 读 FSM / shim 合并口，以及 `aurora_mem_bridge.v` 的 `dma_tready` 与
   `dma_sink` 冒烟口。**没有任何一处触及** frame_mem_if 读侧、泵B、末级 mux、gmii_to_rgmii、
   桥②(u_mem2) 或 Aurora 数据面。
2. **【推断 L2】这 5 处在 `engine=1` 稳态下确实逻辑等价**（逐 hunk 见 §3）；真正的行为差异只有
   两个"窗口"：`engine=0` 时退役版**完全没有读出路径**，以及引擎位翻转瞬间的 gating/tready 窗口。
   ⇒ 单靠这 5 处，**无法解释"同一激励 4/4 vs 0/3"**。
3. **【已证实·关键】归档日志 `s2_s6_204148.log` 里，退役配置 ping 期间的读侧一次都没启动**：
   `WM_WR 2→7`、`WM_RD 2→2`、`req` bit25=0（无待服务请求）。该轮 S5 的 ping 是**无效实验**，
   绿位流跑同一序列也会是 0/N。原因链见 §5 H1（round 收尾把 `cfg_mode` 留在 RND，而 RND 下
   顶层不自动发读）。同时，§补四 表里"两侧 wmwr/wmrd 都 1/1→4/4"与这份原始日志**直接矛盾**。
4. **【已证实】`dbg_emit` 探的不是上线的那个发射口**：它在桥①（`u_mem`），桥① 的读出去向是
   `axis_word_pack → Aurora TX`；而上线路径的泵B 输入是**桥②（`u_mem2`）**。"emit 正确"只覆盖
   「桥①→Aurora」这一跳，**对「桥②→泵B→mux→PHY」零覆盖**。§4 给出完整两跳路径。
5. **【已证实】"绿 4/4 vs 退役 0/N"有两次不同的对照，且两次都有问题**：
   - 对照①（文档 §三之十九之补 §3，ELF **`4aac46be`**）：绿 4/4 / 退役 0/3，**原始日志不在
     `out/evidence_2026-10-17/`**，无法复核其 `cfg_mode`/`WM_RD`；
   - 对照②（文档 §补四，ELF **`2961b585`**）：声称"逐项相同"，但其原始日志（本目录
     `s2_s6_204148.log`）显示 **`WM_WR 2→7` / `WM_RD 2→2`**，即**读侧零启动** ⇒ 该轮无效（H1）。
   - 此外 `5c9a8e9` 同时改了 `sw/*/main.c`（`g_dma_mode` 默认 0、round 收尾强置 `R_ENGINE=0`、
     'd' 才置 1），而"绿 4/4"依据的是**另一颗 ELF**——这使"唯一变量=位流"至少在对照②上不成立。
6. 因此「发射口之后」这一收窄**目前不成立**；最可能的两条是 H1（测试序列/RND，L2）与
   H2（有效对照缺原始日志 / 软件变量混入，L2），其后才是 H3（Aurora/桥②这一跳从未被观测，L1）
   与 H4（网表级差异，L1）。最小判别实验全部**不需要重建位流**（§6）。

---

## 1. 审计方法与命令（可复现）

```powershell
git -C D:\FPGA log --oneline -20 -- prj/project_11/rtl
git -C D:\FPGA diff --stat 3f847e3 5c9a8e9 -- prj/project_11/rtl/     # 2 files, 13+/64-
git -C D:\FPGA diff 3f847e3 5c9a8e9 -- prj/project_11/rtl/             # 逐 hunk（§3）
git -C D:\FPGA diff --stat 3f847e3 5c9a8e9 -- prj/project_11/          # 含 sw/ scripts/ sim/
git -C D:\FPGA diff 3f847e3 8afa168 -- prj/project_11/rtl/             # 退役(读引擎删除)单独看
git -C D:\FPGA diff 8afa168 5c9a8e9 -- prj/project_11/rtl/             # dma_tready 单独看
```

时间线（`git log`）：`3f847e3`（v5-RTL，绿位流 `708f15a4` 的 RTL 基线，10-16 16:18 前）→
`8afa168`（B3-1c 删硬件读 FSM + 冒烟口让路）→ `5c9a8e9`（`dma_tready` 恒接 shim + 软核驻留服务 ELF）。
`3f847e3..8afa168` 只动 `axi4_master_bridge.v`（71 行）＋`aurora_mem_bridge.v`（1 处）；
`8afa168..5c9a8e9` 只动 `aurora_mem_bridge.v` 的 `dma_tready` 一行。

> 注：`5c9a8e9` 的提交信息说"位流构建中"，归档位流 `3aa600aa` 的 mtime 20:47:32 在其后；
> 造它的脚本 `build_rdclose_sweep.tcl` 未入库（文档 §补二 §2 已记），本审计**无法**确认该位流的
> 网表与当前 RTL 一一对应——这是既有的「坑 #35 DCP 缓存」风险，不在本报告结论内。

---

## 2. 逐 hunk 全量差异（`3f847e3` → `5c9a8e9`，rtl/ 只有这 5 处）

### Δ1 `aurora_mem_bridge.v:290`（`8afa168` 之后的 `5c9a8e9` 引入）

```diff
-wire dma_tready = dma_engine_ui ? dma_tready_shim : dma_tready_sink;
+wire dma_tready = dma_tready_shim;
```
`dma_tready` 的去向：`aurora_mem_bridge.v:738` `.M_AXIS_MM2S_0_tready(dma_tready)`（进 mb_ctrl 的
MM2S 主口）。`dma_engine_ui` 是 `lite_cfg_rd_engine` 的 ui 域 2FF（`aurora:309-317`）。
**engine=1 稳态：两者恒选 shim ⇒ 真等价。** 差异只出现在 `dma_engine_ui==0` 的窗口（上电后
软核写引擎位之前、以及引擎位被写 0 之后）。

### Δ2 `aurora_mem_bridge.v:1102`（`8afa168`）

```diff
 dma_sink u_dma_sink (
   .s_tvalid(1'b0), .s_tready(dma_tready_sink),   // 原: ~dma_engine_ui & dma_tvalid
```
- **更正任务书/文档口径**：这里改的是**独立冒烟捕获器 `u_dma_sink`（1098-1105）**，**不是**
  `u_mem2`。`u_mem2`（桥② EGRESS，`HAS_DMA(0)`，917-962）的 DMA 口本来就恒接 0
  （`.dma_engine(1'b0) … .dma_s_tvalid(1'b0)`，956-959），**本次改动没碰它**。
- engine=1 稳态：旧式 `~dma_engine_ui & dma_tvalid` 也恒 0 ⇒ **真等价**；唯一副作用是
  `'D'/'F'` 冒烟读回永久冻结（q0/q1/q2 不再更新）——文档已记。

### Δ3 `axi4_master_bridge.v:555`（`8afa168`）

```diff
- .s_tvalid(dma_engine & dma_s_tvalid),
+ .s_tvalid(dma_s_tvalid),
```
`dma_engine` 是 **user 域**的 `lite_cfg_rd_engine`（`aurora:289`），**未经同步**直接进 ui 域与
`dma_s_tvalid` 相与——绿版这里本来就是个 CDC 单比特采样点。engine=1 稳态 ⇒ 等价；引擎位翻转的
2 拍窗口里旧版会短暂"关掉 shim"（丢的只是拍数，AXIS 主端会保持 tvalid，不丢数据）。
**方向性**：退役版更宽松，不会造成本故障。

### Δ4 `axi4_master_bridge.v:563-564`（`8afa168`）

```diff
-assign rf_wr_en   = brf_wr_en | shim_rf_wr_en;
-assign rf_wr_data = shim_rf_wr_en ? shim_rf_wr_data : brf_wr_data;
+assign rf_wr_en   = shim_rf_wr_en;
+assign rf_wr_data = shim_rf_wr_data;
```
`brf_wr_en` 只在 R_UNPACK 置 1（原 649 行清零、R_UNPACK 置位）。engine=1 时读 FSM 自 R_PRE 直接去
R_DRET（698-702），**R_UNPACK 不可达 ⇒ brf_wr_en ≡ 0 ⇒ 真等价**（不是"看起来等价"）。

### Δ5 删除 `R_AR/R_R/R_UNPACK/R_FIN` 四个状态分支（`8afa168`）

`R_PRE` 的 `if (dma_engine) … else …` 二选一改成无条件 `dma_req_new<=1 … rstate<=R_DRET`
（694-703）。engine=1 时旧版走的就是 `dma_engine` 分支 ⇒ **控制流真等价**。
**但网表不等价**：`r_beats/r_beat/r_bi/r_nbytes/r_beat_data/m_axi_arvalid/m_axi_rready/lat_r` 的
组合锥进入死代码删除，`len_beats_tab` 失去唯一读者。⇒ 这是**唯一可能改变实现结果**的改动（§5 H4）。

### Δ0（不在 rtl/，但同一次退役引入，必须计入变量）`sw/j3_soft/src/main.c` + `sw/src_j3/main.c`

```c
static unsigned g_dma_mode = 1u;   // → 改为 0u（上电默认不驻留）
...
if (g_dma_mode) { R_ENGINE = 1u; g_dma_service = 1u; }   // round 起（main.c:352-356）
...
if (g_dma_mode) { g_dma_service = 0u; R_ENGINE = 0u; }   // round 收尾（main.c:375-379）★
...
else if (c == 'd') { g_dma_mode = !g_dma_mode;
                     R_ENGINE = g_dma_mode ? 1u : 0u;
                     if (g_dma_mode) R_MODE = MODE_SEQ; }  // main.c:436-447
```
★ 这一行 `R_ENGINE = 0u` 是**软核主动把引擎位写回 0**，发生在每轮 M/A/B 结束时。它让"轮次跑完
之后的任何流量"都落在 `engine=0`——而退役 RTL 在 engine=0 时**没有任何读出路径**。

---

## 3. `engine=1` 等价性判定表（"真等价" vs "看起来等价"）

| # | 改动 | engine=1 稳态 | 判定 | 何时不等价 |
|---|---|---|---|---|
| Δ1 | `dma_tready` 恒接 shim | 旧 mux 也选 shim | **真等价** | engine=0 窗口；`dma_engine_ui` 复位后 2 拍 |
| Δ2 | `u_dma_sink.s_tvalid=0` | 旧门控也恒 0 | **真等价**（仅冒烟诊断失效） | engine=0 时旧版会捕获流 |
| Δ3 | shim `s_tvalid` 去门控 | `dma_engine=1` | **真等价** | 引擎位翻转的 2 拍；上电默认 0 期间 |
| Δ4 | `rf_wr_en/rf_wr_data` 只取 shim | `brf_wr_en≡0` | **真等价**（结构可证） | 若 `brf_wr_en` 被综合保留成非 0 —— 不可能，R_UNPACK 已删 |
| Δ5 | 删 4 个读状态 | 控制流同 | **控制流真等价 / 网表不等价** | 实现层（时序/综合改写）——见 H4 |
| Δ0 | ELF：round 收尾 `R_ENGINE=0` | **不等价** | **真差异（软件）** | 每轮结束后 |

**推断 L2**：以上 5 处 RTL 改动在 `engine=1` 稳态下**不构成功能差异**。文档声称的"等价"在 RTL
层面站得住；**但"等价"这个判定不能反推"板上必须同行为"**，因为（a）Δ0 让 engine 位在测试序列
中并不恒为 1，（b）Δ5 改了网表，（c）对照实验的 ELF 不是同一颗（§5 H2）。

---

## 4. TX 路径精确重建（`file:line` + 握手）

**重要更正**：上线路径是**两级内存桥 + Aurora 环路**，`dbg_emit` 只覆盖第一级。

### 4.1 第一跳：桥① 读侧 → pack → Aurora TX（`dbg_emit` 所在处）

| 步 | 位置 | 信号/握手 |
|---|---|---|
| rdesc 弹出 | `frame_mem_if.v:369-385`（est==0） | `!rd_empty` → `rd_pop<=1`（`u_rd_desc` FWFT，`async_fifo.v:32/68`）；`rd_len_o<=rd_dout[23:8]`、`rd_slot_o<=rd_dout[7:0]`；`dout[24]=1` 是"空答" |
| 攒帧（PRIME） | `frame_mem_if.v:394-397`（est==3） | 条件 `rb_level >= rd_len_o`（**注意：`rb_level` 接的是 `wr_level`，见 4.4 的 CDC 备注**） |
| 逐字节发射 | `frame_mem_if.v:398-405`（est==1） | `rb_rd_en=(est==1)&&!rb_empty`（355）；`rd_data<=rb_dout`、`rd_en<=1`；`rd_cnt==rd_len-1` → est=2。**1 字节/user_clk，帧内无气泡（PRIME 保证）** |
| 帧尾 | `frame_mem_if.v:406-412`（est==2） | `rd_en<=0`、`rd_frame_done<=1`、`rd_busy_r<=0` |
| 端口 | `frame_mem_if.v:45-51`；`aurora:1159-1163` | `mem_rd_data/mem_rd_en`（**无 tready**，纯 valid 流）→ `axis_word_pack` |
| 打包 | `axis_word_pack.v:113-155` | 帧界 = `in_valid` 的**下降沿**（`else if (frame_active)`）；末字按 **高位 lane 对齐**（`tail_shift`）；输出 16 深队列 `158-171` |
| Aurora TX | `axis_word_pack.v:75-80` → `tx_tdata/tkeep/tlast/tvalid` | `m_tvalid=~q_empty`、`pop=m_tvalid&m_tready`；`m_tready` 来自 Aurora IP |

### 4.2 第二跳（真正上线的那一跳）：Aurora RX → 桥② → 泵B → mux → gmii_to_rgmii

| 步 | 位置 | 信号/握手 |
|---|---|---|
| 解包 | `aurora:1176-1189`（`axis_word_unpack`） | `unpack_data/unpack_en` |
| 桥② 写 | `aurora:917-929`（`u_mem2`，`HAS_DMA(0)`，SLOT_BASE=0x0020_0000） | `wr_data(unpack_data)`、`wr_en(unpack_en)`，帧界同样靠 `wr_en` 下降沿（`frame_mem_if.v:287-336`） |
| 桥② 读 | `u_mem2` 读 FSM（**仍是硬件读引擎**，未被退役影响） | `mem2_rd_data/mem2_rd_en`（`aurora:1197-1198`） |
| 泵B | `aurora:1194-1206`（`frame_fifo_pump`） | 乒乓双 bank，**跨域只靠 toggle**（`frame_fifo_pump.v:65-75`）；读侧 `rd_data<=ram_dout; rd_en<=ram_dout_v`（`172-173`），**无 tready**；帧长锁存 `len0/len1`（`112`），排空按 `rd_len`（`176-182`） |
| 末级 mux | `aurora:1223-1226` | `rgmii_txd_i=pump_rev_data`、`rgmii_tx_en_i=pump_rev_en`；`*_o = cmd_takeover ? cmd_resp_* : *_i` |
| 接管锁存 | `aurora:333-342` | `cmd_takeover` 在 `cmd_resp_busy && tx_idle_cnt≥64` 时置位、`!cmd_resp_busy` 清零。**若 `cmd_resp_busy` 卡高，则线上永久输出 `cmd_resp_txd`（空闲=0）** |
| PHY | `aurora:501-514`（`gmii_to_rgmii`） | `.gmii_tx_en(rgmii_tx_en_o)`、`.gmii_txd(rgmii_txd_o)`；**该模块无 tready**，纯 valid |

### 4.3 关系到结论的三条推论

1. `dbg_emit`（`frame_mem_if.v:507-527`）只记录**桥①** rdesc 的 `{len,slot}` 与 `rb_dout` 首字节；
   桥① 的字节流去了 `u_pack`（Aurora TX），**不是**泵B。⇒ emit 正确 ≠ 线上有帧。
2. 桥① 的读出与桥②/泵B 之间隔着 **Aurora 收发**（`tx_*`→光纤/回环→`rx_*`）与**一整级 DDR 桥**。
   引擎位只影响桥① 的读法（硬件读 vs DMA），**完全不影响**桥②→泵B→mux。⇒ 若故障在第二跳，
   两台配置的差异与 RTL 改动无关。
3. 泵B 的写入端是**桥② 读侧**，而桥② 的写入端是 Aurora RX。`link_ok = channel_up & channel_up_b`
   （`aurora:207`）、`aurora_rst = ~sys_rst_n | ~link_ok`（`aurora:210`）—— **任一路 Aurora 通道掉线**
   都会让 `aurora_rst` 恒 1：泵B 写侧复位（`frame_fifo_pump.v:81`）、`u_mem2` 的
   `user_rst_n=~aurora_rst` 复位（`aurora:919`）、`axis_word_pack` 复位（`1159-1171` 的 `.rst`）
   ⇒ 线上永久安静，而桥① 的 **ui_clk 侧**计数（`ui_rst_n` 来自 MIG，`aurora:236-239`，与 `aurora_rst`
   无关）照常推进。**这是"内部计数正常、线上没帧"的另一种完整解释。**
   **但注意**：`frame_mem_if` 的**写侧也在 user 域**（`user_rst_n=~aurora_rst`，`frame_mem_if.v:38/42/304`），
   若 `aurora_rst` 真的恒 1，写侧根本不会接受帧 ⇒ `stat_wm`(`WM_WR`) 不会涨。**S2–S6 日志里
   `WM_WR` +5 恰好证明 `aurora_rst=0`（链路在位）**——所以这个子机制**不适用于** S2–S6 那一轮，
   只可能属于更早的 §补二 那次（读退休 +6、回包 0/6）。

### 4.4 顺带发现的两个静态隐患（与本次对照无关，但会影响任何"等价"论证）

- **`rb_level` 跨域使用（推断 L1，正确性目前被兜住）**：`frame_mem_if.v:191-195` 把 `u_rd_bytes`
  的 `.wr_level(rb_level)` 接出来，`wr_level` 定义在 **wr_clk(ui) 域**（`async_fifo.v:70`：
  `wr_bin - gray2bin(rd_gray_s2)`），却在 **user_clk** 的 est==3 里做 `rb_level >= rd_len_o`
  （`frame_mem_if.v:395`）。这是多比特未同步跨域读，且方向是**高估**（用了陈旧的读指针），
  与源码注释"读域保守值(只会低估)"**相反**。当前不出错只因为 est==1 每字节还查 `!rb_empty`
  （`399`）——高估只会让发射早开始、随后逐字节等，不会取到无效数据。若将来去掉 `!rb_empty`，
  这就是数据损坏点。
- **`dma_engine` 直采（推断 L1）**：`axi4:555`（旧版）与 `frame_mem_if.v:434` 各有一份采样，
  一个是裸采、一个是 2FF ⇒ 引擎位翻转的窗口内两个消费者可能不同步（旧版还有
  "sink 与 shim 同时被使能"的重叠窗）。退役版把 shim 改成唯一消费者，**消除**了这个隐患。

---

## 5. Ranked hypotheses（每条：机制 / 依据 / 置信度 / 最小判别实验）

> 排序原则：先用**零重建成本**的实验排除"实验本身无效"，再谈 RTL/网表。

### H1【测试序列使 ping 期间读侧根本没启动】— 置信度 **L2（推断，但证据链很硬）**

- **机制**：`round_command` 在 phase1 把 `cfg_mode` 置 RND 且**不恢复**（`sw/j3_soft/src/main.c:358`，
  注释亦自认"不在此恢复 SEQ"）。而顶层只有 SEQ 才自动发读：
  `aurora_mem_bridge.v:323-327`
  ```verilog
  else if (cfg_mode_eff) mem_rd_req <= cmd_rd_req_pulse | lite_rd_req_pulse;
  else                   mem_rd_req <= (mem_outstanding_sync != 0) && !mem_rd_busy && !mem_rd_req;
  ```
  RND 下没人 pulse ⇒ `mem_rd_req` 恒 0 ⇒ `uc_wr_en`（`frame_mem_if.v:354`）恒 0 ⇒ 命令 FIFO 空 ⇒
  `rc_rd_en`（`axi4:619`）恒 0 ⇒ 读 FSM 永远停在 R_IDLE ⇒ **不发 DMA 请求**（`dma_req_new` 保持 0）
  ⇒ 软核驻留环 `serve_dma_once` 读 `0x34` 看不到 bit25 ⇒ 什么都不做 ⇒ 帧只写不读。
- **依据（已证实的日志事实）**：`out/evidence_2026-10-17/s2_s6_204148.log`
  （位流 `3aa600aa` + ELF `2961b585`，20:41 场次）：
  - `'U'` 探针每行首值是**上一地址的值**（`main.c:127-151` 明写"M01 读一笔滞后…第二笔恒新鲜"），
    且每行首值恰好等于上一行稳定值（`req` 首值=`id` 的 `0x50314231`；`wmwr` 首值=`emit` 的
    `0x00760155`）⇒ 解码自洽：S3 `WM_WR=2, WM_RD=2`；S6 **`WM_WR=7, WM_RD=2`**。
  - S3 `req=0x01010076` ⇒ bit24(engine)=**1**；S6 `req=0x00010076` ⇒ bit24(engine)=**0**、
    **bit25(dreq_new)=0**（无待服务请求）。引擎位在两处之间被写成 0 —— 正是 S4 round 收尾的
    `R_ENGINE = 0`（`main.c:375-379`）。（`ro_dma_req` 拼接见 `frame_mem_if.v:502`。）
  - 即：**+5 写 / +0 读 / 无请求**。这与 S4 的 round 收尾 `R_ENGINE=0`、`cfg_mode=RND` 完全吻合。
  - 与文档 §补四 表（"两侧 wmwr/wmrd 都 1/1→4/4"）**直接矛盾** ⇒ 那张表不能作为"逐项相同"的证据。
  - **交叉排除**：`WM_WR` +5 证明 user 侧写路径活着（`frame_mem_if.v:38/304` 的写侧同受
    `~aurora_rst` 复位）⇒ `aurora_rst=0`、`link_ok=1` ⇒ **"Aurora 掉链把 user 域复位"这一变体
    不适用于本轮**（§4.3 推论 3）。同时 `calib_ok` 也必须为真（否则写侧不提交，`axi4:322`），
    所以"MIG 未校准"也被排除。**剩下唯一能解释"写正常、读零请求"的，就是 `mem_rd_req` 的
    RND 分支（`aurora:323-327`）。**
  - **"与位流无关"判据（推断 L2）**：S6 的 bit24=0 说明 S5 ping 时 **engine=0**。若 `cfg_mode` 也是
    RND，则读触发只可能来自命令脉冲（`cmd_rd_req_pulse`/`lite_rd_req_pulse`），与 `engine` 位和
    读出引擎实现**无关** ⇒ **绿位流在同一状态下同样是"写进去、读不出来"**。这正是需要一个
    "绿 + 同序列"对照才能分清的原因（见本节与该节末条）。
- **最小实验（ELF 现成，零重建，~2 分钟）**：退役位流上电 → `'d'`（**中间不要跑 M/A/B**，因为 'd'
  会顺带置 SEQ：`main.c:443-444`）→ 读一次 `'U'` → ping ×4 → 再读 `'U'`。
  判读：`WM_RD` 前进而回包 0 ⇒ 真缺陷在发射口之后；`WM_RD` 不动 ⇒ 本假设成立、前一轮实验作废。
- **对照（同样零重建）**：绿位流 `708f15a4` + **同一颗** `2961b585` 跑**完全相同的 S2–S6 序列**
  （round 后 ping）。若绿也是 0/4 且 `WM_RD` 冻结 ⇒ "位流差异"前提直接崩塌。

### H2【"唯一变量=位流"没有一份可复核的原始日志】— 置信度 **L2（已证实的事实 ⇒ 推断的结论）**

- **机制/依据（已证实）**：
  - 文档里存在**两次**对照，且都不是"干净的单变量对照"：
    1. §三之十九之补 §3：绿 `708f15a4` + `4aac46be` ping 4/4，退役 `3aa600aa` + 同一 ELF ping 0/3。
       这一次**看起来**是单变量（同一 ELF、'd' 同时置 `R_ENGINE=1` 与 `MODE_SEQ`，见 `main.c:443-444`），
       但**原始日志未归档**（`out/evidence_2026-10-17/` 只有 2961b585 的两份）。
    2. §补四：绿 `708f15a4` + `2961b585` ping 3/3，退役 `3aa600aa` + 同一 ELF ping 0/3，并给出
       "wmwr/wmrd 两侧都 1/1→4/4"的表——**该表与本目录里的原始日志矛盾**（见 H1 解码表）。
  - `5c9a8e9` 同时改了 ELF（§2 Δ0）。如果对照①用的 `4aac46be` 已经包含 `R_ENGINE=0` 的 round
    收尾（该 ELF 是 10-17 的 n5 版本，晚于 `5c9a8e9`），那么**对照①的退役侧也可能在 ping 前
    被某轮 M/A/B 把引擎位归零**；反之若顺序是 'd' → 直接 ping，则对照①有效。
- **最小实验**：按 §6 第 1/2 项重跑对照①的**最小形态**（退役：`'d'`→ping；绿：`'d'`→ping），
  并在 ping 前后各读一次 `'U'`。**只要退役侧 `WM_RD` 前进而回包为 0**，H1/H2 同时被排除，
  H3/H4 顶上；**若 `WM_RD` 不动**，则此前所有"位流差异"结论作废。

### H3【故障在第二跳：Aurora / 桥② / 泵B / 末级 mux】— 置信度 **L1（推断，从未被观测过）**

- **机制**：上线路径 = 桥①读 → `u_pack` → **Aurora TX/RX** → `u_unpack` → 桥②(`u_mem2`) 写/读 →
  泵B → `cmd_takeover` mux → `gmii_to_rgmii`（§4）。其中任一环断开都表现为"`wmwr` 涨、`wmrd` 涨
  （桥① 退休正常）、`emit` 正确、**线上零帧**、PC 计数 delta=0"——与 §补四 观测到的现象**同形**。
  候选子机制：
  - `aurora_rst = ~sys_rst_n | ~link_ok` ⇒ `link_ok` 掉 → 泵B/桥② 全程复位（`frame_fifo_pump.v:81`、
    `aurora:919`），而桥① 的 ui 侧计数照常（**该变体只适用于 §补二 那次；S2–S6 的 `WM_WR` +5 已把
    它排除，见 §4.3-3**）；
  - `cmd_takeover` 卡高（`aurora:338-342`）：`cmd_resp_busy` 不落 ⇒ 线上永久输出 `cmd_resp_txd`；
  - 泵B 的 `len0/len1` 与 bank 释放竞争（`frame_fifo_pump.v:110-124/154-194`）：`rd_en` 比 `rd_data`
    晚一拍是设计内的，但**帧长写侧锁存 vs 读侧采样**只有 toggle 保证，若某帧末字节丢失，泵B 会
    按 `rd_len` 多排/少排（少排时会去读下一 bank 的字节）——需要 ILA 才能排除。
- **依据**：`dbg_emit` 在桥①（`frame_mem_if.v:507-527` + `aurora:815-817`），桥① 出口是
  `u_pack`（`aurora:1159-1171`）；**泵B 的输入是 `mem2_rd_data/mem2_rd_en`（`aurora:1194-1198`）**，
  与桥① 无关。所以现有取证**不覆盖**第二跳。
- **最小实验（复用现有 ILA，只重插探针）**：把 `probe1` 从"桥① 发射字节流"改挂第二跳：
  `mem2_rd_en / mem2_rd_data[7:0] / pump_rev_en / rgmii_tx_en_o / cmd_takeover / link_ok`
  （≈14 net，仍是同一 ILA 深度）。判读：`pump_rev_en` 有字节但 `rgmii_tx_en_o=0` ⇒ mux/接管；
  `mem2_rd_en` 无活动 ⇒ Aurora/桥② 跳；两者都有 ⇒ PHY/RGMII 侧。
- **零成本旁证（优先）**：`'D'/'F'` 冒烟读回在退役位流上已失效（Δ2），但**桥② 的计数器**
  （`mem2_wm/mem2_rd_frame/mem2_outstanding`）目前**没有**暴露到 Lite 读回——建议下一颗 ELF 把
  `mem2_wm/mem2_rd_frame` 或 `pump_rev_wr/rd` 加进 `'U'`；这一步能让 H3 在**不重建位流**的前提下
  被证实/排除。

### H4【网表级差异（坑 #47 家族 / 零余量）】— 置信度 **L1**

- **机制**：Δ5 删掉 4 个状态后，`len_beats_tab`、`r_beats/r_beat/r_bi/r_nbytes/r_beat_data`、
  `m_axi_arvalid/m_axi_rready`、`lat_r` 的锥全部消失，**网表与绿版不同**（虽然 RTL 语义等价）。
  本项目已有多次"RTL 对、网表错"的先例（坑 #47：`len_cnt` CE 锥被改写、`tag_slot=0`、
  `frame_len↔slot` 错位；`HAS_DMA` 参数本身就是为绕开 2023.1 "Mimic Skeleton" 崩溃而加的）。
  两台退役位流的余量分别是 **+0.004**（`3aa600aa`）与 **0.000**（`0ecb8438`），最差路径在
  写侧 FSM CE（文档 §补四 §2 旁证风险）。
- **可预测的失败形态**（若成立）：shim 的 `rf_wr_en` 字节数 ≠ `dma_req_len` ⇒
  `frame_mem_if` 的 est==3（`rb_level >= rd_len_o`）永不满足 ⇒ 读侧卡在 PRIME、`rd_busy_r` 保持 1
  ⇒ 后续 `uc_wr_en`（`354`，受 `~rd_busy_r` 门控）全被拒 ⇒ **`WM_RD` 永久冻结**。
  这与 §5 H1 的日志形态（`WM_RD` 冻结）**同形**，所以只有 ILA/门级仿真能区分。
- **最小实验**：① 门级（post-synth functional）仿真 `bridge_dma_tb` 对退役网表——离线、不碰板；
  ② 造一颗"保留硬件读 FSM 但 engine 位恒 1"的位流（RTL 只恢复死代码、不改行为），若故障消失
  ⇒ 差异确实来自网表/实现而非功能。
- **反证（对 H4 不利）**：`5c9a8e9` 记录 `bridge_dma_tb PASS`；且两台不同实现的退役位流
  （`3aa600aa` +0.004、`0ecb8438` 0.000）**表现同为失败**——若纯属零余量抖动，两台恰好同现象
  的概率不高（但也不能排除，两者网表其实同源）。

### H5【`s_tvalid` 门控/`dma_tready` 的窗口效应】— 置信度 **L0**

- 只在引擎位翻转的 2 拍内或上电初始化窗口内有差异（§3）。若 ELF 在**一帧传输途中**改写
  `R_ENGINE`（例如 round 收尾 `R_ENGINE=0` 恰好落在 DMA 流中间），旧版会把该拍喂给 `u_dma_sink`
  并让 DMA 看到 sink 的 tready ⇒ **shim 少收字节** ⇒ `rb_level` 永远差几个字节 ⇒ est==3 卡死。
  退役版不会。⇒ 这个窗口**只会让绿版更脆弱**，与"绿 4/4、退役 0/3"的方向相反，故降为 L0；
  但它是 H4 之外唯一能解释"卡在 PRIME"的机制，**若要排除 H1/H3，必须查 `R_ENGINE` 是否在帧中被写**。

### H6【`R_DRET` 无超时 ⇒ 单笔丢失即永久停摆（放大器，不是根因）】— 置信度 **L2（结构已证实）**

- `axi4:711-728`：`R_DRET` **唯一**出口是 `shim_frame_done`；没有超时、没有看门狗。一旦某帧的
  `frame_done` 丢失（DMA 少一拍 TLAST、shim 被复位、`dma_req_len` 与流长不符…），读 FSM 永久停泊，
  `dma_req_new` 电平保持 1（`721` 只在退休时清）⇒ 软核驻留环会**反复为该 slot 编程 MM2S**
  （`serve_dma_once` 等 bit25 落零，guard 100000 次后返回，下一次循环再来）⇒ 可能形成
  "重复 DMA + 永不退休"的活锁。**这不会自己恢复**。
- **注意**：这段代码在绿版里**同样存在**（R_DRET 未被本次改动触碰）⇒ 它是**放大器**，不是差异源。
  它解释了为什么一次异常会让"之后所有 ping"都失败（0/3、0/6）。

### 5.7 与任务书五类机制的对照（避免漏项）

| 任务书机制类 | 对应假设 | 静态判定 |
|---|---|---|
| ① 泵B / 末级 mux 没收到 tvalid | **H3** | 泵B 输入是**桥②**（`aurora:1194-1198`），与 engine/退役改动无因果关系；只能由 Aurora/桥②/mux 自身或上游断流造成 |
| ② `rb_dout` 字节流被卡住 / 握手死锁 | **H4、H5** | 唯一的"卡住"点是 est==3 的 `rb_level >= rd_len_o`（`frame_mem_if.v:394-397`）；它成立的前提是 shim 写进 rb FIFO 的字节数 < `dma_req_len`。发射本身（est==1）逐字节查 `!rb_empty`，不会取空 |
| ③ 读出长度 / tlast 早或晚 | **H4** | 长度来自 `len_tab[p_eff]`（`axi4:700`，= 写侧真正入 FIFO 的字节数 `n_push_r`，`frame_mem_if.v:301/329`），tlast 由 shim 在 lane 63 命中 beat_last 时结算（`dma_rd_shim_v2.v:141-157`）。若 DMA 的 TLAST 早到（少 beat）⇒ shim 提前 `frame_done` ⇒ 描述符长度 > 实际字节 ⇒ est==3 永久等待 = H4 |
| ④ FIFO 空/满误判 | §4.4 | `rb_level` 是**未同步的 ui 域值**且方向是**高估**；`wr_full` 用标准 gray 全满判据（`async_fifo.v:65`）。当前被 est==1 的 `!rb_empty` 兜住 ⇒ 不会造成数据错误，**但会让 PRIME 早开始**。这条**与退役改动无关**（frame_mem_if 未改） |
| ⑤ 复位 / 时钟使能被退役改动影响 | §3 Δ1/Δ3 + H3 首条 | 退役改动**没有触碰任何复位**；`aurora_rst`（`aurora:210`）与 `ui_rst_n`（`239`）都与引擎位无关。Δ1 只改 `dma_tready` 的来源，Δ3 只改 shim 的 `s_tvalid` 门控 ⇒ 不产生新的时钟使能/复位 |

---

## 6. 建议的实验顺序（成本从低到高，前 3 项零重建）

| 序 | 实验 | 成本 | 判读 |
|---|---|---|---|
| 1 | 退役位流：上电 → `'d'` → ping ×4（**不跑 round**）→ `'U'` 前后各一次 | ELF 现成 | `WM_RD` 涨 ⇒ H1 排除、进第 4 项；不涨 ⇒ H1 成立，前一轮实验作废 |
| 2 | 绿位流 + `2961b585` + **同一 S2–S6 序列**（round 后 ping） | 位流现成 | 绿也 0/4 ⇒ H1/H2 成立，"位流是唯一变量"不成立 |
| 3 | 退役位流 + `'d'` + `'S'`（显式 SEQ）+ ping；同时读 `WM_RD/WM_WR` | ELF 现成 | 与第 1 项互为对照，排除 RND/命令脉冲两种触发路径 |
| 4 | 新 ELF（**不重建位流**）：`'U'` 增加打印 `mem2_wm/mem2_rd_frame`、`pump_rev_wr/rd`、`link_ok`、`cmd_takeover` | 只重建 ELF | 定位 H3 在第二跳的哪一段（这是最快能证伪 H3 的一步） |
| 5 | 复用现有 ILA：探针改挂 `mem2_rd_en/mem2_rd_data/pump_rev_en/rgmii_tx_en_o` | 只重建位流 | 抓一整帧逐字节，与 10-16 归档 `jb31b_rdcap_*.csv` 对照 |
| 6 | 门级仿真退役网表跑 `bridge_dma_tb`；或造"死代码保留"对照位流 | 离线 | 判定 H4（网表 vs 功能） |

> **不要**在 H1/H2 排除之前再投入"发射口之后"的 ILA 取证：当前唯一的"发射口之后"证据
> （`dbg_emit` 相同 + PC delta=0）来自一轮 `WM_RD` 未推进的实验，而 `dbg_emit` 本身又只覆盖第一跳。

---

## 7. 本报告**不能**证明的事（边界）

- 没有网表、没有 ILA 波形、没有板上复测 ⇒ 无法判定 H3/H4 谁成立；本报告只做**逻辑与证据链**审计。
- 无法确认 `3aa600aa` 的网表是否严格对应当前 RTL（造它的脚本未入库，文档 §补二 §2 已记）。
- 未核实 §补四 那次"绿 3/3"的原始日志（不在 `out/evidence_2026-10-17/` 内；该目录只有退役侧的
  `s2_s6_201701.log`、`s2_s6_204148.log` 与一个内容为 `[%s] %s` 的 `clean_engine1_ping_204258.log`）。
- `'U'` 探针的"首值滞后"是代码注释与日志双重印证的（`main.c:127-151`），但**若**某个寄存器地址
  恰好是"读即弹出"类型，单读才正确（`main.c:157-163` 对 `UART_RX` 的说明）——本报告只对
  `0x08/0x0C/0x18/0x34/0x38/0x3C` 这些只读观测地址用了该规律。

---

## 8. 附：归档日志解码表（`s2_s6_204148.log`，位流 `3aa600aa` + ELF `2961b585`）

| 行 | 打印值（首值为上一地址的滞后值） | 解码 |
|---|---|---|
| S3 `U req` | `50314231 01010076 ×5` | `req=0x01010076`：bit24(engine)=1、bit25=0 |
| S3 `U wmrd` | `01010076 00000002 ×5` | `WM_RD=2` |
| S3 `U wmwr` | `00760155 00000002 ×5` | `WM_WR=2` |
| S3 `U emit` | `0760155 ×3` | `{len=0x76=118, slot=0x01, byte0=0x55}` |
| S6 `U req` | `50314231 00010076 ×5` | `req=0x00010076`：**bit24=0**、bit25=0（与 S3 的 bit24=1 矛盾 ⇒ 引擎位在两处之间被写过，正是 round 收尾 `R_ENGINE=0`） |
| S6 `U wmrd` | `00010076 00000002 ×5` | **`WM_RD=2`（未推进）** |
| S6 `U wmwr` | `00760155 00000007 ×5` | **`WM_WR=7`（+5）** |
| S6 `U emit` | `0760155 ×3` | 与 S3 相同 ⇒ 最后一次发射发生在 S4 之前，S4/S5 期间**零发射** |
| S6 `U mode=1` | — | **这是 `g_dma_mode`（软件标志），不是 `cfg_mode`**（`main.c:470-471`）⇒ 不能用作"engine=1"或"SEQ"的证据 |

> 上表第 5/6/7 行是本报告最硬的事实：**退役配置在那轮 ping 里没有发生任何读出**，
> 而 §补四 声称"两侧 `wmrd` 都 1/1→4/4"。二者必须有一个是错的。
