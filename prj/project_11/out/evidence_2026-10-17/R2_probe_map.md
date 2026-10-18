# R2 ILA 探针 ↔ RTL 信号 ↔ 域 ↔ 位宽 核对表（round2b 裁剪口径）

> 角色：独立审计（rtl-auditor）。本文件**只写可核对事实**；未取到实物证据的字段标 `[待核对]`。
> 依据等级：AGENTS.md §6a。纸面结论 = **[L2]**（脚本 + 冻结 RTL + R1 ltx 三方一致）。
> **重要更新（2026-10-18 12:49，round2b 构建策略）**：为解 place/route 拥塞（首掷 WNS −0.135、route 57–77%、最差路径族扩散），Lead **只裁 ILA 探针集、不改 RTL**——`rtl/axi4_master_bridge.v` 仍 = `06e6bd72…`（TB 无需重跑）。本文按**裁剪后**的 `build_synth_only.tcl` / `build_debug.tcl` 重算（两文件 ILA 段逐行一致，均 12:49:08）。
> **再更新（2026-10-18 14:0x，round2c 时序修复，RTL 新 blob `f43267db…`）**：新增 `WD_ARM=3'd7` 瞬态一拍（`WD_WAITGO` 完成→`WD_ARM` 清拼帧寄存器→`WD_STREAM`）；探针集与位宽**不变**（仍 ILA0 probe0=92/probe1=9/ILA3 probe0=152），但 **`dbg_s2mm_state` 编码新增 7=ARM（每帧瞬态 1 拍，板验/判据忽略；不等于 HALT=6）**。
> 新 ltx 到位后仍按 §5 逐项核对；"探针都在"≠"位宽对"。
> **实物核对已完成（2026-10-18 位流 `28921C6B…` / ltx `4AC25546…`）：§5 全部通过（宽度/位序/核数量/裁剪项缺失），发现 2 处非阻塞事实：`dbg_mem_rden` 在 probe0 bit48 被 Vivado 重命名为 `dbg_mem_rden_1`（同 net 双挂，功能同源）；ltx 不携带 ILA 时钟网名（时钟关联 `[待上板 hw_manager 确认]`，信号域归属已核）。详见 §5.1。**
> **round2d 更新（2026-10-18 17:0x）**：`axi_lite_regs.v` 已合入 AXI 握手修复（blob `421df59c…`→**`d133b508…`**，见 `R2_rtl_audit §15`），**探针集合/位宽/位偏移全部不变**（裁剪后列表不含 lite_* 探针）；其余三文件 blob 不变；新 bit/ltx 到位后按 §5/§5.1 同清单核对，并确认归档 RTL 四副本 hash 集合含 `d133b508…`。
> **round2f 更新（2026-10-18 18:2x）**：bridge `4d1c50c7`（WAITGO 首拍并行执行缺陷 → 独立 TB 判定 FAIL，**未上板**）→ 采纳修正版 fix2，新 blob **`c92c20c7fb1884cb6238daf6e03dd69daa93f172`**；fmi/top/lite 均不变；**探针/ltx 期望仍全部不变**（92/9/152、仅 2 核、裁剪项不出现）；新 bit/ltx 到位后按 §5/§5.1/§5.3 核对，且 bit↔RTL 四副本必须为 round2f 集合（bridge `c92c20c7…`）。
> **round3 草案（2026-10-18 21:0x，待新 ltx）**：Lead 计划新增 `u_ila_5 @ui_clk`（写流 AXIS，5 probe/75b）+ ILA0 追加写入口 9b（probe0 92→101）+ lite fix2 合入；**期望 ltx = 3 核（u_ila_0/3/5）、ILA0 probe0=101 / probe1=9、ILA3 probe0=152、ILA5=64+8+1+1+1**。详见 §5.4。

---

## 1. 依据与推导方法（可复算）

1. **探针列表来源**：`scripts/build_synth_only.tcl` 与 `scripts/build_debug.tcl` 的 `nets0/nets3`（round2b 裁剪后；`#` 开头行不计入）。
   * 解析规则：按脚本**行序**拼接；`one_net X`=1 bit；`bus_nets X N`=N bit（X[N-1:0]）。
