# prj11 路线 B 可观测性清单（自动生成，勿手改）

> 生成器 `scripts/w6_inventory_prj11.py`（W6 思路移植版，**以 LTX 构建产物为主源**）  
> LTX 源：`out/archive/b31b_r2_2026-10-19_round3d/probes_r2_F6012BA0.ltx`  
> RTL 源：`rtl/*.v` · 生成时间：2026-10-19 17:15:58

## 一、ILA 按域分挂

| ILA | 时钟域 | 探针数 | 位宽合计 |
|---|---|---|---|
| `u_ila_0` | user_clk（Aurora A，~151.5MHz） | 13 | 110 |
| `u_ila_3` | ui_clk（MIG ~300MHz） | 14 | 152 |
| `u_ila_5` | ui_clk（MIG ~300MHz） | 9 | 47 |

合计挂载 **309 bit**（3 个 ILA；本轮 ILA4 整核跳过）。

## 二、探针明细（LTX 实际连接）

| ILA | probe | 位宽 | nets（基础名，多 net 时列出） |
|---|---|---|---|
| `u_ila_0` | `probe0` | 16 | `dbg_mem_u_wr` |
| `u_ila_0` | `probe0` | 16 | `dbg_mem_u_rd` |
| `u_ila_0` | `probe0` | 16 | `dbg_mem_u_drop` |
| `u_ila_0` | `probe0` | 1 | `dbg_mem_rden` |
| `u_ila_0` | `probe0` | 9 | `dbg_mem_ost_s` |
| `u_ila_0` | `probe0` | 16 | `dbg_mem2_u_wr` |
| `u_ila_0` | `probe0` | 16 | `dbg_mem2_u_rd` |
| `u_ila_0` | `probe0` | 1 | `dbg_s2mm_reqpend` |
| `u_ila_0` | `probe0` | 1 | `dbg_wr_fault` |
| `u_ila_0` | `probe0` | 8 | `dbg_pfwd_data` |
| `u_ila_0` | `probe0` | 1 | `dbg_pfwd_en` |
| `u_ila_0` | `probe1` | 1 | `dbg_mem_rden` |
| `u_ila_0` | `probe1` | 8 | `mem_rd_data` |
| `u_ila_3` | `probe0` | 1 | `dbg_calib` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem_wm` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem_wr_frm` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem_rd_frm` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem_stall` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem_len_err` |
| `u_ila_3` | `probe0` | 9 | `dbg_mem_ost` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem2_wm` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem2_wr_frm` |
| `u_ila_3` | `probe0` | 16 | `dbg_mem2_rd_frm` |
| `u_ila_3` | `probe0` | 9 | `dbg_mem2_ost` |
| `u_ila_3` | `probe0` | 3 | `dbg_s2mm_state` |
| `u_ila_3` | `probe0` | 1 | `dbg_s2mm_tvalid` |
| `u_ila_3` | `probe0` | 1 | `dbg_s2mm_tready` |
| `u_ila_5` | `probe0` | 32 | `dbg_s2mm_tdata64` |
| `u_ila_5` | `probe1` | 8 | `dbg_s2mm_tkeep8` |
| `u_ila_5` | `probe2` | 1 | `dbg_s2mm_tvalid` |
| `u_ila_5` | `probe3` | 1 | `dbg_s2mm_tready` |
| `u_ila_5` | `probe4` | 1 | `dbg_s2mm_tlast_w` |
| `u_ila_5` | `probe5` | 1 | `dbg_wd_go_ui` |
| `u_ila_5` | `probe5` | 1 | `dbg_wd_ack_ui` |
| `u_ila_5` | `probe5` | 1 | `dbg_wd_intr_ui` |
| `u_ila_5` | `probe5` | 1 | `dbg_wd_go_ok` |

## 三、RTL 声明与挂载状态

| 信号 | 位宽 | 声明文件 | 挂载 ILA |
|---|---|---|---|
| `dbg_arp_rx_done` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_arp_rx_type` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_b_rx_tvalid` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_b_tx_tvalid` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_bus` | 512 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_calib` | 1 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_ch_up` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_ch_up_b` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_ch_up_b_evt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_ch_up_evt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_cmd_err` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_cmd_exec` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_cmd_mode` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_cmd_respbsy` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_cmd_rx` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_cmd_slot` | 8 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_cmd_trig` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_echo_b_ovf` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_echo_b_ovf_cnt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_echo_b_rx` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_echo_b_tx` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_emit` | 32 | `axi_lite_regs.v` | **未挂** |
| `dbg_gmii_rx_dv` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_gmii_rxd` | 8 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_hard_err` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_hard_err_b_cnt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_hard_err_cnt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_icmp_rec_done` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_l_bus` | 36 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_l_bus_w` | 36 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_l_stuck_or` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_lane_up` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_lane_up_b` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_lite_exec` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_lite_mode` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_lite_owner` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_lite_slot` | 8 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_lite_trig` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem2_len` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem2_ost` | 9 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem2_rd_frm` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem2_stall` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem2_u_rd` | 16 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_mem2_u_wr` | 16 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_mem2_wm` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem2_wr_frm` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem_bresp` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem_ill` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem_len_err` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem_nofrm` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem_ost` | 9 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem_ost_s` | 9 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_mem_rbeats` | 32 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem_rd_frm` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem_rden` | 1 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_mem_rslot` | 8 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem_stall` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem_u_drop` | 16 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_mem_u_rd` | 16 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_mem_u_wr` | 16 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_mem_wbeats` | 32 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_mem_wm` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem_wr_frm` | 16 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_mem_wslot` | 8 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_o` | 36 | `axi_lite_regs.v` | **未挂** |
| `dbg_pfwd_data` | 8 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_pfwd_drop` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_pfwd_en` | 1 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_pfwd_rd` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_pfwd_stuck` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_pfwd_stuck_cnt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_pfwd_wr` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_pk_frames` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_pk_ovf` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_pk_ovf_cnt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_prev_drop` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_prev_wr` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_rd_beats` | 32 | `frame_mem_if.v` | **未挂** |
| `dbg_rd_cycles` | 32 | `frame_mem_if.v` | **未挂** |
| `dbg_rec_byte_num` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_rx_tdata` | 64 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_rx_tkeep` | 8 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_rx_tlast` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_rx_tvalid` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_s2mm_reqpend` | 1 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_s2mm_state` | 3 | `aurora_mem_bridge.v` | u_ila_3 |
| `dbg_s2mm_tdata64` | 64 | `aurora_mem_bridge.v` | u_ila_5 |
| `dbg_s2mm_tkeep8` | 8 | `aurora_mem_bridge.v` | u_ila_5 |
| `dbg_s2mm_tlast_w` | 1 | `aurora_mem_bridge.v` | u_ila_5 |
| `dbg_s2mm_tready` | 1 | `aurora_mem_bridge.v` | u_ila_3、u_ila_5 |
| `dbg_s2mm_tvalid` | 1 | `aurora_mem_bridge.v` | u_ila_3、u_ila_5 |
| `dbg_soft_err` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_soft_err_b_cnt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_soft_err_cnt` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_stack_txd` | 8 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_stack_txen` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_tx_tdata` | 64 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_tx_tvalid` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_udp_rec_done` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_udp_src_port` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_up_bytes` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_up_frames` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_up_ovf` | 1 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_up_stall` | 16 | `aurora_mem_bridge.v` | **未挂** |
| `dbg_wd_ack_ui` | 1 | `frame_mem_if.v` | u_ila_5 |
| `dbg_wd_go_ok` | 1 | `axi4_master_bridge.v` | u_ila_5 |
| `dbg_wd_go_ui` | 1 | `frame_mem_if.v` | u_ila_5 |
| `dbg_wd_intr_ui` | 1 | `frame_mem_if.v` | u_ila_5 |
| `dbg_wr_beats` | 32 | `frame_mem_if.v` | **未挂** |
| `dbg_wr_cycles` | 32 | `frame_mem_if.v` | **未挂** |
| `dbg_wr_fault` | 1 | `aurora_mem_bridge.v` | u_ila_0 |
| `dbg_wr_fault_i` | 1 | `frame_mem_if.v` | **未挂** |
| `dbg_wr_last_len` | 16 | `axi4_master_bridge.v` | **未挂** |
| `dbg_wr_last_len_i` | 16 | `frame_mem_if.v` | **未挂** |
| `dbg_wr_last_slot` | 8 | `axi4_master_bridge.v` | **未挂** |
| `dbg_wr_last_slot_i` | 8 | `frame_mem_if.v` | **未挂** |
| `dbg_wr_state` | 3 | `axi4_master_bridge.v` | **未挂** |
| `dbg_wr_state_i` | 3 | `frame_mem_if.v` | **未挂** |

