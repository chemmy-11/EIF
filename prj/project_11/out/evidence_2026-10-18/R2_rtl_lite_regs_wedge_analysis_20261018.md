# R2 板验初场离线判读：Lite 读滞后 / AXI 楔死 / TX 无帧（rtl-auditor，只读分析）

> 依据：`rtl/` 冻结 `f43267db…`（bridge）/`96d5b136…`（fmi）/`1885225f…`（top）/`421df59c…`（axi_lite_regs）；板验日志 `out/evidence_2026-10-18/`。
> 等级：L2=代码级+板上/对照直证；L1=假说（需探针判别）；L0=猜测。**本文件不产生定论，供 Lead 并入 RTL 修改。**

---


---

## 0. 【已确认·L2 实测】根因：`axi_lite_regs` 读/写通道 **VALID 多拍** → AXI 重复握手

> 结论先写：**A 与 B 是同一个 RTL bug**——`s_axi_rvalid` / `s_axi_bvalid` 只在 `LR_IDLE`/`LW_IDLE` 清，而 FSM 在 `LR_DACK`/`LW_CLOSE` 还会停留数拍；主端 `rready`/`bready` 常高时，**单次读/写会在总线上产生 5 个 R / 5 个 B 握手**（AXI4-Lite 协议违例）。互连（SmartConnect/MicroBlaze）的读写跟踪被多余响应打乱 ⇒ A 的"读到上一地址数据"、B 的"事务失步→永久楔死"。这是**离线单元仿真 [L2] + 代码定位**，已用修复副本仿真验证修复有效。

### 0.1 实测定量（`sim/r2_tmp/r2_lite_proto_tb.sv`、`r2_lite_write_proto_tb.sv`；日志见 §证据）
* **冻结版本**（`rtl/axi_lite_regs.v` blob `421df59c…`）：
  * 单次读：`AR_HS=1 → R_HS=5`（rvalid 连续 5 拍为高、rready=1 → 5 次 R 握手，后 4 次为重复响应）；
  * 单次写：`AW_HS=1, W_HS=1 → B_HS=5`；
  * 背靠背双读：2 AR → 5 个 R 且数据错位（0x40/0x44 两个地址都返回 0x44 的值）。
* **修复副本**（`sim/r2_tmp/axi_lite_regs_fix.v`，仅 3 处改动，见 `R2_axi_lite_regs_fix.diff`）：
  * 单读 `AR_HS=1 R_HS=1`、单写 `B_HS=1`、`dup_r_cycles=0 dup_b=0`；
  * 背靠背双读：2 AR → 2 R，**数据各自正确**（0x40→`DEADBEEF`、0x44→`CAFEF00D`），"上一地址数据"现象消失。

### 0.2 代码定位（`rtl/axi_lite_regs.v`）
* 读：`s_axi_rvalid` 仅在 `LR_IDLE` 的 `if (s_axi_rvalid && s_axi_rready)` 清（:259）；`LR_DRQ` 置位（:291）后进入 `LR_DACK` 等 `!d_req_s[1]`（:297，2FF 回程 ≈4 拍），期间 rvalid 一直高且不再被清 ⇒ 重复 R。
* 写：`s_axi_bvalid` 仅在 `LW_IDLE` 清（:184）；`LW_EXEC` 置位（:223）后进入 `LW_CLOSE` 等 `!a_ack_s[1]`（:229），期间 bvalid 一直高 ⇒ 重复 B。
* 附带：`LR_IDLE` 在捕获 AR 当拍又置 `arready<=1`，下一拍进 `LR_RACK` 时 arready 输出仍=1（:266-272）⇒ 流水主端的第二个 AR 可能"总线握手但被 FSM 丢弃"（本 bug 的次级窗口，与重复 R 叠加更易楔死）。

### 0.3 修复（供 Lead 并入 RTL；diff 已给出，改动最小）
1. **读/写都改"握手即撤销 VALID"**：在读/写 always 的 `case` 之前各加一条无条件清除：
   `if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;`
   `if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;`
   并删除/保留 IDLE 内原清除行（重复无害）。