2. **位序规则来源**：R1 最终位流 `scripts/probes.ltx`（JSON）的 `pins[].leftIndex/rightIndex/nets[].name`。实测规则：**脚本列表首个 net → probe 位 0（LSB）**，矢量 net 连续占位、`leftIndex..rightIndex` 递增。
3. **交叉验证**：同一解析器复算 R1 四 ILA 宽度与 R1 ltx 实测**逐项相等**（ILA0 374 / probe1 9 / ILA1 111 / ILA2 101 / ILA3 179）⇒ 位序/位宽模型可信。**round2b 期望宽度**：

   | ILA / probe | R1 ltx 实测 | round2（未裁） | **round2b（本次，裁剪后）** | 变化 |
   |---|---|---|---|---|
   | `u_ila_0/probe0` @user_clk | 374 | 376 | **92** | −284 bit（只留 R2 判据必需） |
   | `u_ila_0/probe1` @user_clk | 9 | 9 | **9** | 不变（`dbg_mem_rden` + `mem_rd_data[7:0]`，S8c 用） |
   | `u_ila_1/probe0` @eth_rxc | 111 | 111 | **整核移除** | —（R2 S0–S11 不使用） |
   | `u_ila_2/probe0` @user_clk_b | 101 | 101 | **整核移除** | —（R2 S0–S11 不使用） |
   | `u_ila_3/probe0` @ui_clk | 179 | 184 | **152** | −32 bit（drop bresp16 + wslot8 + rslot8） |

   ⇒ round2b 新增位偏移：ILA0 probe0 = **bits[90:91]**；ILA3 probe0 = **bits[147:151]**（见 §3/§4）。
4. **域归属来源**：冻结 RTL 端口/镜像实现（file:line 见 §2/§3/§4）。

---

## 2. 脚本/RTL 位置索引（file:line，round2b 裁剪后）

| 项 | 位置（`build_synth_only.tcl` 与 `build_debug.tcl` 行号一致） |
|---|---|
| ILA0@user_clk 时钟 | `build_synth_only.tcl:81-83`（`user_clk`；fail 回退 `u_pack/frame_active_reg/C`） |
| ILA0 probe0 nets0 | `:85-98`（probe0 连接 :98） |
| ILA0 probe1 发射字节流 | `:100-107`（`dbg_mem_rden` + `mem_rd_data[7:0]`，连接 :106） |
| ILA1 整核移除 | `:109`（仅注释，无 `create_debug_core u_ila_1`） |
| ILA2 整核移除 | `:111`（仅注释，无 `create_debug_core u_ila_2`） |
| ILA3@ui_clk 时钟 | `:113-130`（`ui_clk`；fail 回退 `u_mem/u_bridge/wst_reg[0]/C`） |
| ILA3 probe0 nets3 | `:132-157`（probe0 连接 :157） |
| R2 探针线声明 | `aurora_mem_bridge.v:1454-1458` |
| `dbg_s2mm_reqpend` 源 | `mem_dma_wr_req[31]`（top :296/:777；`frame_mem_if.v:90/494` user 域镜像） |
| `dbg_wr_fault` 源 | `mem_dma_wr_dbg[31]`（top :296/:778；`frame_mem_if.v:91/510` user 域镜像） |
| `dbg_s2mm_state` 源 | `mem_dbg_wr_state`（top :298/:870；`frame_mem_if.v:93/512` **ui 域直连，无 user 镜像**） |
| `dbg_s2mm_tvalid/tready` 源 | `s2mm_tvalid/s2mm_tready`（top :292；BD `S_AXIS_S2MM` ui_clk 域；`frame_mem_if.v:88-89`） |
| 本轮裁剪注释 | `:90-91`（ILA0 只留判据必需）、`:139`（drop bresp）、`:141`（drop wslot/rslot）、`:143-146`（历史 96bit 教训保留） |

---

## 3. ILA0 @user_clk（u_ila_0，probe0 期望宽 **92**）

### 3.1 probe0 完整位图（顺序 = 脚本顺序 = ltx leftIndex）

