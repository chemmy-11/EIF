# =============================================================================
# build_v5_sweep.tcl — v5(DROP=0)时序扫描: 逐个 place 指令重掷, 首个过门限者出位流
#   背景: 同网表 ExtraPostPlacementOpt = -0.017 / Explore = -0.185 均被门限拒;
#         该设计 WNS 长期在 0 附近震荡(build15/16 史), 故按指令扫描收敛。
#   用法: vivado -mode batch -source scripts\build_v5_sweep.tcl -notrace
# =============================================================================
set proj D:/FPGA/prj/project_11
set dirs {ExtraTimingOpt Default AggressiveExplore WLDrivenBlockPlacement}
set ok 0

foreach d $dirs {
    puts "==================== TRY place -directive $d ===================="
    # 每条指令独立 catch: MIG PHY 缝合瞬态失败(Opt 31-306 / Mig 66-119)不终止整轮扫描
    if {[catch {
    open_checkpoint $proj/scripts/pre_impl_debug.dcp
    if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost" }
    implement_debug_core
    write_debug_probes -force $proj/out/probes_v5_$d.ltx

    opt_design
    place_design       -directive $d
    phys_opt_design    -directive AggressiveExplore
    route_design       -directive NoTimingRelaxation
    phys_opt_design    -directive AggressiveExplore
    phys_opt_design    -directive Explore

    set wns [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by slack]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]]
    puts "SWEEP_$d: WNS=$wns WHS=$whs"

    if {$wns >= 0 && $whs >= 0} {
        write_checkpoint -force $proj/scripts/post_route_v5.dcp
        write_debug_probes -force $proj/scripts/probes.ltx
        write_bitstream -force $proj/out/aurora_mem_bridge.bit
        write_hw_platform -fixed -include_bit -force $proj/out/mb_ctrl.xsa
        report_timing -max_paths 25 -sort_by slack -file $proj/out/rpt_v5_timing_worst.rpt
        puts "V5_SWEEP_OK: directive=$d wns=$wns bit=$proj/out/aurora_mem_bridge.bit"
        set ok 1
        break
    }
    close_design
    } emsg]} {
        puts "SWEEP_$d: ABORT/TRANSIENT -> $emsg"
        catch {close_design}
    }
}
if {!$ok} { puts "V5_SWEEP_ALL_FAIL" }
exit
