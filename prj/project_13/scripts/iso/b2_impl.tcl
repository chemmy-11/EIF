# =============================================================================
# b2_impl.tcl -- B2 入口缓冲丢弃触发件：隔离工程实现 + 位流（软 A 单角色）
# -----------------------------------------------------------------------------
# 前置：b2_synth.tcl 已产出 <root>/scripts/pre_impl_debug.dcp（含 u_ila_8）
# 配方：沿用 build_impl.tcl（= prj11 round3d 验收配方）
#       opt -> place(ExtraTimingOpt) -> phys_opt AggressiveExplore
#       -> route NoTimingRelaxation -> phys_opt AggressiveExplore -> phys_opt Explore
# 产物（全部落在 <root>/out/<P13_OUT_SUB>，不覆盖既有 D-fix 产物）：
#   aurora_mem_bridge.bit / probes.ltx / post_route.dcp
#   rpt_impl_timing_summary.rpt / rpt_impl_worst.rpt / rpt_impl_clocks.rpt
#   rpt_impl_util.rpt / rpt_impl_drc.rpt / rpt_impl_cdc.rpt / rpt_impl_check_timing.rpt
# 失败：打 IMPL_BUILD_TIMING_FAIL 并 exit 2（不写位流）
# =============================================================================

set _sd  [file normalize [file dirname [info script]]]
set _prj [file normalize [file join $_sd .. ..]]

set ::env(P13_ROOT)     $_prj
set ::env(P13_OUT_SUB)  p13_B2_A_rxdrop
set ::env(P12_SKIP_XSA) 1

# ★2026-11-27 第 4 次尝试：前一轮用 ExtraTimingOpt 得到 WNS=-0.069 / TIS=0.816
#   （失败端点数 17，全部集中在 mmcm_clkout0 = ui_clk 300 MHz 域，与本件新增的
#   gmii_rx_clk 域 ILA 不同域）。按 build_impl.tcl 头部写明的手法"换
#   P12_PLACE_DIRECTIVE 重掷"换成 ExtraPostPlacementOpt 再掷一次。
#   这是单变量重掷：RTL / ILA / 约束一个字都没改。
if {[info exists ::env(P13_PLACE_DIR)] && $::env(P13_PLACE_DIR) ne ""} {
    set ::env(P12_PLACE_DIRECTIVE) $::env(P13_PLACE_DIR)
} else {
    set ::env(P12_PLACE_DIRECTIVE) ExtraPostPlacementOpt
}
puts "B2_ISO_IMPL: place_directive=$::env(P12_PLACE_DIRECTIVE)"

puts "B2_ISO_IMPL: root=$_prj"
puts "B2_ISO_IMPL: outdir=$_prj/out/$::env(P13_OUT_SUB)"
puts "B2_ISO_IMPL: dcp=$_prj/scripts/pre_impl_debug.dcp"

source [file join $_sd .. build_impl.tcl]