| 位偏移 | net | 宽 | 域 | 说明 |
|---|---|---|---|---|
| 15:0 | `dbg_mem_u_wr[15:0]` | 16 | user | 桥① accept 帧数（S6/S10） |
| 31:16 | `dbg_mem_u_rd[15:0]` | 16 | user | 桥① 读出帧数 |
| 47:32 | `dbg_mem_u_drop[15:0]` | 16 | user | 桥① buf_drop |
| 48 | `dbg_mem_rden` | 1 | user | 桥① 读发射 en（probe1 同源位） |
| 57:49 | `dbg_mem_ost_s[8:0]` | 9 | user | 桥① outstanding 灰码镜像 |
| 73:58 | `dbg_mem2_u_wr[15:0]` | 16 | user | 桥② accept 帧数 |
| 89:74 | `dbg_mem2_u_rd[15:0]` | 16 | user | 桥② 读出帧数 |
| **90** | **`dbg_s2mm_reqpend`** | **1** | **user** | **R2 新增**：写引擎请求 pending（user 域镜像） |
| **91** | **`dbg_wr_fault`** | **1** | **user** | **R2 新增**：写路径 fail-stop 粘滞 fault（user 域镜像） |

### 3.2 R2 新增探针语义与期望观测

| net | RTL 源 | file:line | 语义（可核对事实） | 期望观测 |
|---|---|---|---|---|
| `dbg_s2mm_reqpend` | `mem_dma_wr_req[31]`（`{pending,6'b0,toggle,slot,len}` bit31） | top :1457；fmi :90/:494 | 1 = 有写请求待软核服务 | S2（未发 'd'）：首帧后=1，但 **WAITGO 看门狗 ≈56ms 后置 pending=0** ⇒ 抓取窗口须 <56ms；S3/S4 随帧 1→0 脉冲 |
| `dbg_wr_fault` | `mem_dma_wr_dbg[31]`（`{fault,7'b0,last_alloc_slot,last_commit_len}` bit31） | top :1458；fmi :91/:510 | 1 = STREAM/PUSH/WAITDONE 看门狗超时后的 fail-stop 粘滞位（软核 DMACR 复位+清 IOC+翻 ACK 后清 0） | S2–S10 **全程必须为 0**；若=1 且 state=6(HALT) 即写路径 fail-stop |

---

## 4. ILA3 @ui_clk（u_ila_3，probe0 期望宽 **152**）

### 4.1 probe0 完整位图（顺序 = 脚本顺序 = ltx leftIndex）

| 位偏移 | net | 宽 | 域 | 说明 |
|---|---|---|---|---|
| 0 | `dbg_calib` | 1 | ui | MIG init_calib_complete |
| 16:1 | `dbg_mem_wm[15:0]` | 16 | ui | 桥① 写水位（=已提交帧数，S6/S10） |
| 32:17 | `dbg_mem_wr_frm[15:0]` | 16 | ui | 桥① 写提交帧数 |
| 48:33 | `dbg_mem_rd_frm[15:0]` | 16 | ui | 桥① 读退休帧数 |
| 64:49 | `dbg_mem_stall[15:0]` | 16 | ui | 桥① 满槽拒收计数（S10 保留项） |
| 80:65 | `dbg_mem_len_err[15:0]` | 16 | ui | 桥① 长度拒收/异常计数（S10 保留项） |
| 89:81 | `dbg_mem_ost[8:0]` | 9 | ui | 桥① 在驻槽数（S6/S10：应 0） |
| 105:90 | `dbg_mem2_wm[15:0]` | 16 | ui | 桥② 写水位 |
| 121:106 | `dbg_mem2_wr_frm[15:0]` | 16 | ui | 桥② 写提交帧数 |
| 137:122 | `dbg_mem2_rd_frm[15:0]` | 16 | ui | 桥② 读退休帧数（S6：ping +4） |
| 146:138 | `dbg_mem2_ost[8:0]` | 9 | ui | 桥② 在驻槽数（S6/S10：应 0） |
| **149:147** | **`dbg_s2mm_state[2:0]`** | **3** | **ui** | **R2 新增**：写引擎状态 |
| **150** | **`dbg_s2mm_tvalid`** | **1** | **ui** | **R2 新增**：S_AXIS 流 valid |
| **151** | **`dbg_s2mm_tready`** | **1** | **ui** | **R2 新增**：S_AXIS 流 ready |

