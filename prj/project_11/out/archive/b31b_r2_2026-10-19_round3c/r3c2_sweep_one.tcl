# =============================================================================
# build_v5_sweep2.tcl ??R2 ?????????: ??? place ??? + **?????????/dcp**
#   ??? (2026-10-17 23:5x): build_v5_sweep.tcl ??? ExtraTimingOpt ??? WNS=-0.098
#   ??????; Default MIG ???? AggressiveExplore ??????; WLDriven ?????#   ????? ??? ExtraPostPlacementOpt (R1 v3/rdfix ???????, ??????
#   post_route_fail_<d>.dcp + ???/???????? ?????????????(???????#   ???: vivado -mode batch -source scripts\build_v5_sweep2.tcl -notrace
# =============================================================================
set proj D:/FPGA/prj/project_11
#   2026-10-18: R2 ??????????? ????????????????(ExtraTimingOpt -0.098 > ExtraPostPlacementOpt -0.175)
set dirs {ExtraTimingOpt}
set ok 0

foreach d $dirs {
    puts "==================== TRY2 place -directive $d ===================="
    if {[catch {
    open_checkpoint $proj/scripts/pre_impl_debug.dcp
    if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost" }
    implement_debug_core

    opt_design
    place_design       -directive $d
    phys_opt_design    -directive AggressiveExplore
    route_design       -directive NoTimingRelaxation
    phys_opt_design    -directive AggressiveExplore
    phys_opt_design    -directive Explore

    set wns [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by slack]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]]
    puts "SWEEP1_$d: WNS=$wns WHS=$whs"
    report_timing -max_paths 30 -sort_by slack -file $proj/out/rpt3_$d.worst.rpt
    report_utilization -file $proj/out/rpt3_$d.util.rpt
    write_checkpoint -force $proj/scripts/post_route_one_\$d.dcp

    if {$wns >= 0 && $whs >= 0} {
        write_debug_probes -force $proj/scripts/probes.ltx
        write_bitstream -force $proj/out/aurora_mem_bridge.bit
        write_hw_platform -fixed -include_bit -force $proj/out/mb_ctrl.xsa
        report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
                             -max_paths 10 -file $proj/out/rpt3_$d.timing_summary.rpt
        puts "V5_SWEEP1_OK: directive=$d wns=$wns whs=$whs bit=$proj/out/aurora_mem_bridge.bit"
        set ok 1
        # ??break: ??catch ?????????????????ok ?????exit (???????????
        exit
    } else {
        puts "SWEEP1_$d: GATE_FAIL (???/dcp ?????????)"
    }
    close_design
    } emsg]} {
        puts "SWEEP1_$d: ABORT/TRANSIENT -> $emsg"
        catch {close_design}
    }
}
if {!$ok} { puts "V5_SWEEP1_ALL_FAIL" }
exit
