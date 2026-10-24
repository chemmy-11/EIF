# =============================================================================
# build_synth_only.tcl — prj12 双板 P1: synth + 脚本化插入 ILA（A 域/u_i 域）+ 存 pre-impl dcp
# fork 自 prj11 scripts/build_synth_only.tcl 2026-10-24; 与 prj11 差异仅两处:
#   1. 路径 prj12（工程/产物根）
#   2. ★新增 ILA6 @ user_clk：单核链路健康（link_ok/ch_up/lane_up/gt_pll_lock/
#      hard_err/soft_err + ch_up_evt/hard_err_cnt/soft_err_cnt + Aurora TX/RX 帧数
#      + eth↔mem 泵计数），env P12_SKIP_ILA6=1 整核跳过（时序回退用）
#   ILA0/3/5 与 prj11 round3d 验收位流 F6012BA0 **逐字一致**（保持 A/B 可比性）
# 用法(ASCII 工作目录; 先确认无其它 vivado 进程):
#   vivado -mode batch -source D:\FPGA\prj\project_12\scripts\build_synth_only.tcl -notrace
# 产物: scripts/pre_impl_debug.dcp（实现走 build_impl.tcl）
# =============================================================================
set proj  D:/FPGA/prj/project_12
file mkdir $proj/out

open_project $proj/vivado/prj12.xpr
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
# ---- ddr4_0 产物：create_project 已在 No_Buffer 配置下 generate_target all ----
#   仅当 synth 产物缺失时才重建（实测 2026-10-24: 重建路径偶发
#   [Common 17-233] slave interpreter 初始化失败 / [IP_Flow 19-1747] 交付文件失败，
#   与 PITFALLS #61「安装盘偶发读失败」同族 => 重建必须带重试，且能不重建就不重建）。
set ddr4_syn [glob -nocomplain $proj/vivado/prj12.gen/sources_1/ip/ddr4_0/synth/ddr4_0.v]
if {[llength $ddr4_syn] == 0} {
    puts "DDR4_TARGET_REGEN: synth products missing -> regenerate (retry x3)"
    set ddr4_ok 0
    for {set i 1} {$i <= 3} {incr i} {
        if {[catch {
            reset_target  all [get_ips ddr4_0]
            generate_target all [get_ips ddr4_0]
        } emsg]} {
            puts "DDR4_TARGET_RETRY $i: $emsg"
            after 5000
        } else {
            set ddr4_ok 1
            break
        }
    }
    if {!$ddr4_ok} { error "ddr4_0 generate_target failed after 3 tries" }
    puts "DDR4_TARGET_OK"
} else {
    puts "DDR4_TARGET_PRESENT: skip regenerate"
}
if {[llength [get_runs -quiet ddr4_0_synth_1]] > 0} { reset_run ddr4_0_synth_1 }

# ---- prj12 (2026-10-24): 清理上次构建残留的失败/运行中 OOC run ----
#   实测: aurora_64b66b_1_synth_1 在 synth_design 起步崩过一次
#   （runme.log: "TclStackFree: incorrect freePtr"，并列 8 个 OOC run 时发生），
#   之后 launch_runs synth_1 直接拒绝启动（"These failed run(s) need to be reset"）。
#   => 每次 launch 前把 ERROR/FAIL/RUNNING 状态的 run 复位，重试才有意义。
foreach r [get_runs -quiet] {
    set rn [get_property NAME $r]
    if {$rn eq "synth_1"} { continue }
    set rstat [get_property STATUS $r]
    if {[string match -nocase "*error*" $rstat] ||
        [string match -nocase "*fail*"  $rstat] ||
        [string match -nocase "*running*" $rstat]} {
        puts "RESET_STALE_RUN: $rn ($rstat)"
        reset_run $r
    }
}