> **round2b 移除项（原 round2 布局中的位置，现不可观测）**：`dbg_mem_bresp[15:0]`（原 96:81）、`dbg_mem_wslot[7:0]`（原 113:106）、`dbg_mem_rslot[7:0]`（原 121:114）。影响见 §6.2。

### 4.2 R2 新增探针语义与期望观测

| net | RTL 源 | file:line | 语义 | 期望观测 |
|---|---|---|---|---|
| `dbg_s2mm_state[2:0]` | `ro_dbg_wr_state`（bridge `dbg_wr_state`） | top :1454；fmi :93/:512；bridge :626 | 0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT **7=ARM（round2c 新增瞬态 1 拍/帧）** | S4/S5 单帧/4 帧：IDLE→WAITGO→**ARM(7)**→STREAM→PUSH→WAITDONE→IDLE（ARM 仅瞬态 1 拍，快照若恰逢显示 7 属正常，**不要按故障判**；**6(HALT) 只在 fail-stop**；WAITGO 超时（良性丢帧）不出现 6/7） |
| `dbg_s2mm_tvalid` | `s2mm_tvalid`（桥输出侧） | top :1455 | 桥→S2MM 流 valid | S4：与 tready 同拍握手；整帧 beats=ceil(len/64) |
| `dbg_s2mm_tready` | `s2mm_tready`（S2MM 消费侧） | top :1456 | S2MM ready | 正常应随 tvalid 通流；长低 ⇒ S2MM 未 arm/halt（对应 STREAM/PUSH 看门狗） |

> **域纪律警告（坑 #7）**：`dbg_s2mm_state/tvalid/tready` 为 ui_clk，**只能挂 ILA3**；`dbg_s2mm_reqpend/dbg_wr_fault` 是 user 域镜像，**只能挂 ILA0**。

---

## 5. 新 ltx 到位后的逐项核对清单（round2b 口径）

- [ ] ltx 为 **JSON**（`ltx_root.ltx_data[0].debug_cores[]`），`ILA_V3` 核**只有两个**：`u_ila_0`、`u_ila_3`；**不应再有 `u_ila_1`/`u_ila_2`**（若仍有 ⇒ 用了旧 build 脚本/dcp）。
- [ ] `u_ila_0/probe0` 位宽 **92**；条目顺序应为 `dbg_mem_u_wr`(left0,right15) → `dbg_mem_u_rd`(16..31) → `dbg_mem_u_drop`(32..47) → `dbg_mem_rden`(48) → `dbg_mem_ost_s`(49..57) → `dbg_mem2_u_wr`(58..73) → `dbg_mem2_u_rd`(74..89) → `dbg_s2mm_reqpend`(90) → `dbg_wr_fault`(91)。
- [ ] `u_ila_0/probe1` 位宽 **9**（`dbg_mem_rden`@0 + `mem_rd_data[7:0]`@1..8，与 R1 相同）。
- [ ] `u_ila_3/probe0` 位宽 **152**；末 5 bit 必须是 `dbg_s2mm_state`(left147..149，subnets `[2],[1],[0]`)、`dbg_s2mm_tvalid`(150)、`dbg_s2mm_tready`(151)；`dbg_mem_bresp`/`dbg_mem_wslot`/`dbg_mem_rslot` **不应出现**。
- [ ] ILA 时钟：u_ila_0 连 `user_clk` 网、u_ila_3 连 `ui_clk` 网（ltx 无时钟名，需在 ILA 属性/时钟域或 `clk_input_freq_hz` 侧核对；R1 先例 dbg_hub 74.999998MHz）。
- [ ] 若任一不符：**以 ltx 为唯一真值**，先查两个 build 脚本 ILA 段是否一致（:85-157），再查 `one_net` 名字是否真实存在于 netlist——`get_nets` 空会让 `llength` 变短、`port_width` 静默缩水（最易漂移点）。
- 核对方法（可复算，无需 GUI）：
  ```
  python: json.load(open(ltx))['ltx_root']['ltx_data'][0]['debug_cores']
          -> 找 name in (u_ila_0,u_ila_3)；逐条打印 (name,leftIndex,rightIndex,nets[0]['name'],subnets)
  ```

