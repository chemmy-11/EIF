# =============================================================================
# build_debug.tcl — prj11 路线B(B0 冻结基线): synth + 脚本化插入 ILA（四域）+ 实现 + 位流
# fork 自 prj10/prj_loop 同名脚本 2026-10-10, ILA 配置与产物判据逐字一致
# 派生自 prj9 build_debug.tcl; 差异:
#   ILA0 追加 prj10 桥用户侧探针(mem_u_wr/rd/drop 16x3 + mem_rden + ost_sync 9)
#   ILA3 新增 @ ui_clk(MIG ~300MHz): calib + 桥 ui 域计数器(严禁挂 user/eth 域 ILA)
# 用法(ASCII 工作目录):
#   vivado -mode batch -source D:\FPGA\prj\project_11\scripts\build_debug.tcl -notrace
# 产物: out/aurora_mem_bridge.bit + scripts/probes.ltx
# =============================================================================
set proj  D:/FPGA/prj/project_11
file mkdir $proj/out

open_project $proj/vivado/prj11.xpr
# ---- B3-1: 新增 RTL 幂等纳入工程（create_project 只在首建加文件）----
if {[llength [get_files -quiet axi_arb_3to1.v]] == 0} {
    add_files -fileset sources_1 $proj/rtl/axi_arb_3to1.v
    puts "ADD_FILES: axi_arb_3to1.v"
    update_compile_order -fileset sources_1
}
if {[llength [get_files -quiet dma_sink.v]] == 0} {
    add_files -fileset sources_1 $proj/rtl/dma_sink.v
    puts "ADD_FILES: dma_sink.v"
    update_compile_order -fileset sources_1
}
# ---- B3-1b: shim v2 (更名绕开综合 worker 的文件级陈旧缓存, 见 v2 文件头) ----
if {[llength [get_files -quiet dma_rd_shim_v2.v]] == 0} {
    add_files -fileset sources_1 $proj/rtl/dma_rd_shim_v2.v
    puts "ADD_FILES: dma_rd_shim_v2.v"
}
if {[llength [get_files -quiet dma_rd_shim.v]] > 0} {
    remove_files -fileset sources_1 [get_files -quiet dma_rd_shim.v]
    puts "REMOVE_FILES: dma_rd_shim.v (v1 退役)"
}
update_compile_order -fileset sources_1
# ---- ddr4_0 配置已改(System_Clock=No_Buffer): 强制重建其产物与 OOC run ----
# reset_run synth_1 不级联 IP run; 不重建则顶层读到旧差分 stub -> [Synth 8-11365]
reset_target  all [get_ips ddr4_0]
generate_target all [get_ips ddr4_0]
if {[llength [get_runs -quiet ddr4_0_synth_1]] > 0} { reset_run ddr4_0_synth_1 }
# ---- prj11 B1: BD 模块引用/内部 IP 的 OOC 综合必须重置 ----
#     reset_run synth_1 不级联 mb_ctrl_* 的 OOC runs: RTL 变更后旧 DCP 被
#     复用, 修复进不了位流(2026-10-11 板上实证: axi_lite_regs 修复版
#     没生效, DCP 时间戳停在旧综合)。
foreach mr [get_runs -quiet -filter {NAME =~ mb_ctrl_*}] {
    reset_run $mr
    puts "MODULE_REF_RESET: $mr"
}
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synth failed" }
open_run synth_1 -name synth_1

proc one_net {name} {
    set n [get_nets -quiet [list $name]]
    if {[llength $n] == 0} { error "net not found: $name" }
    return [lindex $n 0]
}
proc bus_nets {name width} {
    set nets {}
    for {set i 0} {$i < $width} {incr i} {
        set n [get_nets -quiet "${name}\[${i}\]"]
        if {[llength $n] == 0} { error "net not found: ${name}\[${i}\]" }
        lappend nets $n
    }
    return $nets
}