# ---- prj12 (2026-10-24): OOC IP run 逐个跑 + 单 run 重试 ----
# 实测：`launch_runs synth_1 -jobs N` 会把 16 个 OOC IP run 一起拉起来，其中一部分在
# "Launching helper process" 后立刻崩（runme.log: "TclStackFree: incorrect freePtr"），
# 而且**同一个 run 有时崩有时不崩**（mdm 连续两次成功、microblaze 崩一次后第二次成功）
# => 属于瞬态，不是设计问题；但批次级重试代价高（要整套重来）。
# 做法：先把 OOC run 串行跑完，失败的单独 reset+重试，最多 OOC_ROUNDS 轮；
#       全部 100% 后再 launch synth_1（顶层会自动复用这些 DCP）。
set ooc_runs {}
foreach r [get_runs -quiet] {
    set rn [get_property NAME $r]
    if {$rn eq "synth_1"} { continue }
    if {[string match "*_synth_1" $rn]} { lappend ooc_runs $r }
}
set ooc_rounds 4
if {[info exists ::env(P12_OOC_ROUNDS)]} { set ooc_rounds $::env(P12_OOC_ROUNDS) }
puts "OOC_RUNS: [llength $ooc_runs] rounds<=$ooc_rounds"
for {set round 1} {$round <= $ooc_rounds} {incr round} {
    set todo {}
    foreach r $ooc_runs {
        if {[get_property PROGRESS $r] ne "100%"} { lappend todo $r }
    }
    if {[llength $todo] == 0} { puts "OOC_ALL_DONE round=$round"; break }
    puts "OOC_ROUND $round: [llength $todo] run(s) to do"
    foreach r $todo {
        set rn [get_property NAME $r]
        if {[catch {
            reset_run $r
            launch_runs $r -jobs 1
            wait_on_run $r
        } emsg]} {
            puts "OOC_ERR $rn: $emsg"
            continue
        }
        puts "OOC_STEP $rn progress=[get_property PROGRESS $r] status=[get_property STATUS $r]"
    }
}
set ooc_bad {}
foreach r $ooc_runs {
    if {[get_property PROGRESS $r] ne "100%"} { lappend ooc_bad [get_property NAME $r] }
}
if {[llength $ooc_bad] > 0} { error "OOC runs still incomplete: $ooc_bad" }
puts "OOC_PRECHECK_OK: all [llength $ooc_runs] OOC runs at 100%"

reset_run synth_1
# 顶层 synth 的 -jobs 只影响它自己（OOC 已全部完成）
set synth_jobs 4
if {[info exists ::env(P12_SYNTH_JOBS)]} { set synth_jobs $::env(P12_SYNTH_JOBS) }
puts "SYNTH_JOBS: $synth_jobs"
launch_runs synth_1 -jobs $synth_jobs
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
# round3d 口径: ILA3 保持全量(判据需要 mem2/stall/len_err), 只裁 ILA5(不影响 S6/S10)
set lite_ila5 $lite_ila
if {[info exists ::env(R3C_LITE_ILA5)]} { set lite_ila5 1 }
puts "R3C_LITE_ILA: $lite_ila  R3C_LITE_ILA5: $lite_ila5"

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
if {$lite_ila5} {
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
if {!$lite_ila5} {
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

# ============ ILA6 @ user_clk —— ★prj12 P0-06: 单核链路健康（P1 上板主仪器）============
#   目的: 一块板只有 A 笼光纤, P1 首日要在**一个核**里同时看到:
#     链路态(link_ok/channel_up/lane_up/QPLL lock) + 错误(hard/soft + 粘滞计数)
#     + Aurora TX/RX 帧数(pack/unpack) + eth↔mem 泵计数(pfwd_wr/prev_wr)
#   触发建议: dbg_hard_err 或 dbg_soft_err 上升; 或 dbg_ch_up 下降(掉链瞬间)
#   域归属: 全部 user_clk 域；**B 核(user_clk_b)探针严禁挂本核**——B 核 P1 不参与判决,
#     其观测留 P2 清理 B 核时一并处理（见草案 §2.2 #3/#4）。
#   回退: P12_SKIP_ILA6=1 整核跳过（时序余量不足时；ltx 由 4 核变 3 核）
if {[info exists ::env(P12_SKIP_ILA6)]} {
    puts "ILA6_SKIPPED: env P12_SKIP_ILA6 set (timing fallback, ltx = 3 cores)"
} else {
create_debug_core u_ila_6 ila
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_6]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_6]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_6]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_6]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_6]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_6]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_6]
set_property port_width 1 [get_debug_ports u_ila_6/clk]
connect_debug_port u_ila_6/clk $uclk_net