### 5.1 实物核对结果（2026-10-18 归档位流；[L2 构建产物直证]）

**对象**：`out/archive/b31b_r2_2026-10-18/`
* bit：`aurora_mem_bridge_r2_28921C6B.bit`（10,266,180 B）SHA256 = `28921C6B38BE92447950B8C81405F278945529BB007E94461EC2CEEF0D324627` ✅ 与 Lead 值一致；别名 `aurora_mem_bridge_r2.bit` 与 canonical `out/aurora_mem_bridge.bit` 三者 hash 相同。
* ltx：`probes_r2_28921C6B.ltx`（64,593 B）SHA256 = `4AC2554667F94BC3E052E0A652FF2DE322E2CE51FEE2B47399A108DF9E6B7C33` ✅；别名 `probes_r2.ltx` 同 hash。
* **bit↔RTL 绑定核对**：归档 `rtl_axi4_master_bridge.v` 的 `git hash-object` = **`f43267db82b84305cfeb519adcfa76f79443f6b3`**（与本轮冻结 blob 一致）；`rtl_frame_mem_if.v=96d5b136…`、`rtl_aurora_mem_bridge.v=1885225f…`、`rtl_axi_lite_regs.v=421df59c…` 全部与冻结值一致 ⇒ 该 bit 由冻结 RTL 构建（可复算证据）。

**逐项核对（期望值来自 §1/§3/§4，实际值解析自 ltx JSON 的 `debug_cores[].pins[].leftIndex/rightIndex/nets[].name/subnets`）**：

| # | 核对项 | 期望 | 实际 | 判定 |
|---|---|---|---|---|
| 1 | ILA 核数量/名字 | 仅 `u_ila_0`、`u_ila_3` | `u_ila_0`、`u_ila_3`（非 ILA 核：`dbg_hub`、`u_ddr4`） | ✅ |
| 2 | `u_ila_0/probe0` 宽度 | 92 | **92** | ✅ |
| 3 | `u_ila_0/probe0` 位序/名 | u_wr[15:0]/u_rd[31:16]/u_drop[47:32]/rden[48]/ost_s[57:49]/mem2_u_wr[73:58]/mem2_u_rd[89:74]/reqpend[90]/fault[91] | 逐条一致；**唯一命名差异：bit48 = `dbg_mem_rden_1`**（Vivado 对同 net 双挂 probe0/probe1 自动加 `_1` 后缀，功能同源；若工具按名匹配需兼容） | ✅（含命名注记） |
| 4 | `u_ila_0/probe1` 宽度/内容 | 9 = `dbg_mem_rden` + `mem_rd_data[7:0]` | **9**（`dbg_mem_rden`@0；`mem_rd_data` 总线@1..8，subnets [7]..[0]） | ✅ |
| 5 | `u_ila_3/probe0` 宽度 | 152 | **152** | ✅ |
| 6 | `u_ila_3/probe0` 位序/名 | calib0/wm16:1/…/mem2_ost146:138/state149:147/tvalid150/tready151 | 逐条一致（见 verify 结果：14 pins、位区间全同） | ✅ |
| 7 | 末 5 bit | `dbg_s2mm_state[2:0]`@149:147、`dbg_s2mm_tvalid`@150、`dbg_s2mm_tready`@151 | 一致；state subnets 顺序 `[2],[1],[0]` | ✅ |
| 8 | 裁剪项不出现 | `dbg_mem_bresp/wslot/rslot`（及历史未挂 ill/nofrm/wbeats/rbeats）不出现在任何 probe | 全部 **present=False** | ✅ |
| 9 | 时钟网 | ILA0=user_clk 网、ILA3=ui_clk 网 | **ltx 不记录 ILA 时钟网名**（全文仅 `dbg_hub.clk_input_freq_hz=74999998`；`user_clk`/`ui_clk`/`clock` 字串 0 次）⇒ ltx 无法直证；旁证：build 脚本 :81-83/:124-130 显式连 `user_clk`/`ui_clk` + RTL 域归属已核（ILA0 全 user 域信号、ILA3 全 ui 域信号） | ⚠ **`[待上板 hw_manager 确认]`**（非阻塞） |

