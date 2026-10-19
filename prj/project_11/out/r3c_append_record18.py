# -*- coding: utf-8 -*-
"""Atomic append §十八 to the R2 record (pit #24: temp file + os.replace)."""
import io
import os

P = r"C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md"

SECTION = r'''
## 十八、round3c 探针构建与板端新证据（2026-10-19 午）

> 本会话（11:52–14:1x）：先读交接单/AGENTS/§十二–§十七；随后并行组队（rtl-auditor 审计、script-tools 工具链）+ Lead 独占构建与上板。
> 结论等级按 AGENTS §6a 标注；低于 L2 只能作假设。

### 18.1 round3c 探针设计（RTL/BD 改动，功能逻辑零改动）

- **目标仪器**：① lite_regs AXI 侧楔死探针（aclk 域）；② 桥①写引擎 GO/ACK/introut 链（ui 域）。
- **BD 内 module ref 无法从顶层直接挂 ILA**（`build_r2_synth.log`：lite_regs 是独立 OOC run，synth_1 只见 stub/blackbox）⇒ 方案改为：
  1. `rtl/axi_lite_regs.v` 增加**纯观测** output `[35:0] dbg_o`（AXI 握手 10b、地址解码 8b（+0x34/+0x40/+0x44/+0x0C/+0x48/+0x4C/其它）、lwst/lrst 4b、aclk 侧邮箱 6b（a_req/a_ack_s1/r_req/r_ack_s1/d_req_s1/d_ack）、aresetn、rst_user_n 2FF+sticky、卡死 sticky[3:0]（lrst/lwst 悬置≥256 aclk 拍、arvalid&!arready、rvalid&!rready）+ |stuck；卡死计数器为纯观察，不反馈 FSM。
  2. `scripts/create_bd_b.tcl` 新增 BD 端口 `dbg_l_bus`（`create_bd_port` + `connect_bd_net`，UG835）——已独立 regen 成功（log `out/r3c_regen_bd.log`，生成 `mb_ctrl.v` 含 `output [35:0]dbg_l_bus`，地址 0x44A00000/0x44A10000 不变）。
  3. 顶层 `aurora_mem_bridge.v`：`u_mb_ctrl` 增 `.dbg_l_bus(dbg_l_bus_w)` + `(* mark_debug *) wire [35:0] dbg_l_bus = dbg_l_bus_w;`、`dbg_l_stuck_or`。
  4. `frame_mem_if.v`（HAS_DMA 分支）增 `dbg_wd_go_ui/ack_ui/intr_ui` 2FF 镜像 mark_debug；`axi4_master_bridge.v`（g_wr_dma 分支）增 `dbg_wd_go_ok`；均只读。
  5. 构建脚本：新 `u_ila_4 @init_clk(100M)`（probe0=36b 打包总线、probe1=bit35 |stuck 触发）；`u_ila_5@ui` 增 probe5=7b（go_ui/ack_ui/intr_ui/go_ok/state[2:0]）；并加 `R3C_SKIP_ILA4` 环境变量回退开关。
- **官方依据**：UG949/UG912 `MARK_DEBUG`（"hierarchical module ports and nets internal to hierarchical modules" 保名不优化）；UG835 `create_bd_port`/`update_module_reference`。**本工程落点**：Vivado 2023.1 / xcku060-ffva1156-2-i / mb_ctrl BD / lite_regs module ref / 验证动作 = 综合后 `ILA4_PROBES`、`DBG_NET_FUZZY` 日志与 LTX 实物核对。

### 18.2 构建轮次

- **attempt1（4 核）**：round3c 综合 PASS（`SYNTH_STATUS: synth_design Complete!`；4 核 debug core 创建成功：ILA4 `probe0=36 + probe1=1`、ILA5 `probe5=7`、`DBG_NET_FUZZY(dbg_wd_go_ui): u_mem/gen_wr_dma_obs.dbg_wd_go_ui` 等 4 条）。**sweep2 `ExtraTimingOpt`：后布 WNS=-0.216 → 后路 -0.029/TNS=-0.061（WHS +0.004）⇒ 未过门限**（`CRITICAL WARNING [Route 35-39]`）；且 post-route phys_opt 在 300MHz `mmcm_clkout0` 路径族（`u_mem/u_wr_bytes`、`wd_wait_cnt` —— 与坑 #59/#60 同族）上极慢（单掷 ~60min）。日志已留 `out/evidence_2026-10-19/round3c_build_attempt1/`。
- **round3c-lite（3 核，`R3C_SKIP_ILA4=1`）**：为保住板验最关键的 ILA5 probe5（GO 链）而临时去掉 ILA4（其 stuck 触发在当前"读回冻结"形态下大概率不触发）。综合 PASS（3 核；`ILA4_SKIPPED`；pre_impl_debug.dcp 13:39:59）。实现：`ExtraPostPlacementOpt` 后布 WNS=-0.525（variance 大）→ 已切 ExtraTimingOpt 单掷重跑。**（截至本记录写入时实现仍在跑，结果见 `out/archive/...round3c/BUILD_STATUS.md`。）**
- **坑（本轮新发现，待入 §九）**：构建 Tcl 若从**中文 CWD**（如 `C:\Users\15266\Desktop\毕设`）启动，`implement_debug_core` spawn 的子 vivado 临时目录为 `<CWD>\.Xil\...`，中文路径使子进程失败 → `Synthesis of Debug Cores has failed / dbg_hub_synth_1`。修法：构建脚本首行 `Set-Location D:\FPGA`（ASCII CWD），随后一次即过。

### 18.3 板端新证据（round3b `02F7153A` 上复演；[L2]/[L1] 分级）

1. **[L2] 复现配方**：烧 round3b + 诊断 ELF（`F5E0F1F3` 或 `DB88C9D0`）→ `'U'`→`'d'`→`'W'`（正常：s2sr=0/s2len=0/m2sr=1/wreq=01000048）→ `ping 1`（0/1 超时）→ **串口全静默**（W/U 无任何输出）。
2. **[L2] 楔死后 LMB（r3c_diag，mb-nm 校验 mismatch=0；同址 3 读 stable）**：`G_STEP=0x0b`、`GDMA_MODE=1`、`WA_CNT=1`、`WA_S2CR=WA_S2SR=WA_S2LEN=WA_WREQ=WA_WDBG=0x80010056`；`PC=0x730/0x738`。0x738 = 反汇编 `uputc` 内 UART_ST(TX_FULL) 轮询（0x72c–0x73c）。
3. **[L2] 冻结值不是伪影**：LMB 区域 dump（0x44F0–0x4544）相邻变量正常、五个变量真为 `0x80010056`；该值 = GO 前最后一次读到的 `WR_REQ` 值（pending=1/toggle=0/slot=1/len=86=前导 8B+74B ping 帧+FCS 4B）。⇒ **MB DP 读回数据冻结/回放，跨 M01(lite_regs)/M02(axi_dma) 两从机** —— 不是 lite_regs 单点、不是 JTAG 伪影。
4. **[L1] 单变量实验**（新固件命令 P/G/C/J/K，源码与 ELF 已归档 round3c 目录）：P（写 DMA SA/IOC/LENGTH 后读）、J（M02 写 LENGTH 紧接 M01 写 GO 后读）、G/C（只写 GO/WRACK）**均不楔死**，读值仅 lag-1/2 后自纠；帧到达但不服务（mode=0 ping）读路完全正常（桥请求超时 DRAIN，wreq=00010056）。⇒ 楔死需要"**真实帧请求 + 固件服务使桥真正进入 STREAM → S2MM 写 DDR**"这一组合（K1 候选）。
5. **[L1] round2f 同位流 A/B**：round2f bit `8A8FE378` + 原配固件 `b614a2dc`（10-18 曾 wm=5）同序列**也复现 ping 后静默** ⇒ "lite fix2 回归"无证据；与历史 wm=5 的差异变量（环境/PC/流程）未定位。
6. 原始串口转录 + 工件 hash：`out/evidence_2026-10-19/R3C_serial_PJK_rehearsal.log.md`。

### 18.4 工具与审计交付（本轮新增，均可复用）

- 审计（rtl-auditor）：`out/evidence_2026-10-19/audit/R3C_probe_review.md`（探针可行性/盲区）、`R3C_wedge_hypotheses.md`（H1–H6 + Z1–Z6 + §E 新证据与 K1–K7 候选）、`round3d_candidate.patch`（邮箱看门狗/SLVERR/sticky、ASYNC_REG、卡死检测 4→8）+ `R3C_round3d_impact.md`。
- 工具（script-tools）：`out/evidence_2026-10-19/tools/` —— `r3c_cap.tcl`（4 核自动发现/触发/快照采集，坑 #66 合规）、`r3c_diag.tcl`（mb-nm 符号校验 + 坑 #54 同址复读）、`r3c_seq.ps1`+`r3c_runbook.md`（分步板验编排）、`r3c_ila_analyze.py`（打包总线解码 + H 签名自动判定，selftest 13/13 PASS）、`r3c_pin.md`、`selfcheck.txt`。
- 本轮实跑：`r3c_diag.tcl`（3 次复现，可用）；`r3c_cap.tcl` 在 round3b 3 核 LTX 上彩排（PRE/POST 正常；ILA5 `tvalid` 触发 60s 无触发 = 未服务时无流，属预期；同时暴露"packed probe 不能按单 bit 触发"的局限 → round3d 拆探针列表已给出）。

### 18.5 下一步（承接交接单）

1. round3c-lite 实现出位流（WNS/WHS≥0）→ 归档 → 板验：烧 round3c-lite + ELF（`DB88C9D0`/`F5E0F1F3`）→ `'U'/'d'/'W'` → arm ILA5（先 `probe5=eq7'b0011001` 判"GO 到桥未放流"；不动则退 `dbg_s2mm_tvalid=eq1'b1`）→ ping 1 → 判 GO/ACK/introut/state；楔死后 `R2_SNAPSHOT_ONLY=1` 全核快照 + `r3c_diag.tcl` + 串口补测（'U'/'W'）。
2. 若 ILA5 判 "go_ui 从未到桥"（GO 写丢失/未执行）⇒ 按 lite 写路径修（round3d patch 的 A1–A6 草案 + 必要时拆分 ILA4 触发探针重建）。
3. 若 go_ui 到桥但 `go_ok=0`/introut 粘滞 ⇒ 按 PG021 + bridge WD 条件修。
4. 数据面通后跑 S0–S11/四档/10MB/双桥对账（不变）。
'''

path = P
cur = io.open(path, "r", encoding="utf-8", newline="").read()
new = cur.rstrip("\n") + "\n" + SECTION
tmp = path + ".tmp_append"
io.open(tmp, "w", encoding="utf-8", newline="").write(new)
assert os.path.getsize(tmp) > os.path.getsize(path), "append shrink guard"
os.replace(tmp, path)
print("APPENDED bytes_old=%d bytes_new=%d" % (os.path.getsize(path) - len(SECTION.encode("utf-8")), os.path.getsize(path)))
print("tail_marker_ok=", "十八、round3c" in io.open(path, encoding="utf-8", newline="").read()[-3000:])
