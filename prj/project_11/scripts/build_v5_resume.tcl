# =============================================================================
# build_v5_resume.tcl — v5(DROP_BYTES=0 + DMA_LENGTH=len) 重掷: 从 pre_impl_debug.dcp 续跑
#   背景: build_debug.tcl 首掷 WNS -0.017 被门限拒(设计在 ±0.02 边缘, 先例 = 换 place 指令重掷)。
#   检查点已含: v5 RTL(DROP=0)综合结果 + 全部 ILA(含 probe1 发射字节流)。
#   用法: vivado -mode batch -source scripts\build_v5_resume.tcl -notrace
# =============================================================================
set proj D:/FPGA/prj/project_11

open_checkpoint $proj/scripts/pre_impl_debug.dcp
if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost after checkpoint reopen" }
implement_debug_core
write_debug_probes -force $proj/scripts/probes.ltx

opt_design
place_design       -directive Explore
phys_opt_design    -directive AggressiveExplore
route_design       -directive NoTimingRelaxation
phys_opt_design    -directive AggressiveExplore
phys_opt_design    -directive Explore

report_clocks            -file $proj/out/rpt_v5_clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
                         -max_paths 10 -file $proj/out/rpt_v5_timing_summary.rpt
report_timing -max_paths 25 -sort_by slack -file $proj/out/rpt_v5_timing_worst.rpt
puts "TIMING: [get_property SLACK [get_timing_paths -max_paths 1 -sort_by slack]]"

write_checkpoint -force $proj/scripts/post_route_v5.dcp

set wns [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by slack]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]]
puts "WNS_GATE: $wns"
puts "WHS_GATE: $whs"
if {$wns >= 0 && $whs >= 0} {
    write_bitstream -force $proj/out/aurora_mem_bridge.bit
    write_hw_platform -fixed -include_bit -force $proj/out/mb_ctrl.xsa
    puts "V5_BUILD_OK: bit=$proj/out/aurora_mem_bridge.bit ltx=$proj/scripts/probes.ltx xsa=$proj/out/mb_ctrl.xsa"
} else {
    puts "V5_BUILD_TIMING_FAIL: wns=$wns whs=$whs (未写位流)"
}
exit
