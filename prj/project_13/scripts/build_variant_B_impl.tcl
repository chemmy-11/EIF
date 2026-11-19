# =============================================================================
# build_variant_B_impl.tcl — 2026-11-19 板 B 参数组实现
#   前置：build_variant_B_synth.tcl 已产出 scripts/pre_impl_debug.dcp（BOARD_B）
#   配方：opt -> place(ExtraTimingOpt) -> phys_opt AggressiveExplore
#        -> route NoTimingRelaxation -> phys_opt AggressiveExplore -> phys_opt Explore
#   产物：out/aurora_mem_bridge.bit, scripts/probes.ltx, scripts/post_route.dcp
# =============================================================================
set ::env(P13_BOARD) B
source D:/FPGA/prj/project_13/scripts/build_impl.tcl