2. **非 IDLE 态 ready 拉 0**：`LW_EXEC`/`LW_CLOSE` 加 `awready<=0; wready<=0;`；`arready` 改单拍（先拉高一拍，握手拍撤销）——消除"接受后 ready 仍高 1 拍"的丢 AR 窗口。
3. **（防御，建议同批加）** 邮箱超时：`LR_RACK/LR_DRQ/LW_EXEC` 加 ~4096 aclk 周期超时 → 清邮箱 + **SLVERR 完成响应**（读 `rvalid=1,rresp=SLVERR`；写 `bvalid=1,bresp=SLVERR`） + 32b sticky `mbox_fault` 寄存器（新 Lite 读地址如 +0x50），把未来任何 reset 失配/握手丢失从"死机"降级为"可观测 SLVERR/计数"。
4. （可选）统一 `aresetn` 与 `rst_user_n` 的**邮箱复位**：当前 `aresetn=rst_100m/peripheral_aresetn`、`rst_user_n=~aurora_rst`（`~sys_rst_n|~link_ok`，top:210）不同源；单侧复位会丢邮箱状态（3 的超时是兜底）。

### 0.4 对 A/B/C 的重新解释
* **A（读滞后）**：R1 期" M01 读滞后"（坑 #39）的**真正根因就是本 bug**——单次读返回多个 R 响应，互连把多余响应当成随后事务的响应，表现为"读落后 1–2 笔/交替地址串味"；`rd_reg()` 的哑写+延时只是碰巧改变节奏使现象缓解。[L2：当前文件仿真直证；R1 历史文件未逐字比对 → R1 部分标 L1]
* **B（楔死）**：多余 R/B 使 SmartConnect/MicroBlaze 读写跟踪失步；写后紧接读（SET_WRGO→读 WR_DBG/WRREQ）时读写重复响应叠加，最易触发某笔事务永无响应 ⇒ `lwi` 永久挂、`rst -processor` 无效、只能重配 FPGA。高频率服务循环（143kHz）≈ 更密集的重复响应 ⇒ 与"1ms 限速可存活、偶发仍楔死"吻合。[L2 机理 + L1 板端对应关系（待修复后板验确认）]
* **C（TX 无帧）**：与本 bug 无直接因果（C 的桥②/泵B 是独立硬件路径），但**楔死会让桥①读服务停摆/干扰观测**；建议 A/B 修复后再做 C 的最小序列判定（PC 侧抓包优先，见 §C）。

