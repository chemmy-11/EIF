# =============================================================================
# b2_pre_hook.tcl -- B2 诊断件预钩子（在 build_synth_only.tcl 的**综合前**被 source）
# -----------------------------------------------------------------------------
# 职责：建 B2 专属的暂停控制 VIO（vio_p2_pause，0 输入 / 1 输出 / 1 bit）。
#
# 为什么用 VIO IP 而不是 create_debug_core：
#   Vivado 2023.1 的 create_debug_core 只支持 ila，建 vio 会报 [Vivado 12-3620]
#   （本工程 2026-11-20 实测，同理见 scripts/build_synth_only.tcl 的 VIO 段注释）。
#
# 为什么不改 vio_link_health：
#   那个核的 5 个输入探针顺序被 scripts/read_link_health.tcl 硬绑定，
#   改它的 CONFIG.C_NUM_PROBE_OUT 需要重新生成 IP 且动到既有读出链路；
#   新开一个 1 bit 输出的核代价更小、互不影响。
#
# 幂等：IP 已存在则复用；不重复 generate_target。
# 触发方式：由驱动脚本设好 ::env(P13_PRE_HOOK) 后由主脚本 source。
# =============================================================================

if {[llength [get_ips -quiet vio_p2_pause]] == 0} {
    create_ip -name vio -vendor xilinx.com -library ip -module_name vio_p2_pause
    # 只设有把握的参数（坑 #10：set_property 遇到不存在的参数名是致命错）。
    set_property -dict [list \
        CONFIG.C_NUM_PROBE_IN      {0} \
        CONFIG.C_NUM_PROBE_OUT     {1} \
        CONFIG.C_PROBE_OUT0_WIDTH  {1} \
    ] [get_ips vio_p2_pause]
    generate_target {instantiation_template synthesis simulation} [get_ips vio_p2_pause]
    puts "B2_CREATE_IP: vio_p2_pause (in=0 out=1 width=1)"
} else {
    puts "B2_CREATE_IP: vio_p2_pause 已存在，复用"
    puts "B2_VIO_PAUSE_CFG: NUM_PROBE_IN=[get_property CONFIG.C_NUM_PROBE_IN [get_ips vio_p2_pause]] NUM_PROBE_OUT=[get_property CONFIG.C_NUM_PROBE_OUT [get_ips vio_p2_pause]]"
}
update_compile_order -fileset sources_1
puts "B2_PRE_HOOK_DONE"