**核对方法（可复算）**：`python` 读 ltx JSON，按 `pins` 的 `leftIndex/rightIndex` 顺序与 `nets[].name` 逐条比对（本表即由脚本产出，未用 GUI）。

### 5.2 由实物核对新增的板验/工具注意
1. `dbg_mem_rden` 在 ILA0 probe0 的 CSV/ltx 名为 **`dbg_mem_rden_1`**：若 `r2_counter_recon.py`/ILA 解析脚本按 `dbg_mem_rden` 精确匹配 probe0 列，会 miss 该位（当前 recon 未使用该列，风险低；建议匹配时兼容 `_1` 后缀）。
2. ltx 无时钟网名 ⇒ 探针"核↔时钟域"只能靠 build 脚本+信号域或上板 hw_manager 确认；**不影响探针数据语义**（域归属已由 RTL 逐信号核对）。

### 5.3 round2d（lite_regs AXI 修复后）核对补充
* **冻结四文件集合（round2d）**：bridge `f43267db…` / fmi `96d5b136…` / top `1885225f…` / **lite `d133b508…`**。
* **ltx 期望不变**：ILA0 probe0=92、probe1=9、ILA3 probe0=152；仅 `u_ila_0`/`u_ila_3` 两核；`dbg_mem_bresp/wslot/rslot` 不出现；末 5bit 顺序不变（`state[2:0]`/`tvalid`/`tready`）。
* 新增核对项：归档 `rtl_axi_lite_regs.v` 的 `git hash-object` 必须 = `d133b508f80480bb8fa70a7f4a7953a07d8cb230`（bit↔RTL 绑定，旧 bit 28921C6B 对应 421df59c，勿混）。
* `u_ila_5 @eth_rxc` **暂不加**（等 Lead PC 侧零成本判别结果）；`dbg_mem_rden_1` 命名注记与时钟网 `[待上板]` 项维持。

### 5.4 round3 探针草案（Lead 计划，**待新 ltx 实物核对**）

> 来源：Lead 2026-10-18 21:0x 计划（写流字节探针重建一轮）。本节为**纸面草案**，所有"实际 net 名/宽度"以新 ltx 为准；核对通过后本表升级。
> 变更：① 新增 `u_ila_5` @ui_clk（写流 AXIS 观测）；② ILA0 probe0 追加 9b 写入口字节（user 域）；③ lite_regs 合入 fix2（AXIS 握手加固，探针集合无影响）。

#### 5.4.1 期望 ILA 核集合（round3）
| ILA | 时钟 | 期望 probe | 说明 |
|---|---|---|---|
| `u_ila_0` | user_clk | probe0=**101**、probe1=9 | 追加写入口 9b；其余 92b 与 round2f 相同（位偏移 0..91 不变） |
| `u_ila_3` | ui_clk | probe0=152 | 不变 |
| `u_ila_5`（**新增**） | ui_clk | probe0=64、probe1=8、probe2=1、probe3=1、probe4=1 | 写流 AXIS：tdata 低 64b / tkeep 低 8b / tvalid / tready / tlast |
| `u_ila_1` / `u_ila_2` | — | **仍应不存在** | 保持 round2b 裁剪 |

#### 5.4.2 ILA0 probe0 追加段（bits 92..100）
| 位偏移 | 期望 net（建议名） | 源信号（top，user 域） | 宽 | 语义 |
|---|---|---|---|---|
| 99:92 | `dbg_pfwd_data[7:0]` | `pump_fwd_data[7:0]`（泵A 出 → u_mem `.wr_data`，top:188/816） | 8 | 进桥写入口的帧字节（期望首字节序列 55 55 … D5 …；与 `dbg_mem_rd_data`/发射探针对照可分层 写入口/S2MM/读出） |
| 100 | `dbg_pfwd_en` | `pump_fwd_en`（top:188/816） | 1 | 写入口字节有效 |
> 若 Lead 直接用原始 net 名，则 ltx 里应为 `pump_fwd_data[i]` / `pump_fwd_en`；若建 `dbg_*` 别名则按别名。**偏移 92..100 为本草案预测，待 ltx 核对。**
> 注：追加 9b 后 ILA0=101b（历史 376b 过，无预算问题）。

