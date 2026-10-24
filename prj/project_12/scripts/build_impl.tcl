# =============================================================================
# build_impl.tcl — prj12 P1 实现 + 位流（沿用 prj11 round3d 验收位流 F6012BA0 配方）
#   round3d 实测配方(2026-10-19): open pre_impl_debug.dcp -> implement_debug_core
#   -> opt_design -> place_design -directive ExtraTimingOpt
#   -> phys_opt AggressiveExplore -> route NoTimingRelaxation
#   -> phys_opt AggressiveExplore -> phys_opt Explore
#   => WNS +0.002 / WHS +0.004（门限 WNS>=0 && WHS>=0 才写位流）
# prj12 差异: 只有 rtl 的 link_ok 一行 + 新增 u_ila_6（可通过 env 关闭）。
# 用法(ASCII 工作目录; 先跑 build_synth_only.tcl; 确认无其它 vivado 进程):
#   set P12_PLACE_DIRECTIVE=ExtraTimingOpt   # 可换 ExtraPostPlacementOpt 重掷
#   vivado -mode batch -source D:\FPGA\prj\project_12\scripts\build_impl.tcl -notrace
# 产物: out/aurora_mem_bridge.bit, scripts/probes.ltx, scripts/post_route.dcp,
#       out/rpt_impl_*.rpt, out/mb_ctrl.xsa（env P12_SKIP_XSA=1 可跳过）
# 失败: 打印 IMPL_BUILD_TIMING_FAIL 并以 exit 2 退出(不写位流)
# =============================================================================
set proj D:/FPGA/prj/project_12
file mkdir $proj/out

set directive ExtraTimingOpt
if {[info exists ::env(P12_PLACE_DIRECTIVE)]} { set directive $::env(P12_PLACE_DIRECTIVE) }

set dcp $proj/scripts/pre_impl_debug.dcp
if {![file exists $dcp]} { error "pre_impl_debug.dcp not found: run build_synth_only.tcl first" }

puts "IMPL_DIRECTIVE: $directive"
open_checkpoint $dcp
if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost after checkpoint reopen" }
puts "IMPL_DEBUG_CORES: [llength [get_debug_cores -quiet]]"
implement_debug_core

opt_design
place_design       -directive $directive
phys_opt_design    -directive AggressiveExplore
route_design       -directive NoTimingRelaxation
phys_opt_design    -directive AggressiveExplore
phys_opt_design    -directive Explore

set wns [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by slack]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]]
puts "IMPL_GATE: directive=$directive WNS=$wns WHS=$whs"

report_clocks -file $proj/out/rpt_impl_clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
                      -max_paths 10 -file $proj/out/rpt_impl_timing_summary.rpt
report_timing -max_paths 30 -sort_by slack -file $proj/out/rpt_impl_worst.rpt
report_utilization -file $proj/out/rpt_impl_util.rpt
# CW/时序违例速查（build 报告用）
set failing [get_timing_paths -delay_type min_max -max_paths 10000 -filter {SLACK < 0}]
puts "IMPL_FAILING_ENDPOINTS_SAMPLE: [llength $failing]"

if {$wns >= 0 && $whs >= 0} {
    write_checkpoint -force $proj/scripts/post_route.dcp
    write_debug_probes -force $proj/scripts/probes.ltx
    write_bitstream -force $proj/out/aurora_mem_bridge.bit
    if {![info exists ::env(P12_SKIP_XSA)]} {
        write_hw_platform -fixed -include_bit -force $proj/out/mb_ctrl.xsa
        puts "IMPL_XSA: $proj/out/mb_ctrl.xsa"
    }
    puts "IMPL_BUILD_OK: bit=$proj/out/aurora_mem_bridge.bit ltx=$proj/scripts/probes.ltx"
} else {
    puts "IMPL_BUILD_TIMING_FAIL: wns=$wns whs=$whs (未写位流; 换 P12_PLACE_DIRECTIVE 重掷)"
    close_design
    exit 2
}
close_design
exit 0