# round3c (2026-10-19): 解析普通 RTL 子模块(u_mem/frame_mem_if、u_mem/u_bridge)内的
#   mark_debug 别名。合成后其层级前缀不可预知 => 按 leaf-name 匹配，允许综合重命名
#   追加 _N 后缀（先例: dbg_mem_rden -> dbg_mem_rden_1）。
proc dbg_net {token} {
    set cands [get_nets -hier -quiet -filter "NAME =~ *${token}*"]
    set exact {}
    foreach n $cands {
        set ln [lindex [split [get_property NAME $n] /] end]
        if {$ln eq $token} { lappend exact $n }
    }
    if {[llength $exact] == 1} { return [lindex $exact 0] }
    if {[llength $exact] > 1} { error "dbg_net $token: [llength $exact] exact matches" }
    # round3c 实测(2026-10-19): 综合会把 frame_mem_if 内 mark_debug 别名改成非 _N 后缀形态
    #   (dbg_wd_go_ui: cands=1 hit=0)。token 足够独特 => 全设计唯一候选直接用并打印实际名。
    if {[llength $cands] == 1} {
        puts "DBG_NET_FUZZY($token): [get_property NAME [lindex $cands 0]]"
        return [lindex $cands 0]
    }
    set hit {}
    foreach n $cands {
        set ln [lindex [split [get_property NAME $n] /] end]
        if {[regexp "${token}_\[0-9\]+\$" $ln]} { lappend hit $n }
    }
    if {[llength $hit] == 1} { return [lindex $hit 0] }
    error "dbg_net $token: not uniquely found (cands=[llength $cands] hit=[llength $hit])"
}

# round3c-lite: R3C_LITE_ILA=1 时裁剪 300MHz 域 ILA 探针（诊断用位流：
#   ILA3 去掉 stall/len_err/mem2=89b、ILA5 tdata 64->32、probe5 去 state=35b）。
#   判据项 mem2 计数在本诊断位流暂不上 ILA（round3d 全量构建再挂回）。
set lite_ila 0
if {[info exists ::env(R3C_LITE_ILA)]} { set lite_ila 1 }
puts "R3C_LITE_ILA: $lite_ila"

# ============ ILA0 @ Aurora user_clk（prj9 判决链 + prj10 桥用户侧） ============
create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_0]   ;# ★W6: 探针输入加 1 级流水, 解 ILA 引起的布线拥塞(WNS -0.235 -> 目标 >=0)
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
set uclk_net [get_nets -quiet [list user_clk]]
if {[llength $uclk_net] == 0} {
    set uclk_net [get_nets -quiet -of_objects [get_pins -quiet {u_pack/frame_active_reg/C}]]
}
if {[llength $uclk_net] == 0} { error "user_clk net not found (nor via u_pack/frame_active_reg/C)" }
puts "ILA0_CLK_NET: $uclk_net"
connect_debug_port u_ila_0/clk $uclk_net