#### 5.4.3 u_ila_5 @ui_clk 布局（75b，建议 5 个独立 probe 以便硬件触发）
| probe | 宽 | 位偏移(该 probe 内) | 期望 net（建议名） | 源信号（top，ui 域） | 判据/期望值 |
|---|---|---|---|---|---|
| probe0 | 64 | 63:0 | `dbg_s2mm5_tdata[63:0]` | `s2mm_tdata[63:0]`（top:291；写引擎 `wd_data_r[63:0]`） | **beat0 = `0xD555555555555555`**（byte0=0x55…byte7=0xD5）；beat1 = 帧字节 64..85（低 22B） |
| probe1 | 8 | 7:0 | `dbg_s2mm5_tkeep[7:0]` | `s2mm_tkeep[7:0]`（top:291） | beat0=`0xFF`；beat1=`0x3F`（低 6 bit=1，覆盖 22 lane 的低 8 位部分） |
| probe2 | 1 | 0 | `dbg_s2mm_tvalid`（复用 ILA3 同名 net 可） | `s2mm_tvalid`（top:292） | 触发用；beat0/beat1=1 |
| probe3 | 1 | 0 | `dbg_s2mm_tready`（复用） | `s2mm_tready`（top:292） | 触发用 |
| probe4 | 1 | 0 | `dbg_s2mm_tlast`（**新增 alias**） | `s2mm_tlast`（top:291） | beat0=0、beat1=1 |
> **为什么拆 5 个 probe**：单 75b 总线探针无法做"tvalid&&tready&&!tlast"的部分位触发；拆开后可用硬件 trigger（probe2==1、probe3==1、probe4==0）抓**首拍**，1024 深度窗口可覆盖 beat0+beat1+帧间隔。
> C_DATA_DEPTH=1024、C_INPUT_PIPE_STAGES=1；@300MHz 为新增负载，若 WNS 紧可先降 IL A3/5 深度或只保留此 75b。
> 采样 CS V 解析：ILA5 有 5 个 probe（64/8/1/1/1），hex 列；判读顺序按表。

#### 5.4.4 `R2_EXPECT_PROBES` 更新草案（`out/r2_ilacap.tcl:117` 的默认值）
```
dbg_s2mm_reqpend,dbg_wr_fault,dbg_s2mm_state,dbg_s2mm_tvalid,dbg_s2mm_tready,dbg_pfwd_data,dbg_pfwd_en,dbg_s2mm5_tdata,dbg_s2mm5_tkeep,dbg_s2mm_tlast
```
* `R2_ILA_MATCH_EXTRA` 草案 = `dbg_s2mm5_tdata`（第三个 ILA pattern；r2_ilacap 已支持该 env，默认空）。
* 期望宽度注释同步：`dbg_pfwd_data 8 / dbg_pfwd_en 1 / dbg_s2mm5_tdata 64 / dbg_s2mm5_tkeep 8 / dbg_s2mm_tlast 1`。
* 存在性检查仍为 WARN-only，不改变 S 判据 PASS/FAIL。

#### 5.4.5 新 ltx 到位后的 round3 核对清单（在 §5 基础上增补）
- [ ] ILA 核 = **3 个**：`u_ila_0`、`u_ila_3`、`u_ila_5`（无 ILA1/2）。
- [ ] ILA0 probe0=**101**：bits 0..91 与 round2f 完全相同；**92..99 为新 8b、100 为 1b**；net 名与上表一致（`dbg_pfwd_*` 或 `pump_fwd_*`）。
- [ ] ILA0 probe1=9 不变；ILA3 probe0=152 不变。
- [ ] ILA5 = 5 个 probe，宽度 **64/8/1/1/1**（总 75b），时钟 ui_clk；net 名与上表一致。
- [ ] 若 ILA5 做成单 75b probe ⇒ 无法做首拍触发，需改为 5-probe 或改用 `-trigger_now` 连续抓（不推荐）。
- [ ] lite_regs 新 blob（fix2 合入后）另行记录；本 ltx 核对不涉及 lite 内部信号（探针集合不含）。

---

## 6. 资源/可观测性影响（round2b）

