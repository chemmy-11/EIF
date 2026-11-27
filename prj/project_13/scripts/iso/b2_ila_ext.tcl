# =============================================================================
# b2_ila_ext.tcl -- B2 诊断件追加 ILA 核（在 build_synth_only.tcl 的 write_checkpoint
#                   之前被 source；此时 open_run synth_1 已完成，可 get_nets）
# -----------------------------------------------------------------------------
# 核：u_ila_8，采样时钟 = gmii_rx_clk（= eth_rxc，RGMII RX 时钟，链路上行时自由运行）
#     全部探针都在这一域内，符合 UG908「调试核时钟必须与被测信号同域」
#     （与既有 ILA7 同源；Aurora 侧的 p2_st_aur_* 不挂本核，避免跨域采样 —— 见
#      docs/M1_prj13_双板恢复与A1收口操作单_2026-11-23.md 记录的上一轮 ILA8 错配）
#
# 探针编排（**位序即 LTX 位序，改动必须同步更新此表**）：
#   probe0 [9:0]  单 bit 事件/握手
#        [0] dbg_b2_pause        暂停态（0 = 生产语义）
#        [1] dbg_b2_rxbf_vld     入口 RAM 读侧 valid（原始）
#        [2] dbg_b2_buf_rdy      门控后送 RAM 的 rd_ready
#        [3] dbg_b2_ext_rdy      提取器原始 s_ready（未门控）
#        [4] dbg_b2_rx_sop       入口帧边界：帧首
#        [5] dbg_b2_rx_eop       入口帧边界：帧尾
#        [6] dbg_b2_rx_drop      入口整帧拒收脉冲
#        [7] dbg_b2_ep_ok        1 = 处于同一未复位区间（~aurora_rst）
#        [8] dbg_b2_bank_busy[0] 槽0 占用
#        [9] dbg_b2_bank_busy[1] 槽1 占用
#   probe1 [15:0] dbg_b2_rx_drop16   st_rx_drop[15:0]（16 位源，顶层扩展成 32）
#   probe2 [8:0]  dbg_b2_relay_en + dbg_b2_relay_data[7:0]
#   probe3 [15:0] dbg_b2_relay16    st_relay[15:0]（relay 模差 +2 的取证点）
#   合计 51 bit / depth 1024
#
# 回退：env P13_SKIP_ILA8=1 整核跳过（时序不足时；D-fix 的 WNS 只有 +0.021）
# =============================================================================

if {[info exists ::env(P13_SKIP_ILA8)] && $::env(P13_SKIP_ILA8) eq "1"} {
    puts "B2_ILA8: SKIPPED (P13_SKIP_ILA8=1)"
} else {
    set grx8 [get_nets -quiet [list gmii_rx_clk]]
    if {[llength $grx8] == 0} {
        set grx8 [get_nets -hier -quiet -filter {NAME =~ *gmii_rx_clk}]
    }
    puts "B2_ILA8_CLK_NET: count=[llength $grx8]"
    if {[llength $grx8] == 0} {
        error "B2_ILA8: gmii_rx_clk net not found"
    } else {
        create_debug_core u_ila_8 ila
        # 2023.1 C_DATA_DEPTH 合法最小值 1024（坑 #67：512 报 [Vivado 12-206]）
        set_property C_DATA_DEPTH          1024 [get_debug_cores u_ila_8]
        set_property C_TRIGIN_EN           false [get_debug_cores u_ila_8]
        set_property C_TRIGOUT_EN          false [get_debug_cores u_ila_8]
        set_property C_INPUT_PIPE_STAGES   1 [get_debug_cores u_ila_8]
        set_property C_EN_STRG_QUAL        false [get_debug_cores u_ila_8]
        set_property ALL_PROBE_SAME_MU     true [get_debug_cores u_ila_8]
        set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_8]
        set_property port_width 1 [get_debug_ports u_ila_8/clk]
        connect_debug_port u_ila_8/clk [lindex $grx8 0]

        # ---- probe0: 10 bit 单 bit 事件/握手（位序见文件头）----
        set n8a {}
        foreach t {dbg_b2_pause dbg_b2_rxbf_vld dbg_b2_buf_rdy dbg_b2_ext_rdy \
                   dbg_b2_rx_sop dbg_b2_rx_eop dbg_b2_rx_drop dbg_b2_ep_ok} {
            lappend n8a [one_net $t]
        }
        foreach n [bus_nets dbg_b2_bank_busy 2] { lappend n8a $n }
        set_property port_width [llength $n8a] [get_debug_ports u_ila_8/probe0]
        connect_debug_port u_ila_8/probe0 $n8a

        # ---- probe1: 16 bit 入口缓冲丢弃计数低 16 位 ----
        create_debug_port u_ila_8 probe
        set n8b [bus_nets dbg_b2_rx_drop16 16]
        set_property port_width [llength $n8b] [get_debug_ports u_ila_8/probe1]
        connect_debug_port u_ila_8/probe1 $n8b

        # ---- probe2: 9 bit relay 出口（en + 字节）----
        #   P13_ILA8_LEAN=1 时只保留 relay_en（9 -> 1 bit）：时序不够时优先牺牲
        #   "relay 字节流"这类旁证，**必须保留的**是 pause / 两槽占用 / 入口帧边界 /
        #   drop pulse / 丢弃计数(probe1) / relay 计数(probe3) —— 判据不依赖字节流。
        create_debug_port u_ila_8 probe
        set n8c {}
        lappend n8c [one_net dbg_b2_relay_en]
        if {[info exists ::env(P13_ILA8_LEAN)] && $::env(P13_ILA8_LEAN) eq "1"} {
            puts "B2_ILA8_LEAN: relay_data[7:0] 已裁（只留 relay_en）"
        } else {
            foreach n [bus_nets dbg_b2_relay_data 8] { lappend n8c $n }
        }
        set_property port_width [llength $n8c] [get_debug_ports u_ila_8/probe2]
        connect_debug_port u_ila_8/probe2 $n8c

        # ---- probe3: 16 bit relay 计数低 16 位（模差 +2 取证）----
        create_debug_port u_ila_8 probe
        set n8d [bus_nets dbg_b2_relay16 16]
        set_property port_width [llength $n8d] [get_debug_ports u_ila_8/probe3]
        connect_debug_port u_ila_8/probe3 $n8d

        puts "B2_ILA8_PROBES: p0=[llength $n8a] p1=[llength $n8b] p2=[llength $n8c] p3=[llength $n8d] total=[expr {[llength $n8a]+[llength $n8b]+[llength $n8c]+[llength $n8d]}]"
    }
}