# probe0: 链路状态 4b
set nets6a {}
foreach t {dbg_link_ok dbg_ch_up dbg_lane_up dbg_gt_pll_lock} {
    lappend nets6a [one_net $t]
}
set_property port_width [llength $nets6a] [get_debug_ports u_ila_6/probe0]
connect_debug_port u_ila_6/probe0 $nets6a
# probe1: 错误事件 2b
set nets6b {}
foreach t {dbg_hard_err dbg_soft_err} { lappend nets6b [one_net $t] }
create_debug_port u_ila_6 probe
set_property port_width [llength $nets6b] [get_debug_ports u_ila_6/probe1]
connect_debug_port u_ila_6/probe1 $nets6b
# probe2-4: 粘滞计数 ch_up_evt / hard_err_cnt / soft_err_cnt
create_debug_port u_ila_6 probe
set_property port_width 16 [get_debug_ports u_ila_6/probe2]
connect_debug_port u_ila_6/probe2 [bus_nets dbg_ch_up_evt 16]
create_debug_port u_ila_6 probe
set_property port_width 16 [get_debug_ports u_ila_6/probe3]
connect_debug_port u_ila_6/probe3 [bus_nets dbg_hard_err_cnt 16]
create_debug_port u_ila_6 probe
set_property port_width 16 [get_debug_ports u_ila_6/probe4]
connect_debug_port u_ila_6/probe4 [bus_nets dbg_soft_err_cnt 16]
# probe5-6: Aurora TX/RX 帧数（pack_frames=进 A 核 TX / unpack_frames=出 A 核 RX）
create_debug_port u_ila_6 probe
set_property port_width 16 [get_debug_ports u_ila_6/probe5]
connect_debug_port u_ila_6/probe5 [bus_nets dbg_pk_frames 16]
create_debug_port u_ila_6 probe
set_property port_width 16 [get_debug_ports u_ila_6/probe6]
connect_debug_port u_ila_6/probe6 [bus_nets dbg_up_frames 16]
# probe7-8: eth↔mem 泵计数（pfwd_wr = eth→桥①写帧 / prev_wr = 桥②读→eth）
create_debug_port u_ila_6 probe
set_property port_width 16 [get_debug_ports u_ila_6/probe7]
connect_debug_port u_ila_6/probe7 [bus_nets dbg_pfwd_wr 16]
create_debug_port u_ila_6 probe
set_property port_width 16 [get_debug_ports u_ila_6/probe8]
connect_debug_port u_ila_6/probe8 [bus_nets dbg_prev_wr 16]
# probe9: 数据通路复位（观测 channel_up 上升 ⇔ aurora_rst 释放）
create_debug_port u_ila_6 probe
set_property port_width 1 [get_debug_ports u_ila_6/probe9]
connect_debug_port u_ila_6/probe9 [list [one_net dbg_aurora_rst]]
puts "ILA6_PROBES: status=4 err=2 evt=16 hec=16 sec=16 pktx=16 pkrx=16 pfwd=16 prev=16 rst=1 (total=[expr {4+2+16*7+1}])"
}

write_checkpoint -force $proj/scripts/pre_impl_debug.dcp
close_design

# synth + ILA definition only; implementation via scripts/build_impl.tcl
puts "SYNTH_ONLY_DONE"
exit