set nets0 {}
# ★2026-10-18 (R2 round2 时序攻坚): ILA0 只保留 R2 板验判据必需项 (省资源/布线余量)
#   S6/S10(user 侧): 桥① u_wr/u_rd/u_drop/rden/ost_s + 桥② u_wr/u_rd;
#   S2MM 写引擎: reqpend/fault;   probe1 发射字节流 (S8c) 保留不变.
foreach n [bus_nets dbg_mem_u_wr   16] { lappend nets0 $n }
foreach n [bus_nets dbg_mem_u_rd   16] { lappend nets0 $n }
foreach n [bus_nets dbg_mem_u_drop 16] { lappend nets0 $n }
lappend nets0 [one_net dbg_mem_rden]
foreach n [bus_nets dbg_mem_ost_s   9] { lappend nets0 $n }
foreach n [bus_nets dbg_mem2_u_wr  16] { lappend nets0 $n }
foreach n [bus_nets dbg_mem2_u_rd  16] { lappend nets0 $n }
lappend nets0 [one_net dbg_s2mm_reqpend]
lappend nets0 [one_net dbg_wr_fault]
# ★round3: 写入口字节 (泵A→桥写) 9b: 判定"上游数据源/写入口"层
foreach n [bus_nets dbg_pfwd_data 8] { lappend nets0 $n }
lappend nets0 [one_net dbg_pfwd_en]
set_property port_width [llength $nets0] [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 $nets0

# ---- B3-1b v5(2026-10-16): 发射字节流探针(probe1) ----
#   目的: 把「frame_mem_if 读侧实际发射的字节」搬上 ILA, 与桥/DMA 两引擎逐字节比对
#   (该探针是 0 回显根因定案的关键仪器: 桥流=[8B 前导+SFD][帧][FCS], DMA 流旧口径=[帧][FCS][8B 垃圾])。
set nets_rd {}
lappend nets_rd [one_net dbg_mem_rden]
foreach i {0 1 2 3 4 5 6 7} { lappend nets_rd [one_net "mem_rd_data\[$i\]"] }
create_debug_port u_ila_0 probe
set_property port_width [llength $nets_rd] [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 $nets_rd
puts "ILA0_PROBE1_EMIT_BYTES: [llength $nets_rd] nets"

# ★2026-10-18 (R2 round2): ILA1@eth_rxc 整核移除 (R2 S0–S11 判据不使用, 省资源/布线; 原 prj9 eth 域探针仅 prj9 判据用)

# ★2026-10-18 (R2 round2): ILA2@user_clk_b 整核移除 (B 通道; R2 S0–S11 判据不使用)

# ============ ILA3 @ ui_clk (MIG ~300MHz) —— prj10 新增 ============
#   ui 域信号严禁挂 ILA0/1/2; 桥的 ui 侧计数器全部在此观测
create_debug_core u_ila_3 ila
# ★round3b 时序: ILA3 深 2048->1024 (300MHz 面积余量; 判据探针不动)
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_3]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_3]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_3]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_3]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_3]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_3]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_3]
set_property port_width 1 [get_debug_ports u_ila_3/clk]
set uiclk_net [get_nets -quiet [list ui_clk]]
if {[llength $uiclk_net] == 0} {
    set uiclk_net [get_nets -quiet -of_objects [get_pins -quiet {u_mem/u_bridge/wst_reg[0]/C}]]
}
if {[llength $uiclk_net] == 0} { error "ui_clk net not found (nor via u_mem/u_bridge/wst_reg[0]/C)" }
puts "ILA3_CLK_NET: $uiclk_net"
connect_debug_port u_ila_3/clk $uiclk_net

set nets3 {}
lappend nets3 [one_net dbg_calib      ]
foreach n [bus_nets dbg_mem_wm      16] { lappend nets3 $n }
foreach n [bus_nets dbg_mem_wr_frm  16] { lappend nets3 $n }
foreach n [bus_nets dbg_mem_rd_frm  16] { lappend nets3 $n }
# round3c-lite: stall/len_err 107b 不在诊断位流上挂 (原 152b -> 最多 63b)
if {!$lite_ila} {
foreach n [bus_nets dbg_mem_stall   16] { lappend nets3 $n }
foreach n [bus_nets dbg_mem_len_err 16] { lappend nets3 $n }
}
# ★2026-10-18 round2 裁: dbg_mem_bresp (S2MM 下恒 0, INFO) 不挂
foreach n [bus_nets dbg_mem_ost      9] { lappend nets3 $n }
# ★2026-10-18 round2 裁: wslot/rslot (调试用) 不挂
# ---- W5: 非法读/无帧计数 + 读写突发数（J5 对账与可观测性）----
# ⚠️ 2026-10-07 实测: 这 96 bit 加在 300MHz 的 ILA3 上会把 ui 域推向拥塞
#    （WNS -0.041 → -1.142, 4040 端点失败, 平均缺口仅 0.27ns = 典型拥塞特征）。
#    RND 使能后 stat_ill_rd/full_bit 查表锥本就是零余量, 再加载即崩。
#    -> 暂不挂 ILA3, 保住 RND 时序（J5 的 ill_rd 证据改由 PC 侧空应答 + 桥语义文档 + 单元 TB/T5b 承担）
# foreach n [bus_nets dbg_mem_ill     16] { lappend nets3 $n }
# foreach n [bus_nets dbg_mem_nofrm   16] { lappend nets3 $n }
# foreach n [bus_nets dbg_mem_wbeats  32] { lappend nets3 $n }
# foreach n [bus_nets dbg_mem_rbeats  32] { lappend nets3 $n }
# ---- W4: 桥②(EGRESS) ui 域观测 ----
# round3c-lite: 桥② 计数 57b 不在诊断位流上挂（round3d 全量构建恢复）
if {!$lite_ila} {
foreach n [bus_nets dbg_mem2_wm     16] { lappend nets3 $n }
foreach n [bus_nets dbg_mem2_wr_frm 16] { lappend nets3 $n }
foreach n [bus_nets dbg_mem2_rd_frm 16] { lappend nets3 $n }
foreach n [bus_nets dbg_mem2_ost     9] { lappend nets3 $n }
}
# ---- B3-2: DMA 写引擎 (S2MM) ui 域观测 (状态/流握手, 仅 5 bit 保时序) ----
foreach n [bus_nets dbg_s2mm_state  3] { lappend nets3 $n }
lappend nets3 [one_net dbg_s2mm_tvalid]
lappend nets3 [one_net dbg_s2mm_tready]
set_property port_width [llength $nets3] [get_debug_ports u_ila_3/probe0]
connect_debug_port u_ila_3/probe0 $nets3

