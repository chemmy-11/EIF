# =============================================================================
# build_rdprobe.tcl — prj11 B3-1b v5: 在 pre_impl_debug.dcp 上追加「发射字节流」探针
#   目的: 直接观测 frame_mem_if 读侧发射字节 (mem_rd_data[7:0] + dbg_mem_rden),
#         与已知帧逐字节比对, 定位 E 模式 0 回显的字节级损坏点(需重建位流)。
#   做法: 复用既有综合/ILA 检查点, 只在 u_ila_0 新建 probe1(9 bit) —— 不动 probe0,
#         不改 RTL(= 无综合风险)。移植自 build_b1_resume_impl.tcl(v3 末版指令)。
#   产物(另名, 不覆盖 v3 a432addd): out/aurora_mem_bridge_rdprobe.bit +
#         out/probes_rdprobe.ltx + out/mb_ctrl_rdprobe.xsa + scripts/post_route_rdprobe.dcp
# =============================================================================
set proj D:/FPGA/prj/project_11

open_checkpoint $proj/scripts/pre_impl_debug.dcp
if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost after checkpoint reopen" }

set nets {}
lappend nets [get_nets -quiet dbg_mem_rden]
foreach i {0 1 2 3 4 5 6 7} { lappend nets [get_nets -quiet "mem_rd_data\[$i\]"] }
if {[llength $nets] != 9 || [lsearch $nets ""] >= 0} { error "target nets missing: $nets" }
puts "RDPROBE_TARGET_NETS: $nets"

create_debug_port u_ila_0 probe
set p [get_debug_ports u_ila_0/probe1]
if {$p eq ""} { error "probe1 not created" }
set_property port_width 9 $p
connect_debug_port u_ila_0/probe1 $nets
puts "RDPROBE_CONNECTED width=[get_property port_width $p]"

implement_debug_core
write_debug_probes -force $proj/out/probes_rdprobe.ltx

opt_design
place_design       -directive ExtraPostPlacementOpt
phys_opt_design    -directive AggressiveExplore
route_design       -directive NoTimingRelaxation
phys_opt_design    -directive AggressiveExplore
phys_opt_design    -directive Explore

report_clocks            -file $proj/out/rpt_rdprobe_clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
                         -max_paths 10 -file $proj/out/rpt_rdprobe_timing_summary.rpt
report_timing -max_paths 25 -sort_by slack -file $proj/out/rpt_rdprobe_timing_worst.rpt
puts "TIMING: [get_property SLACK [get_timing_paths -max_paths 1 -sort_by slack]]"

write_checkpoint -force $proj/scripts/post_route_rdprobe.dcp

set wns [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by slack]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]]
puts "WNS_GATE: $wns"
puts "WHS_GATE: $whs"
if {$wns >= 0 && $whs >= 0} {
    write_bitstream -force $proj/out/aurora_mem_bridge_rdprobe.bit
    write_hw_platform -fixed -include_bit -force $proj/out/mb_ctrl_rdprobe.xsa
    puts "RDPROBE_BUILD_OK: bit=$proj/out/aurora_mem_bridge_rdprobe.bit ltx=$proj/out/probes_rdprobe.ltx"
} else {
    puts "RDPROBE_BUILD_TIMING_FAIL: wns=$wns whs=$whs (未写位流)"
}
exit