## 四、可观测性缺口（RTL 已声明但未上 ILA）

| 信号 | 位宽 | 声明文件 | 说明 |
|---|---|---|---|
| `dbg_arp_rx_done` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_arp_rx_type` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_b_rx_tvalid` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_b_tx_tvalid` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_bus` | 512 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_ch_up` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_ch_up_b` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_ch_up_b_evt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_ch_up_evt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_cmd_err` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_cmd_exec` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_cmd_mode` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_cmd_respbsy` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_cmd_rx` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_cmd_slot` | 8 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_cmd_trig` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_echo_b_ovf` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_echo_b_ovf_cnt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_echo_b_rx` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_echo_b_tx` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_emit` | 32 | `axi_lite_regs.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_gmii_rx_dv` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_gmii_rxd` | 8 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_hard_err` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_hard_err_b_cnt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_hard_err_cnt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_icmp_rec_done` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_l_bus` | 36 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_l_bus_w` | 36 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_l_stuck_or` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_lane_up` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_lane_up_b` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_lite_exec` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_lite_mode` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_lite_owner` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_lite_slot` | 8 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_lite_trig` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_mem2_len` | 16 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem2_stall` | 16 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem_bresp` | 16 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem_ill` | 16 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem_nofrm` | 16 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem_rbeats` | 32 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem_rslot` | 8 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem_wbeats` | 32 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_mem_wslot` | 8 | `aurora_mem_bridge.v` | 300MHz ui 域诊断计数；按轮次裁剪/未挂（时序余量），xsim 可见 |
| `dbg_o` | 36 | `axi_lite_regs.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pfwd_drop` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pfwd_rd` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pfwd_stuck` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pfwd_stuck_cnt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pfwd_wr` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pk_frames` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pk_ovf` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_pk_ovf_cnt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_prev_drop` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_prev_wr` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_rd_beats` | 32 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_rd_cycles` | 32 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_rec_byte_num` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_rx_tdata` | 64 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_rx_tkeep` | 8 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_rx_tlast` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_rx_tvalid` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_soft_err` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_soft_err_b_cnt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_soft_err_cnt` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_stack_txd` | 8 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_stack_txen` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_tx_tdata` | 64 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_tx_tvalid` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_udp_rec_done` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_udp_src_port` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_up_bytes` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_up_frames` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_up_ovf` | 1 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_up_stall` | 16 | `aurora_mem_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_beats` | 32 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_cycles` | 32 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_fault_i` | 1 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_last_len` | 16 | `axi4_master_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_last_len_i` | 16 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_last_slot` | 8 | `axi4_master_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_last_slot_i` | 8 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_state` | 3 | `axi4_master_bridge.v` | 顶层聚合/别名或按需诊断信号 |
| `dbg_wr_state_i` | 3 | `frame_mem_if.v` | 顶层聚合/别名或按需诊断信号 |

