# build_b1_resume_impl2.tcl — 时序重掷: 换 place 指令(Explore)避开同一布局收敛点
set proj D:/FPGA/prj/project_11
open_checkpoint $proj/scripts/pre_impl_debug.dcp
if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost after checkpoint reopen" }
implement_debug_core
write_debug_probes -force $proj/scripts/probes.ltx
opt_design
place_design       -directive Explore
phys_opt_design    -directive AggressiveExplore
route_design       -directive AggressiveExplore
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
    puts "W5_BUILD_TIMING_FAIL: wns=$wns5 whs=$whs5"
}
