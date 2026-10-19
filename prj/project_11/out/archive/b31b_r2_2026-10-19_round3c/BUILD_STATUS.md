# R2 round3c 构建状态（out/archive/b31b_r2_2026-10-19_round3c/）

状态：**构建成功（diag-lite，PASS）** —— 2026-10-19 15:29 出流：V5_SWEEP1_OK: WNS=+0.004 / WHS=+0.004（ExtraTimingOpt 单掷）。
> 本归档位流 = **round3c-diag**：ILA4 跳过（attempt1 四核版 WNS=-0.029 被门限拒）、ILA3 裁 63b、ILA5 裁 47b（tdata32/probe5 4b）；**功能 RTL 与 round3b 等价，仅新增纯观测 dbg_o/BD 端口/GO 链 mark_debug**。
> **板验（2026-10-19 15:3x–16:0x）：数据面首次全通** —— ping 20/20、四档全 PASS、10MB 100%+SHA PASS；50% 丢帧根因=固件 MM2S 复位连带复位 S2MM（见 out/evidence_2026-10-19/R3C_board_session_20261019.md）。
> 遗留：S6/S10 需 ILA3 全量计数 → 由 **round3d**（ILA3=152b / ILA5=47b / ILA4 跳过）承担，见 out/archive/b31b_r2_2026-10-19_round3d/。

## 1. round3c 是什么

为定位 R2 两层阻塞（① lite_regs/M01 读楔死；② 桥①写侧 GO→S2MM 流/commit 链）新增仪器，**功能逻辑零改动**：

- `rtl/axi_lite_regs.v`：新增纯观测 output `[35:0] dbg_o`（AXI 握手 10b / 地址解码 8b / lwst+lrst 4b / aclk 侧邮箱 6b / aresetn / rst_user_n 2FF+sticky / 卡死 sticky[3:0] + |stuck；位图见 RTL 末尾 DBG 段）。
- `scripts/create_bd_b.tcl`：引出 BD 端口 `dbg_l_bus`（`create_bd_port`+`connect_bd_net`，UG835）；独立 regen 成功（`out/r3c_regen_bd.log`；生成 `mb_ctrl.v` 含 `output [35:0]dbg_l_bus`；地址 0x44A00000/0x44A10000 不变）。
- `rtl/aurora_mem_bridge.v`：u_mb_ctrl `.dbg_l_bus(dbg_l_bus_w)`；顶层 `(* mark_debug *) dbg_l_bus[35:0]`、`dbg_l_stuck_or`。
- `rtl/frame_mem_if.v`（HAS_DMA 分支）：`dbg_wd_go_ui/dbg_wd_ack_ui/dbg_wd_intr_ui`（2FF 镜像，ui 域）mark_debug。
- `rtl/axi4_master_bridge.v`（g_wr_dma 分支）：`dbg_wd_go_ok` mark_debug。
- 构建脚本：`u_ila_4 @init_clk(100M)`（probe0=36b 打包、probe1=bit35 |stuck 触发）；`u_ila_5@ui` 增 probe5=7b（go_ui/ack_ui/intr_ui/go_ok/state[2:0]）；新增 `R3C_SKIP_ILA4` 环境变量回退开关。

## 2. attempt1（4 核，ILA4 在）：时序未过门限

| 步骤 | 结果 |
|---|---|
| 综合 | PASS（4 核 debug core 创建成功；`ILA4_PROBES: probe0=36 + probe1=1`、`ILA5_PROBE5: 7 nets`、`DBG_NET_FUZZY` 4 条命中） |
| sweep2 `ExtraTimingOpt` | 后布 WNS=-0.216 → **后路 WNS=-0.029 / TNS=-0.061 / WHS=+0.004** ⇒ `CRITICAL WARNING [Route 35-39]` **未过门限**（门限 WNS/WHS≥0 才写位流） |
| 备注 | post-route phys_opt 在 300MHz `mmcm_clkout0` 路径族（`u_mem/u_wr_bytes`、`wd_wait_cnt`，同坑 #59/#60 族）上极慢（单掷 ~60min）；日志存档 `out/evidence_2026-10-19/round3c_build_attempt1/` |

## 3. round3c-lite（3 核，`R3C_SKIP_ILA4=1`）：进行中