# ============ ILA5 @ ui_clk —— round3: S2MM 写流首拍取证 (75b, 拆分 5 probe) ============
#   目的: 核对 S2MM 写入 DDR 的 AXI-Stream 首拍是否 = 55x7,D5 前导+SFD (厂商 INDET_BTT:
#   WSTRB 来自 TKEEP, TLAST 终止) -> 判定"写引擎/上游数据源" vs "写参数/读出链"故障层。
#   触发: tvalid & tready & !tlast (首拍)。深度 1024 省 300MHz 面积 (WNS 仅 +0.004)。
create_debug_core u_ila_5 ila
# ★round3b: ILA5 深度保持 1024 (Vivado 2023.1 C_DATA_DEPTH 最小 1024, 512 非法)
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_5]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_5]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_5]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_5]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_5]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_5]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_5]
set_property port_width 1 [get_debug_ports u_ila_5/clk]
connect_debug_port u_ila_5/clk $uiclk_net

set nets5a {}
if {$lite_ila} {
    foreach n [bus_nets dbg_s2mm_tdata64 32] { lappend nets5a $n }
    puts "ILA5_LITE: tdata 64->32 (beat0 低 32b 仍可核 0x55555555)"
} else {
    foreach n [bus_nets dbg_s2mm_tdata64 64] { lappend nets5a $n }
}
set nets5b [bus_nets dbg_s2mm_tkeep8 8]
set_property port_width [llength $nets5a] [get_debug_ports u_ila_5/probe0]
connect_debug_port u_ila_5/probe0 $nets5a
create_debug_port u_ila_5 probe
set_property port_width [llength $nets5b] [get_debug_ports u_ila_5/probe1]
connect_debug_port u_ila_5/probe1 $nets5b
create_debug_port u_ila_5 probe
set_property port_width 1 [get_debug_ports u_ila_5/probe2]
connect_debug_port u_ila_5/probe2 [list [one_net dbg_s2mm_tvalid]]
create_debug_port u_ila_5 probe
set_property port_width 1 [get_debug_ports u_ila_5/probe3]
connect_debug_port u_ila_5/probe3 [list [one_net dbg_s2mm_tready]]
create_debug_port u_ila_5 probe
set_property port_width 1 [get_debug_ports u_ila_5/probe4]
connect_debug_port u_ila_5/probe4 [list [one_net dbg_s2mm_tlast_w]]
# ---- round3c (2026-10-19): ILA5 probe5 = GO/ACK/introut 到达桥内 (ui 域) ----
#   判别 S2MM 写引擎零 commit 链: GO 是否跨到 ui / ACK / introut 是否粘滞 /
#   桥 WAITGO 是否看到 GO（wd_go_ok）。state[2:0] 复用 ILA3 同源 net。
create_debug_port u_ila_5 probe
set nets5c {}
foreach t {dbg_wd_go_ui dbg_wd_ack_ui dbg_wd_intr_ui dbg_wd_go_ok} {
    lappend nets5c [dbg_net $t]
}
if {!$lite_ila} {
foreach n [bus_nets dbg_s2mm_state 3] { lappend nets5c $n }
}
set_property port_width [llength $nets5c] [get_debug_ports u_ila_5/probe5]
connect_debug_port u_ila_5/probe5 $nets5c
puts "ILA5_PROBE5: [llength $nets5c] nets (go_ui/ack_ui/intr_ui/go_ok/state)"

