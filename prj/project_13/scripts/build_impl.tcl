# =============================================================================
# build_impl.tcl 鈥?prj12 P1 瀹炵幇 + 浣嶆祦锛堟部鐢?prj11 round3d 楠屾敹浣嶆祦 F6012BA0 閰嶆柟锛?
#   round3d 瀹炴祴閰嶆柟(2026-10-19): open pre_impl_debug.dcp -> implement_debug_core
#   -> opt_design -> place_design -directive ExtraTimingOpt
#   -> phys_opt AggressiveExplore -> route NoTimingRelaxation
#   -> phys_opt AggressiveExplore -> phys_opt Explore
#   => WNS +0.002 / WHS +0.004锛堥棬闄?WNS>=0 && WHS>=0 鎵嶅啓浣嶆祦锛?
# prj12 宸紓: 鍙湁 rtl 鐨?link_ok 涓€琛?+ 鏂板 u_ila_6锛堝彲閫氳繃 env 鍏抽棴锛夈€?
# 鐢ㄦ硶(ASCII 宸ヤ綔鐩綍; 鍏堣窇 build_synth_only.tcl; 纭鏃犲叾瀹?vivado 杩涚▼):
#   set P12_PLACE_DIRECTIVE=ExtraTimingOpt   # 鍙崲 ExtraPostPlacementOpt 閲嶆幏
#   vivado -mode batch -source D:\FPGA\prj\project_13\scripts\build_impl.tcl -notrace
# 浜х墿: out/aurora_mem_bridge.bit, scripts/probes.ltx, scripts/post_route.dcp,
#       out/rpt_impl_*.rpt, out/mb_ctrl.xsa锛坋nv P12_SKIP_XSA=1 鍙烦杩囷級
# 澶辫触: 鎵撳嵃 IMPL_BUILD_TIMING_FAIL 骞朵互 exit 2 閫€鍑?涓嶅啓浣嶆祦)
# =============================================================================
set proj D:/FPGA/prj/project_13
# 鈽?026-11-27 闅旂鏋勫缓锛歅13_ROOT 瑕嗙洊宸ョ▼/浜х墿鏍癸紙榛樿涓嶈 => 涓诲伐绋嬶紝琛屼负涓嶅彉锛?
if {[info exists ::env(P13_ROOT)] && $::env(P13_ROOT) ne ""} { set proj $::env(P13_ROOT) }
puts "P13_ROOT: $proj"
file mkdir $proj/out

# 鈽?026-11-27 鍙樹綋杈撳嚭瀛愮洰褰曪細涓嶅悓瑙掕壊/鍙樹綋涓嶄簰鐩歌鐩?
set outdir $proj/out
if {[info exists ::env(P13_OUT_SUB)] && $::env(P13_OUT_SUB) ne ""} {
    set outdir $proj/out/$::env(P13_OUT_SUB)
}
file mkdir $outdir
puts "P13_OUTDIR: $outdir"

set directive ExtraTimingOpt
if {[info exists ::env(P12_PLACE_DIRECTIVE)]} { set directive $::env(P12_PLACE_DIRECTIVE) }

set dcp $proj/scripts/pre_impl_debug.dcp
if {![file exists $dcp]} { error "pre_impl_debug.dcp not found: run build_synth_only.tcl first" }

puts "IMPL_DIRECTIVE: $directive"
open_checkpoint $dcp
if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost after checkpoint reopen" }
puts "IMPL_DEBUG_CORES: [llength [get_debug_cores -quiet]]"
implement_debug_core