- 动机：保住板验最关键的 `u_ila_5 probe5`（GO/ACK/introut/state），暂舍 ILA4（其 stuck 触发在当前"读回冻结"形态下大概率不触发；拆分触发探针列 round3d）。
- 综合：**PASS**（`ILA4_SKIPPED`；ILA0/ILA3/ILA5 三核；`pre_impl_debug.dcp` 13:39:59）。
- 实现：`ExtraPostPlacementOpt` 后布 WNS=-0.525（variance 大，弃）→ 已切 **ExtraTimingOpt 单掷**重跑（脚本 `out/r3c2_sweep_one.tcl`，日志 `out/r3c2_one*.log`）。截至本文件写入时仍在跑。
- 期间已知瞬态：`ExtraTimingOpt` 首掷遇 `ddr4_phy` MIG 缝合瞬态（`[Mig 66-119]`，坑 #61 家族），由重试包装恢复。

## 4. 产物（已回填）

| 产物 | 期望 |
|---|---|
| bit | `aurora_mem_bridge_r2_<hash8>.bit` |
| ltx | `probes_r2_<hash8>.ltx` —— **3 核**：ILA0 probe0=110 / probe1=9；ILA3 probe0=152；ILA5 total=82（probe0=64/probe1=8/probe2=1/probe3=1/probe4=1/probe5=7） |
| xsa | `mb_ctrl_r2.xsa` |
| ELF | 诊断固件 `j3_soft_r2_DB88C9D0_jk.elf`（含 P/G/C/J/K 实验命令；服务逻辑与 F5E0F1F3 相同）/ `j3_soft_r2_F5E0F1F3.elf` |
| RTL 快照 | rtl_axi_lite_regs.v / rtl_aurora_mem_bridge.v / rtl_axi4_master_bridge.v / rtl_frame_mem_if.v |
| 脚本快照 | create_bd_b.tcl / build_synth_only.tcl / build_debug.tcl / build_v5_sweep2.tcl + 重试包装 + r3c2_sweep_one.tcl |
| 日志 | build_r3c_synth*.log / build_r3c_sweep2_attempt1*.log / build_r3c_synth/sweep2（lite） |
| 清单 | SHA256.txt（由 `out/r2_archive_round3c.py` 生成） |

## 5. 板验准备（位流出后）

1. 烧归档绝对路径 bit + ELF（先 Get-FileHash；脚本 `xsct jb31b_burn_pair.tcl <bit> <elf>`，期待 `PAIR_BURNED`）。
2. 串口 COM5 9600：`'U'`（基线，mode=0）→ `'d'`（DMAMODE now=DMA）→ `'W'`（期望 s2cr=00011003 / s2sr=0 / s2len=0 / m2sr=1）。
3. ILA 抓取（工具 `out/evidence_2026-10-19/tools/r3c_cap.tcl`；实跑时 arm 在 `'d'` 之后、ping 之前）：
   - **Run A**：`R2_TRIG_ILA5="<probe5名>=eq7'b0011001"`（go_ui=1&go_ok=1&WAITGO ⇒ "GO 到桥但未放流"）；
   - **Run B**（最稳）：`R2_TRIG_ILA5="dbg_s2mm_tvalid=eq1'b1"`（引擎真进 STREAM）；Run C `eq7'b0011101`（intr 粘滞）；Run D `eq7'b0000001`（GO 到但引擎 IDLE）。
   - 另加一次 `R2_SNAPSHOT_ONLY=1` 全核快照（楔死后）。
4. 楔死后：`xsct tools/r3c_diag.tcl`（PC/g_step/g_wa_*）、串口补测 `'U'/'W'`、保存所有 CSV + 日志 + 判读（`tools/r3c_ila_analyze.py`，输出 HYPOTHESIS 行）。
5. 判读口径（审计 §E.3）：go_ui=0 ⇒ GO 写未达桥/未执行（先修 lite 写路径）；go_ok=0 ⇒ WAITGO 条件未满足；intr=1 ⇒ introut 粘滞；ENTERED_STREAM ⇒ 写流启动（再核对 tdata beat0 0xD555…/tkeep）。

## 6. 已知坑（本轮新增）

- **中文 CWD 下跑会 spawn 子 vivado 的构建脚本**（`implement_debug_core`）→ 子进程 `.Xil` 临时目录含中文 → `Synthesis of Debug Cores has failed / dbg_hub_synth_1`。修法：脚本首行 `Set-Location D:\FPGA`（ASCII CWD）。
- `C_DATA_DEPTH` 最小 1024（坑 #67，不变）。
- `R3C_SKIP_ILA4=1` 只影响构建期 ILA 插入；RTL/BD 的 dbg_o/dbg_l_bus 仍在（无副作用）。