## 五、判据 ↔ 探针索引（人工维护）

| 判据 | 依赖探针/计数 |
|---|---|
| S4/S5 单帧端到端（ping / NIC / WM 计数） | ILA0 `dbg_mem_u_wr/u_rd`、`dbg_mem_rden`；ILA3 `dbg_mem_wm/wr_frm/rd_frm`、`dbg_s2mm_state/tvalid/tready` |
| S6 桥级 ILA（mem 写/读 +4、ost=0；mem2 rd_frm +4、ost=0） | ILA3 `dbg_mem_wm/wr_frm/rd_frm/ost`、`dbg_mem2_wm/wr_frm/rd_frm/ost`、`dbg_mem_stall/len_err`、`dbg_calib` |
| S7 四档（PC 侧 UDP 逐字节） | PC 侧判据；板上 `dbg_mem_wr_frm/rd_frm` + `dbg_mem2_*` 计数佐证 |
| S8 10MB 100%+SHA（PC 侧） | PC 侧判据；`dbg_mem_wr_frm/rd_frm`、`dbg_wr_fault=0` 佐证 |
| S9 J3 四链（软核控制下导师四环节） | PC 侧 j3_soft_verify 判据；串口 `U` 计数 + ILA3 `dbg_s2mm_state/tvalid` 佐证 |
| S10 双桥计数对账（mem/mem2 各自 wm==wr_frm==rd_frm、ost=0、stall/len_err=0、fault=0） | ILA3 `dbg_mem_*` + `dbg_mem2_*`（152b 全量）；ILA0 `dbg_wr_fault` |
| R2 写引擎 GO/ACK/introut 链（诊断用） | ILA5 `dbg_wd_go_ui/ack_ui/intr_ui/go_ok`、`dbg_s2mm_tdata64/tkeep8/tvalid/tready/tlast_w`、`dbg_s2mm_state` |

## 六、配置变体与已知裁剪（口径，非缺陷）

| 位流轮次 | ILA 配置 | 说明 |
|---|---|---|
| round3b `02F7153A` | ILA0 110b / ILA3 152b / ILA5 82b（tdata64+probe5=7b），3 核 | 写流首拍全面取证版 |
| round3c-diag `9852016C` | ILA0 110b / ILA3 **63b**（裁 stall/len_err/mem2）/ ILA5 **47b**（tdata32+probe5=4b） | 为 300MHz 时序余量裁剪的诊断版（S6/S10 计数不可用） |
| round3d `F6012BA0`（验收） | ILA0 110b / ILA3 **152b 全量** / ILA5 47b；ILA4 整核跳过 | 本清单主源；S6/S10 判据仪器齐 |
| 全部轮次 | `u_ila_4`（lite_regs `dbg_o[35:0]` @100MHz） | round3c/round3d 均 `R3C_SKIP_ILA4=1` 跳过（省时序余量；lite 总线直证暂缺） |