# ★2026-11-27: opt_design 的 Phase 1 会重新生成并缝合 ddr4_phy（MIG），实测偶发
#   `couldn't read file ".../scripts/rt/data/unimacro/unimacro_verilog.tcl": No error`
#   -> `[Mig 66-119] Phy core regeneration & stitching failed`（= 坑 #61 的
#   "安装盘瞬态读失败"，与设计无关；该文件实测存在且可读，1097 B）。
#   处置：最多 3 次重试；每次都从 dcp 重新 open_checkpoint + implement_debug_core，
#   不在失败状态上继续，避免把瞬态错误带进后续 stage。
set opt_ok 0
for {set _try 1} {$_try <= 3} {incr _try} {
    if {[catch { opt_design } _emsg]} {
        puts "IMPL_OPT_RETRY $_try: $_emsg"
        catch { close_design }
        after 8000
        open_checkpoint $dcp
        if {[llength [get_debug_cores -quiet]] == 0} { error "debug cores lost on reopen" }
        implement_debug_core
    } else {
        set opt_ok 1
        break
    }
}
if {!$opt_ok} {
    puts "IMPL_OPT_FAILED: opt_design failed after 3 tries (transient MIG read failure?)"
    catch { close_design }
    exit 3
}
puts "IMPL_OPT_OK: opt_design done"
place_design       -directive $directive
phys_opt_design    -directive AggressiveExplore
route_design       -directive NoTimingRelaxation
phys_opt_design    -directive AggressiveExplore
phys_opt_design    -directive Explore

# 鈽?026-10-24 瀹炴祴绾犻敊: 鍘熷厛鍐?`-delay_type min_max -max_paths 1 -sort_by slack`,
#   瀹冭繑鍥?setup+hold 閲?*鏈€宸殑閭ｆ潯璺緞**锛堟湰渚嬫槸 hold 0.004锛夛紝浜庢槸鏃ュ織鎶?WNS 鎵撴垚
#   0.004锛岃€?report_timing_summary 鐨勭湡瀹?WNS 鏄?+0.032銆傞棬闄愮粨璁轰笉鍙橈紙閮?鈮?锛夛紝
#   浣嗗彛寰勯敊浜?=> setup 鐢?-delay_type max銆乭old 鐢?-delay_type min锛?
#   瀵瑰鎶ュ憡涓€寰嬩互 rpt_impl_timing_summary.rpt 鐨?Design Timing Summary 涓哄噯銆?
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -sort_by slack]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]]
puts "IMPL_GATE: directive=$directive WNS=$wns WHS=$whs"

report_clocks -file $outdir/rpt_impl_clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
                      -max_paths 10 -file $outdir/rpt_impl_timing_summary.rpt
report_timing -max_paths 30 -sort_by slack -file $outdir/rpt_impl_worst.rpt
report_utilization -file $outdir/rpt_impl_util.rpt
# ★2026-11-27 出件判据要求留原始件：DRC / CDC / check_timing
#   （用 catch 包住：这三份是"证据"，不应改变是否写位流的主判据）
catch { report_drc -file $outdir/rpt_impl_drc.rpt }
catch { report_cdc -details -file $outdir/rpt_impl_cdc.rpt }
catch { check_timing -verbose -file $outdir/rpt_impl_check_timing.rpt }
puts "IMPL_EXTRA_REPORTS: drc/cdc/check_timing -> $outdir"
# CW/鏃跺簭杩濅緥閫熸煡锛坆uild 鎶ュ憡鐢級
set failing [get_timing_paths -delay_type min_max -max_paths 10000 -filter {SLACK < 0}]
puts "IMPL_FAILING_ENDPOINTS_SAMPLE: [llength $failing]"

if {$wns >= 0 && $whs >= 0} {
    write_checkpoint -force $proj/scripts/post_route.dcp
    write_debug_probes -force $outdir/probes.ltx
    write_bitstream -force $outdir/aurora_mem_bridge.bit
    if {![info exists ::env(P12_SKIP_XSA)]} {
        write_hw_platform -fixed -include_bit -force $outdir/mb_ctrl.xsa
        puts "IMPL_XSA: $outdir/mb_ctrl.xsa"
    }
    puts "IMPL_BUILD_OK: bit=$outdir/aurora_mem_bridge.bit ltx=$outdir/probes.ltx"
} else {
    puts "IMPL_BUILD_TIMING_FAIL: wns=$wns whs=$whs (鏈啓浣嶆祦; 鎹?P12_PLACE_DIRECTIVE 閲嶆幏)"
    close_design
    exit 2
}
close_design
exit 0