### 6.1 资源收益（纸面）
* ILA0 probe0 376→**92** bit（−284）；ILA3 probe0 184→**152** bit（−32）；**ILA1(111b)+ILA2(101b) 整核移除**（2 套 ILA 核 + 触发/比较逻辑 + 时钟/布线负载）。
* 动机（Lead 失败轮报告）：首掷 place/route WNS −0.135、最差路径族扩散（`gray→FSM state CE` 桥② 读/写状态 + 新写引擎 lane CE）、route 占 57–77%、`AggressiveExplore` 布局失败 ⇒ 主因判断为**拥塞/资源密度**而非单条锥；裁 ILA 是省资源/布线余量的策略手段。[L1：Lead 归因判断；本表只记录裁剪事实]
* **注意：裁 ILA 不是时序保证**——是否收敛以新一轮 place/route 实测为准。

### 6.2 可观测性损失与判据口径影响（[L2] 纸面逐条对表）
1. **`dbg_mem_bresp` 移除**：DESIGN §10 S10（`out/R2_S2MM_DESIGN.md:167`）要求"错误计数（bresp/len_err/stall 按语义）为 0"——现在 **bresp 项不可观测**（且桥① 在 S2MM 下 bresp 本就无意义：BRESP 在 IP 内部，桥不可见）。⇒ **S10 判据须改为**："`len_err/stall` 按语义为 0；**bresp 项改 INFO/判据未取得**"，不得写"错误计数全 0"（§6a 硬规则 3）。
2. **`dbg_mem_wslot` / `dbg_mem_rslot` 移除**：S6/S11 判据不依赖（S11 槽号本地复算、S6 用 wm/rd_frm/ost）；仅失去调试可见性，无判据影响。
3. **ILA1@eth_rxc / ILA2@user_clk_b 移除**：R2 S0–S11 逐条核对**未引用**（S6/S10 用 ILA3 保留项；S8c 用 ILA0 probe1；S2/S3 用 'U'/ping/NIC）。⇒ 判据无影响；但 **R2 板场次失去 eth 域/B 域交叉观测**（prj9/R1 时代的对照能力），若 S4/S5 出现物理层疑点需回烧 R1 位流或加临时 ILA——写入板验风险备注。
4. **`dbg_wr_timeout` 仍不可观测**（A17，见 §7）。

---

## 7. 纸面核对结论（round2b）

* ILA0@user：probe0 **92 bit**（R2 新增 `dbg_s2mm_reqpend`@90、`dbg_wr_fault`@91），probe1 9 bit 不变；ILA3@ui：probe0 **152 bit**（R2 新增 `state[2:0]`@149:147、`tvalid`@150、`tready`@151）；**ILA1/ILA2 本轮整核移除**。
* 推导方法复用 R1 ltx 位序规则并经 R1 宽度逐一复算校验 [L2]；与 `out/r2_ilacap.tcl` 的探针布局注释（R2 v1.2）无冲突（其只描述"存在哪些探针"，不含位偏移）。
* **判据口径需同步**：S10 的 bresp 项 → INFO/未取得（§6.2-1）；DESIGN §11 K1 若引用"ILA1 probe1"应更正为 **ILA0 probe1**（发射字节流探针）。
* **round2c（`f43267db…`）**：探针位宽/偏移不变；`dbg_s2mm_state` 新增 7=ARM 瞬态（1 拍/帧，板验忽略）；`out/r2_counter_recon.py` 对未知状态值只作 INFO 打印（不参与硬判），无需改动；若需严格可把 7 加进其解码表（Lead 文件）。
* `stat_wr_timeout` 仍不可观测（A17）：板验替代口径 `dbg_wr_fault`+`state==6(HALT)`+`WM_WR` 停滞；不得写"timeout 计数=0"。
* 状态：**纸面核对 [L2] + 实物 ltx 核对已完成 [L2-构建产物直证]（2026-10-18，bit `28921C6B…`/ltx `4AC25546…`；round2d 待新 bit/ltx 后同清单复核，见 §5.3）**；仅 **时钟网关联** 与 **`dbg_mem_rden_1` 命名注记** 两项非阻塞遗留（前者 `[待上板 hw_manager 确认]`，后者工具匹配兼容即可）。
