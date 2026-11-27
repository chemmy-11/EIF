# =============================================================================
# b1_ila_ext.tcl -- B1 正式 V4 追加 ILA 核（write_checkpoint 之前 source）
# -----------------------------------------------------------------------------
# 2026-11-27 v2：**按域 + 按类拆成 5 个核**。
#   背景（实测）：v1 把所有 eth 域计数塞进单个 465 bit 核，A 角实现两次不同 place
#   指令分别是 -0.080 / -0.035，且 -0.035 重掷逐位复现 => 不是波动而是时序地板。
#   拆核让每个核的采样寄存器就近布局，降低单核宽 MUX 的布线拥塞；总位数不变。
#   位宽与采样域仍严格按 EIF #18：4×32 基础 + 16 入口丢弃 + 十类×32（eth 域），
#   3×16 + 32（user 域）。
# 探针位序（= LTX 位序）：
#   u_ila_8  @gmii_rx_clk 145b : ep_ok(1) rx_frames(32) relay(32) local(32) arp(32) rx_drop16(16)
#   u_ila_9  @gmii_rx_clk  96b : vlan(32) ipv6(32) ethertype(32)
#   u_ila_10 @gmii_rx_clk  96b : broadcast(32) multicast(32) unknown_dst(32)
#   u_ila_11 @gmii_rx_clk 128b : oversize(32) bad_csum(32) truncated(32) mac(32)
#   u_ila_12 @user_clk     80b : aur_frames(16) aur_drop(16) lan_frames(16) bad_v4(32)
# 回退：P13_SKIP_ILA8=1 跳过全部 eth 域核；P13_SKIP_ILA9=1 跳过 user 域核
# =============================================================================

proc b1_mk_ila {core clknet} {
    create_debug_core $core ila
    set_property C_DATA_DEPTH          1024 [get_debug_cores $core]
    set_property C_TRIGIN_EN           false [get_debug_cores $core]
    set_property C_TRIGOUT_EN          false [get_debug_cores $core]
    set_property C_INPUT_PIPE_STAGES   1 [get_debug_cores $core]
    set_property C_EN_STRG_QUAL        false [get_debug_cores $core]
    set_property ALL_PROBE_SAME_MU     true [get_debug_cores $core]
    set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores $core]
    set_property port_width 1 [get_debug_ports $core/clk]
    connect_debug_port $core/clk $clknet
}

proc b1_probe {core nets} {
    set_property port_width [llength $nets] [get_debug_ports $core/probe0]
    connect_debug_port $core/probe0 $nets
    puts "B1_ILA_PROBE: $core/probe0 width=[llength $nets]"
}

proc b1_clk {name fallback} {
    set n [get_nets -quiet [list $name]]
    if {[llength $n] == 0} { set n [get_nets -hier -quiet -filter "NAME =~ *$name"] }
    if {[llength $n] == 0 && $fallback ne ""} {
        set n [get_nets -quiet -of_objects [get_pins -quiet $fallback]]
    }
    if {[llength $n] == 0} { error "B1_ILA: clock net $name not found" }
    return [lindex $n 0]
}

if {[info exists ::env(P13_SKIP_ILA8)] && $::env(P13_SKIP_ILA8) eq "1"} {
    puts "B1_ILA_ETH: SKIPPED (P13_SKIP_ILA8=1)"
} else {
    set ec [b1_clk gmii_rx_clk ""]

    # ---- 核 1：基础计数 + 入口丢弃 ----
    b1_mk_ila u_ila_8 $ec
    set a {}
    lappend a [one_net dbg_b1_ep_ok]
    foreach t {dbg_b1_rx_frames dbg_b1_relay dbg_b1_local dbg_b1_arp} {
        foreach n [bus_nets $t 32] { lappend a $n }
    }
    foreach n [bus_nets dbg_b1_rx_drop16 16] { lappend a $n }
    b1_probe u_ila_8 $a

    # ---- 核 2：VLAN / IPv6 / EtherType ----
    b1_mk_ila u_ila_9 $ec
    set b {}
    foreach t {dbg_b1_d_vlan dbg_b1_d_ipv6 dbg_b1_d_etype} {
        foreach n [bus_nets $t 32] { lappend b $n }
    }
    b1_probe u_ila_9 $b

    # ---- 核 3：广播 / 组播 / 未知目的 ----
    b1_mk_ila u_ila_10 $ec
    set c {}
    foreach t {dbg_b1_d_bcast dbg_b1_d_mcast dbg_b1_d_unknown} {
        foreach n [bus_nets $t 32] { lappend c $n }
    }
    b1_probe u_ila_10 $c

    # ---- 核 4：超长 / 坏校验 / 截断 / 错误 MAC ----
    b1_mk_ila u_ila_11 $ec
    set d {}
    foreach t {dbg_b1_d_oversize dbg_b1_d_csum dbg_b1_d_trunc dbg_b1_d_mac} {
        foreach n [bus_nets $t 32] { lappend d $n }
    }
    b1_probe u_ila_11 $d

    puts "B1_ILA_ETH_TOTAL: [expr {[llength $a]+[llength $b]+[llength $c]+[llength $d]}] bit in 4 cores"
}

if {[info exists ::env(P13_SKIP_ILA9)] && $::env(P13_SKIP_ILA9) eq "1"} {
    puts "B1_ILA_USER: SKIPPED (P13_SKIP_ILA9=1)"
} else {
    set uc [b1_clk user_clk {u_pack/frame_active_reg/C}]
    b1_mk_ila u_ila_12 $uc
    set e {}
    foreach t {dbg_b1_aur_frames dbg_b1_aur_drop dbg_b1_lan_frames} {
        foreach n [bus_nets $t 16] { lappend e $n }
    }
    foreach n [bus_nets dbg_b1_bad_v4 32] { lappend e $n }
    b1_probe u_ila_12 $e
    puts "B1_ILA_USER_TOTAL: [llength $e] bit in 1 core @ user_clk"
}