### 0.5 证据文件
* `out/evidence_2026-10-18/R2_sim_lite_proto_frozen_r.log`（冻结：FAIL，1AR→5R）
* `out/evidence_2026-10-18/R2_sim_lite_proto_frozen_w.log`（冻结：FAIL，1AW/W→5B）
* `out/evidence_2026-10-18/R2_sim_lite_proto_fix_r.log`（修复副本：PASS，1AR→1R，双读数据正确）
* `out/evidence_2026-10-18/R2_sim_lite_proto_fix_w.log`（修复副本：PASS，1AW/W→1B）
* `out/evidence_2026-10-18/R2_axi_lite_regs_fix.diff` / `R2_axi_lite_regs_fix.v`（建议补丁与完整修复副本；**我未写 rtl/**，由 Lead 决定是否合入）
* TB：`sim/r2_tmp/r2_lite_proto_tb.sv`、`sim/r2_tmp/r2_lite_write_proto_tb.sv`（可复跑：`xvlog -sv rtl/axi_lite_regs.v <tb>` → `xelab` → `xsim -runall`）

## A. Lite 读滞后（固件 `dread` 2 读 → pending 永不置 1）

### A1 结论（[L2] 代码级：lite_regs 不可能返回"上一地址"的数据）
`axi_lite_regs.v` 读通道是严格串行的 4 相邮箱，数据与地址一一对应：
* `LR_IDLE` 仅在 `!s_axi_rvalid && !r_ack_s[1]` 时放 `arready`，捕获 `r_addr`(+0x269)；
* `LR_RACK` 等 `r_ack_s[1]` 后才清 `r_req`（+0x283-285）；
* `LR_DRQ` 等 `d_req_s[1]` 才把 **user 域按 `r_addr` 快照出的 `d_data`** 装入 `s_axi_rdata`（:289-294；快照见 `UR_IDLE` :459-487）；
* 前后两笔之间必须走完 `LR_DACK→LR_IDLE` 且 `r_ack_s[1]==0`（:296-300）。
⇒ lite_regs 内部**没有**"上一笔数据"通路；`r_addr` 在 `r_req` 之后才被 user 域使用，且前一笔彻底关闭前不会接受新 AR（[L2] 静态代码+时序推演）。

### A2 滞后来源：**已改判**——根因是 §0 的 lite_regs 重复 R 握手（原"M01 读滞后/坑 #39"是其外部表现）[L2]
* R1 已实证：经 SmartConnect M01 的 Lite 读**第一笔可能陈旧、同址连读第二笔正确**（记录见坑 #39；`rd_reg()` 哑写+双读即为此而生）。
* 本轮现象（`R2_manual_rd3test.log`）：`U id:` 首笔读到上一地址值（`00010056`），后续同址 5 笔正确；交替地址两笔读对不上 → 与"读数据滞后 ≥1 笔"完全一致。
* **2 读失败 / 3 读成功**现象与"单读返回多份 R、互连把多余响应分给后续读"一致（与 "深度 2 的互连滞后" 等效）；**真正的修复是 §0 的 RTL 补丁**，而非继续加读次数。
* （旧解释，保留供对照）≈2 笔滞后 = 2 读失败/3 读成功的等效描述（[L1] 由实测反推；R1 期表现为 1 笔，深度随互连/负载可能变化）。注意：这是**互连侧**现象，不是 lite_regs 串行化的必然结果（A1），故改 lite_regs 不能直接消除它。

### A3 读原语建议（固件侧；按稳健性排序）
1. **`rd_reg()` 口径（R1 已板证）**：哑写（+0x2C）+ 短延时 + **同址 2 读取第 2 读**。哑写冲刷读管线；对"滞后 1–2 笔"都有效。代价：必须插延时，别用 `busy_ms(1)`（≈0.15ms，143kHz 环撑不住）；建议 8–16 个 NOP/循环即可。
2. **快速路径：同址 3 读**（不是交替地址各 2 读）：若滞后深度确为 2，第 3 读必新；实现上 `dread3()` 三次读同一指针、用第 3 次。**风险**：深度若偶发变 3（互连仲裁/背压）会再踩；建议仅在"轮询 pending"这类可重试语义上用，并在读到 pending=1 后再用 `rd_reg` 复核一次（arm 决策只做一次/帧，慢速代价可接受）。
3. **根本缓解**：把服务轮询降到 ≤1kHz（J3 pace 1ms 足够）——这也同时降低 B 的楔死暴露概率；`serve_any` 的读频度不必 143kHz。

---

## B. AXI 楔死（高频率 Lite 读后 MicroBlaze 挂 `lwi`，只能重配 FPGA）—— 根因见 §0；下面 B1–B3 为同批建议修的附加强化项

### B1【高·协议缺陷，[L2] 代码级】读通道 `arready` 在握手后多高 1 拍 → 可能吞掉第二个 AR
`axi_lite_regs.v:257-277`：
```
LR_IDLE: if (!rvalid && !r_ack_s[1]) begin
    s_axi_arready <= 1'b1;
    if (s_axi_arvalid) begin r_addr<=...; r_req<=1; lrst<=LR_RACK; end   // ← 未检查 arready 当前电平
```
* 问题 1：捕获条件只看 `s_axi_arvalid`，不看 `s_axi_arready`（可在 ready 输出为 0 的拍"预捕获"，属非标握手）。
* 问题 2：接受当拍又执行 `arready<=1`，**下一拍 state=LR_RACK 时 arready 输出仍为 1**（RACK 才刚把它清 0）。若主端（SmartConnect/AXI4 流水）在该拍仍在发 AR，**AR 被总线握手但被 FSM 丢弃** → 该笔读永远等不到 R → MicroBlaze `lwi` 永久挂起（无超时）→ 只能重配。这是"读侧楔死"最符合现象的单点机制（[L1] 需探针确认主端是否流水）。
* 修法（建议）：
```
LR_IDLE:
  if (!rvalid && !r_ack_s[1] && !s_axi_arready) s_axi_arready <= 1'b1;
  else if (s_axi_arready) begin
      if (s_axi_arvalid) begin
          s_axi_arready <= 1'b0;            // 接受当拍即撤销，单拍脉冲
          r_addr <= s_axi_araddr[7:2]; r_req <= 1'b1; lrst <= LR_RACK;
      end
  end
  else s_axi_arready <= 1'b0;
```

### B2【高·协议缺陷，[L2] 代码级】写通道 ready 在非 IDLE 态保持旧值 + 可吞 AW/W + B 覆盖风险
`axi_lite_regs.v:181-234`：
* `LW_EXEC/LW_CLOSE` **完全不赋值** `awready/wready` → 输出保持上一个 IDLE 拍的值（常为 1）。期间若主端完成 AW/W 握手，FSM 不锁存（`!aw_pending` 门）→ **写被吞**、且不产生该笔 B（主端可能拿上一笔 B 冒充）⇒ 写/读混合流量下总线可楔死。
* `s_axi_bvalid <= 1'b1` 在 EXEC 无条件置位；若上一笔 B 尚未被 `bready` 取走，存在 B 响应覆盖/合并风险（AXI 要求单笔 B 未完成前不得再接受同通道新写）。
* 修法：非 IDLE 态 ready 赋 0（或改组合 ready）；仅在 IDLE 且 `!bvalid` 时接受新 AW/W；BVALID 置位前确保上一 B 已握手。

### B3【高·结构性单点故障，[L1]】邮箱无超时 + 两侧复位不对称 → 永久挂
* 两侧时钟/复位源不同：`aresetn=rst_100m/peripheral_aresetn`（`create_bd_b.tcl:169-176`），而 user 侧 `rst_user_n=~aurora_rst`、`aurora_rst = ~sys_rst_n | ~link_ok`（`aurora_mem_bridge.v:210`）。**任一侧单独复位/脉冲**（link_ok 抖动、Aurora 链路重训、pma 杂散）都会让 4 相邮箱丢失状态：
  - 若 user 侧复位：`r_ack/d_req` 丢失 → aclk 侧 FSM 永久停在 `LR_RACK`/`LR_DRQ`；`a_ack` 丢失 → `LW_EXEC` 永久停 → 写通道也挂。**没有超时，AXI 事务永不响应 ⇒ 与"只能重配 FPGA"吻合**。
* 修法（门槛低、收益大）：
  1. `LR_RACK/LR_DRQ/LW_EXEC` 各加 ~4096 aclk 周期超时：超时后**清邮箱、给 SLVERR 完成响应**（读：`rvalid=1,rresp=SLVERR,rdata=0`；写：`bvalid=1,bresp=SLVERR`），保证 AXI 永不悬挂；
  2. 加 32b sticky `mbox_fault` 寄存器（bit0 read-timeout/1 write-timeout/2 假 AR 握手/3 假 AW-W 握手/4 reset 失配），经 Lite 读回（新地址，如 +0x50）+ ILA 探针；固件 `'U'` 打印；
  3. 长期：把 `aresetn` 与 `rst_user_n` 的**邮箱部分**做统一复位（任一侧复位时对邮箱 FSM 产生跨域复位脉冲，或至少让 aclk 侧把 user 复位 2FF 进来看作"邮箱复位"）；
  4. **先做 (1)+(2)** 即可让楔死变成"可观测的 SLVERR/计数"而不是死机，且能定位是读还是写通道先挂。

### B4【中·CDC 规范】`r_addr[5:0]` 从 aclk 直接给 user 域 case 使用（:463）
* 依赖"r_req 2FF 后 r_addr 已稳定 ≥2 拍"的准静态前提；当前成立，但按 AGENTS §5.1 属"数据+握手"型 CDC，建议注释固化或随 `r_req` 打 2 拍（若改，面积可忽略）。

### B5【低】`s_axi_bvalid` 单驱动只在 IDLE 清；`s_axi_rvalid` 单驱动只在 IDLE 清 —— 结构可以，但需配合 B1/B2 的 ready 修正一起复核。

### B6 建议的探针/诊断清单（供你重综合加 ILA）
**新 `u_ila_4 @clk_100m`（约 28b，eth 域余量大）**：
`aresetn`、`lrst[1:0]`、`lwst[1:0]`、`s_axi_arvalid/arready/rvalid/rready`、`s_axi_araddr[7:2]`、`s_axi_awvalid/awready/wvalid/wready/bvalid/bready`、`r_req`、`r_ack_s[1]`、`d_req_s[1]`、`d_ack`、`a_req`、`a_ack_s[1]`、`rst_user_n`(2FF 进 100M)。
**触发条件（任一）**：
1. `lrst==LR_RACK && !r_ack_s[1]` 持续（用 ILA basic trigger 电平即可，抓 2048 窗口看是否卡死）；
2. `lrst==LR_DRQ && !d_req_s[1]`；
3. `lwst==LW_EXEC && !a_ack_s[1]`；
4. **假握手**：`s_axi_arvalid && s_axi_arready && (lrst!=LR_IDLE)`；`s_axi_awvalid && s_axi_awready && (lwst!=LW_IDLE)`；
5. `!aresetn || !rst_user_n` 边沿（复位失配时刻）。
**ILA0@user 追加 12b（92→104，仍远低于原 376）**：`ust[1:0]`、`urst[1:0]`、`a_req_s[1]`、`a_ack`、`r_req_s[1]`、`r_ack`、`d_req`、`d_ack_s[1]`、`cfg_wr_go`、`cfg_wr_ack` —— 直接看"SET_WRGO 写后紧接读"时两侧握手是否闭合。
**若不想加 ILA 4**：至少把 B3(1)(2) 的 timeout+sticky 寄存器做进 RTL，用固件 `'U'` 读回（0 成本观测，且能把楔死后的现场留在寄存器里）。

---

## C. 写提交后 PC 收不到帧（rd_frm 在涨）—— 读出流→eth TX 耦合判读

### C1 路径事实（[L2] RTL 接线 + ILA 数据）
回路：`eth RX→栈→泵A→桥①写(S2MM)→[firmware MM2S 服务]→桥①读 mem_rd_data/en → u_pack(8→64) → Aurora A TX →光纤→ Aurora B RX → u_unpack_b/u_pack_b(B 回显) → Aurora B TX →光纤→ Aurora A RX → u_unpack(64→8) → 桥②写 → 桥②硬件读 mem2_rd_data/en → u_pump_rev(user→eth_rxc) → TX mux → gmii_to_rgmii → PHY`
* 代码位置：`u_pack` :1229-1241；`u_unpack`(A RX) :1246-1259；`u_pump_rev` :1264-1276；TX mux :1293-1296；`gmii_to_rgmii` :~515-530。
* **IA 实测（s4emit 16:56–16:57）**：`mem wm/wr/rd = 7/7/7`、`mem2 wm/wr/rd = 7/7/7`、`mem2_ost=0`、`s2mm_state=0`、`tready=1`；user 侧 `mem2_u_wr=mem2_u_rd=7`。
  ⇒ **到"桥②读出口"为止全链路都已跑通**；剩余未观测段只有 **u_pump_rev → TX mux(cmd_takeover) → gmii_to_rgmii/PHY** 三处（均在 eth 域，本轮 ILA1 已裁）。[L2]
* 该段 RTL 与 R1 **逐字相同**（`aurora_mem_bridge.v` hash `1885225f…` 自 R1 未变）⇒ 若是"腿卡死"，更可能是**状态/时序/PC 侧**而非 R2 写路径改动；但若是"帧内容/长度损坏"，则来源可能回到 **S2MM 写槽内容/len_tab（A9 TKEEP 尾拍风险）**，需 S4 逐字节先证。

### C2 判定优先级（先做零成本，再决定是否加 ILA）
1. **PC 侧零成本判别（无需重综合）**：`Get-NetAdapterStatistics` 看 `ReceivedErrors/ReceivedDiscarded/Outbound...`；用 Wireshark/pktmon 以混杂模式抓 192.168.1.10 方向帧（含 CRC 错误）。
   * 若"完全无帧"→ TX 腿（pump B/mux/PHY）问题；
   * 若"有帧但被判坏/长度怪"→ 帧内容/长度问题（回到 A9/槽内容）；
   * 若 NIC 计数显示收到但 `ReceivedBytes` 判据口径问题（广播/dst MAC）→ 判据脚本侧（已知 kink：板自发帧 dst 为广播，`ReceivedUnicast` 不可用，只认 `ReceivedBytes`）。
2. **eth 域最小 ILA（若确需重综合）**：`u_ila_5 @gmii_rx_clk(eth_rxc,125M)` 约 **35b**（该域 R1 余量 1.248ns，35b 很轻）：
   `rgmii_tx_en_i`、`rgmii_txd_i[7:0]`、`rgmii_tx_en_o`、`cmd_takeover`、`cmd_resp_busy`、`tx_idle_cnt[6:0]`、`stack_tx_en`、`pump_rev_rd[7:0]`、`pump_rev_drop[7:0]`（=1+8+1+1+1+7+1+8+8）。
   触发：`rgmii_tx_en_i` 上升沿（抓下一帧波形，看前导 55..D5/长度/是否被 takeover 劫持）；或 `pump_rev_drop != 0`；或 `cmd_takeover` 上升沿。
   * 若 `rgmii_tx_en_i` 完全不翻 → pump B 没出字节（看 `pump_rev_rd/wr` 是否推进、`cmd_takeover` 是否吸死）；
   * 若 `rgmii_tx_en_i` 正常翻但 PC 无帧 → mux 后/rgmii TX/PHY/PC 侧，重点看 `cmd_takeover`/`cmd_resp_busy` 是否被粘住（cmd_channel `resp_busy` 若因历史命令未完成而卡高，会把 TX 全面劫持——[L1]，可先用 JTAG 读 `cmd_channel` 状态/或加 1b 探针快速排除）。
   * 若 `pump_rev_drop` 增长 → pump B 写侧溢出（eth TX 反压），看 `pump_rev_rd` 是否推进。
3. **帧内容/长度**：待 AXI 楔死修好、S4 能稳定跑后，用 ILA0 probe1 发射字节流（`mem_rd_data[7:0]` + rden，本 bitstream **保留**）抓一帧，与 PC 期望序列比较；重点看 86B 尾拍是否 86 字节（多/少 8B 前导问题即 R1 已修的 DROP_BYTES 口径）。

### C3 与 A/B 的耦合
* 若 B 的楔死发生在"服务读请求"路径（`serve_dma_once` 在 0x34 读上挂），则**桥①读服务停摆**；但 s4emit 时 rd_frm 已到 7，说明捕获时刻服务是通的。**建议 A/B 修好后重新跑最小序列（'d' → 1 ping → 等 2s → 'U'）**，再判 C，避免在楔死干扰下误判。

---

---

## E. round2f 上板后更新（2026-10-18 21:0x）：A 残留竞争复核 + B(TX 无帧) 证据与探针方案

### E.1 A：lite 修复后仍楔死（读 +0x40；busy_ms 规避）——新增候选补丁 fix2
* 板端事实（Lead）：wedge 挂点 = `dread()` 读 lite_regs **+0x40**（PC 停 `lwi`，`g_dbg_addr=0x44A00040`）；在 S2MM `R_WRGO` 写后加 `busy_ms(1)` 即不再楔死 ⇒ 与"写后紧接读"强相关。
* 代码再审视（当前 `axi_lite_regs.v`=`d133b508`）：写通道 `LW_IDLE` 仍是**寄存器 ready 尾窗**：
  `s_axi_awready <= !aw_pending` / `s_axi_wready <= !w_pending` 在握手拍又对旧值赋值 ⇒ 握手后下一拍 ready 输出仍为 1，若互连/主端在此拍推进下一笔 AW/W，会**总线握手成功但 FSM 因 `!aw_pending` 门丢弃** ⇒ 互连永等该笔 B ⇒ 后续读被阻塞/`lwi` 卡死（[L1] 与"写后紧接读"吻合）。另：`bvalid` 未消费时可接新写、读 AR 与写事务无串行化，放大该窗口。
* **候选补丁 fix2（已生成并仿真验证，未改 rtl/）**：
  `sim/r2_tmp/axi_lite_regs_fix2.v` / `axi_lite_regs_fix2.diff`：① AW/W ready 改**单拍握手**（拉高到握手为止，握手拍拉低，消除尾窗）；② `bvalid` 未消费前不接受新写；③ 写事务（FSM/待锁存/B）完全关闭前不接受新 AR（串行化"写后紧接读"）。
  验证（离线单元 TB）：单读/单写仍 PASS；**背靠背两笔写 → AW/W/B = 2/2/2 PASS**（当前版本同一 TB = 1/1/1 FAIL ⇒ 第二笔写无法完成）。TB：`sim/r2_tmp/r2_lite_pipe_wr_tb.sv`（新）。
* 建议：A 项下一轮可合入 fix2（低风险，100MHz 域），同时保留固件 busy_ms 直到板证；若仍复现，再加"读/写邮箱超时→SLVERR + sticky"（把死机降级为可观测错误），并加 lite 域探针（见 E.2 资源讨论）。

### E.2 B：TX 无帧——新证据 / 零重综合判别 / 探针方案复核 / 厂商判读口径
**新证据（本机解析 round2f ILA）**
* `R2_ila_emittrig_user_post.csv`（trigger=dbg_mem_rden 上升）：发射流恰为**一次 86 拍连续 rden=1**（长度正确=86），`mem_rd_data[7:0]` 采样 = **84 个 0xFF + 位置 73=0xEF + 位置 80=0xFD**（其余全 FF）⇒ 读出的 86 字节内容 ≈ 全 1，而非期望的 `55×7,D5 + 帧`。
* 因此方向：rb FIFO（读侧字节 FIFO）内容≈0xFF ⇐ shim 从 MM2S 流拿到的就是 0xFF，或槽内容/MM2S 参数异常；结合 R1 同板同线 ping 4/4 ⇒ 链路/PHY/PC 正常，问题在 R2 数据面（写侧→DDR 槽内容，或 MM2S 读请求参数）。
* **零重综合判别（优先做，最快）**：运行固件 `'F'` 命令（`sw/src_j3/main.c:735-768`）：对**最后提交槽** `SA-64/SA/SA+64` 各做一笔 MM2S 64B，回读 dma_sink q1=该笔流首拍 4 字节 LE。期望：
  * `q1[0] = 0x55555555`（前导+SFD 前 4 字节 55 55 55 55）；`q1[-64]` = 上一槽尾部、`q1[+64]` = 下一槽开头（通常非 55 序列）；
  * 若 `q1[0]=0xFFFFFFFF` ⇒ 槽内容全 1 / 未写；
  * 若 `q1[-64]` 或 `q1[+64]` 才是 `0x55555555` ⇒ 写入地址偏移（±64B）；
  * 若 `q1[0]` 为字节反序（如 `0xD5555555`）⇒ 首拍 lane 序/前导位置问题。
  该命令不依赖写路径，可在现 bit+固件上直接跑 ⇒ **先做 'F' 再决定是否重建**。

**探针方案复核（重要修正：域不匹配）**
* **`m_axis_s2mm_*` 在 ui_clk（300MHz）域；ILA0 是 user_clk（151.5MHz）域 ⇒ 不能加到 ILA0**（跨域采样数据无意义）。
* 可选方案：
  1. **新建小 ILA `u_ila_5` @ui_clk**：推荐 `m_axis_s2mm_tdata[63:0]` + `tkeep[7:0]` + `tvalid/tready/tlast` = **75b**（C_DATA_DEPTH 1024，C_INPUT_PIPE_STAGES 1）。这是唯一能完整核对"首拍 55×7,D5"的方案；timing 风险中等（新核、探针在寄存器 Q 上），若 WNS 紧可先只 42b（tdata[31:0]+tkeep+tvalid/tready/tlast）但只能看到前 4 字节。
  2. 加到 ILA3（152→227b @300MHz）：**不建议**（W6 教训：300MHz 加挂曾致 WNS −1.142）。
  3. **低成本替代（user 域，可加 ILA0）**：`mem_wr_data[7:0]` + `mem_wr_en`（pump A→桥写入口，user_clk 域）9b——现有 ILA0=92b，**不必移走 mem2_u_***（101b 远低于历史 376b）；用于核对"进桥字节"是否 55…；配合 'F' 可把故障分层到"写入口 / S2MM / MM2S 读出"。
  4. 触发建议（ui ILA）：`tvalid && tready && !tlast`（首拍触发，窗口含末拍）或 `tlast && tvalid && tready`（尾拍触发，窗口含首拍）；`R2_EXPECT_PROBES` 里加 `m_axis_s2mm_tdata`。
* **位预算**：ILA0 加 9b 无需裁任何现有探针（92→101b）；ui 新 ILA 75b 属新增；若必须腾面积，优先降 ILA3 C_DATA_DEPTH（2048→1024）而不是再裁判据探针。

**厂商判读口径（本机 Vivado 2023.1 数据直证）**
* IP 配置（生成 wrapper）：`C_S_AXIS_S2MM_TDATA_WIDTH=512`、`C_M_AXI_S2MM_DATA_WIDTH=512`、`C_INCLUDE_S2MM_DRE=0`、`C_S2MM_BURST_SIZE=16`；`C_INCLUDE_S2MM_DRE` 仅在 stream width<128 时可选（`component.xml` 依赖）⇒ 512b 无 DRE，SA 必须对齐（4KB 槽基址 ✓）。
* **生成网表含 `\GEN_INDET_BTT.*` / `\GEN_ENABLE_INDET_BTT.*` 层级、无 `sig_strt_strb_reg`** ⇒ 本实例 **C_ENABLE_INDET_BTT=1（Indeterminate BTT 生效）**：S2MM 的 **WSTRB 来自 stream TKEEP**（datamover `axi_datamover_v5_1_vh_rfs.vhd:16429-16437`），**TLAST 终止传输**。⇒ **尾拍 TKEEP/TLAST 是真判据（A9 风险为真，不是被 BTT 掩盖）**。
* 数据 lane 映射：datamover 等宽路径 `sig_data2mmap_data <= s2mm_strm_wdata`（同文件 :15953）**无 lane 交换** ⇒ **TDATA lane k → 内存地址 +k**（AXI4-Stream 首字节在 TDATA[7:0]）。
* **捕获判据（ui ILA）**：
  * beat0：`tdata[63:0] = 0xD555555555555555`（byte0=0x55, byte7=0xD5）、`tkeep=0xFFFF_FFFF_FFFF_FFFF`；
  * beat1（86B 帧）：`tdata[63:0]` 低 22 字节 = 帧字节 64..85，`tkeep = 0x0000_003F_FFFF`、`tlast=1`；
  * 若 beat0 即 FF/0 ⇒ 写引擎/上游数据源问题；若 beat0 正确而 'F' 读槽为 FF ⇒ S2MM 写入参数/地址/MM2S 读出问题。

### E.3 结论/下一步（供 Lead）
1. **先跑 'F'**（零重建）判定槽内容；这决定 B 是"写侧内容错"还是"读侧参数错"。
2. 若重建：按 E.2 方案 1 加 ui ILA（75b）或方案 3 加 ILA0 写入口 9b；probe map 需同步更新（届时我核对 ltx）。
3. A 项 fix2 可随同一轮重建合入（验证证据在 E.1）；保留 busy_ms 直到板证。

## D. 建议的最小操作序列（**先合入 §0 补丁再跑**）（区分触发点，每步记录 `'U'` + ILA 触发）
1. 仅 'U' ×20（无 'd'、无 ping）——基线 + 看读滞后形态；
2. 'd' → 等 2s → 'U' ——只有 GO/read-service 初始化，无帧；
3. 'd' → 1 ping → 等 2s → 'U' ——首帧写入+MM2S 读出（看 wm/rd_frm/s2mm_state）；
4. 'd' → 连续 ping ×4 → 'U' ——写+读并发（楔死最可能触发点）；
5. 若 3 步即楔死：缩小到"仅 'd'+1 ping"；若 2 步即楔死：仅 'd' + 读轮询；逐步二分。
每步后 JTAG 读：`lrst/lwst` 快照（需 RTL 加 sticky）或 ILA 触发捕获。

---
*本文件由 rtl-auditor 产出。**§0 为已实测确认的根因（单读=5 R、单写=5 B 握手）+ 已验证修复补丁**；B1/B2 是附带协议窗口修复（建议同批合入），B3 的 timeout+sticky 为防御性建议。C 建议先做 PC 侧零成本判别再决定加 eth 探针；A/B 修复后再判 C 最干净。*
