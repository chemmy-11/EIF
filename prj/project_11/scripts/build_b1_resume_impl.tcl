# =============================================================================
# build_b1_resume_impl.tcl — prj11 续跑: 从 pre_impl_debug.dcp 续到位流
# 用于 build_debug.tcl 在 opt_design 的 MIG PHY 缝合瞬态失败后的重试
# (prj10 史上同症: "Phy core regeneration & stitching failed" 一次重跑即过,
#  综合与 ILA 插入均已完成, 全部复用)。
# 用法: vivado -mode batch -source scripts\build_b1_resume_impl.tcl -notrace
# =============================================================================
set proj D:/FPGA/prj/project_11

open_checkpoint $proj/scripts/pre_impl_debug.dcp
if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost after checkpoint reopen" }
implement_debug_core
write_debug_probes -force $proj/scripts/probes.ltx

opt_design
place_design       -directive ExtraTimingOpt
phys_opt_design    -directive AggressiveExplore
route_design       -directive NoTimingRelaxation
phys_opt_design    -directive AggressiveExplore

report_clocks            -file $proj/out/rpt_clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
                         -max_paths 10 -file $proj/out/rpt_timing_summary.rpt
report_timing -max_paths 25 -sort_by slack -file $proj/out/rpt_timing_worst.rpt
puts "TIMING: [get_property SLACK [get_timing_paths -max_paths 1 -sort_by slack]]"

write_checkpoint -force $proj/scripts/post_route.dcp

set wns5 [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by slack]]
set whs5 [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]]
puts "WNS_GATE: $wns5"
puts "WHS_GATE: $whs5"
if {$wns5 >= 0 && $whs5 >= 0} {
    write_bitstream -force $proj/out/aurora_mem_bridge.bit
    write_hw_platform -fixed -include_bit -force $proj/out/mb_ctrl.xsa
    puts "DBG_BUILD_DONE: bit=$proj/out/aurora_mem_bridge.bit ltx=$proj/scripts/probes.ltx xsa=$proj/out/mb_ctrl.xsa"
    puts "W5_BUILD_OK"
} else {
    puts "W5_BUILD_TIMING_FAIL: wns=$wns5 whs=$whs5 (未写位流)"
}