set n5a [llength $nets5a]
set n5b [llength $nets5b]
puts "ILA5_PROBES: tdata64=$n5a tkeep8=$n5b + tvalid/tready/tlast + probe5=[llength $nets5c]"

# ============ ILA4 @ clk_100m —— round3c: lite_regs AXI/邮箱楔死探针 ============
#   背景: lite_regs 在 BD 内为 module ref(独立 OOC run), 顶层综合看不到其内部 net
#   (build_r2_synth.log: "synthesizing module 'mb_ctrl_axi_lite_regs_0_0' ... stub")。
#   做法: axi_lite_regs.v 增加纯观测 output [35:0] dbg_o -> create_bd_b.tcl 引出 BD
#   端口 dbg_l_bus (UG835 create_bd_port) -> 顶层 alias dbg_l_bus[35:0] 挂本 ILA。
#   触发: probe1 = dbg_l_stuck_or (= bus bit35, |stuck[3:0]) 上升。
#   2026-10-19: 环境变量 R3C_SKIP_ILA4=1 时跳过本核（时序余量不足时的快速回退；ltx 变 3 核）。
if {[info exists ::env(R3C_SKIP_ILA4)]} {
    puts "ILA4_SKIPPED: env R3C_SKIP_ILA4 set (timing fallback, ltx = 3 cores)"
} else {
create_debug_core u_ila_4 ila
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_4]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_4]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_4]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_4]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_4]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_4]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_4]
set_property port_width 1 [get_debug_ports u_ila_4/clk]
set c100_net [get_nets -quiet [list init_clk]]
if {[llength $c100_net] == 0} { set c100_net [get_nets -hier -quiet -filter {NAME =~ *init_clk}] }
if {[llength $c100_net] != 1} { error "ILA4 clock init_clk: [llength $c100_net] matches" }
puts "ILA4_CLK_NET: $c100_net"
connect_debug_port u_ila_4/clk $c100_net

set nets4 {}
foreach n [bus_nets dbg_l_bus 36] { lappend nets4 $n }
set_property port_width [llength $nets4] [get_debug_ports u_ila_4/probe0]
connect_debug_port u_ila_4/probe0 $nets4
create_debug_port u_ila_4 probe
set_property port_width 1 [get_debug_ports u_ila_4/probe1]
# probe1 = probe0 bit35 同一 net (|stuck 触发位)。零名字依赖: 不赌 alias 是否被综合改名
# (审计 R1 建议; 同 net 双挂 ILA 探针已有 ILA0 dbg_mem_rden 先例)
connect_debug_port u_ila_4/probe1 [list [lindex $nets4 35]]
puts "ILA4_PROBES: probe0=[llength $nets4] (lite AXI/fsm/mbox/reset/stuck[35:0]) + probe1=1 (stuck_or trigger)"
}

write_checkpoint -force $proj/scripts/pre_impl_debug.dcp
close_design

# 2026-10-17 R1 fix: synth + ILA definition only; implementation via build_v5_sweep.tcl
puts "SYNTH_ONLY_DONE"
exit
