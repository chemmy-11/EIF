# =============================================================================
# build_variant_B_synth.tcl — 2026-11-19 板 B 参数组综合
#   机制：设置 env P13_BOARD=B -> build_synth_only.tcl 里 verilog_define BOARD_B
#        -> rtl/aurora_mem_bridge.v 的 `ifdef BOARD_B 参数组生效
#   产物：scripts/pre_impl_debug.dcp（随后走 build_impl.tcl）
#   用法：vivado -mode batch -source D:\FPGA\prj\project_13\scripts\build_variant_B_synth.tcl -notrace
# =============================================================================
set ::env(P13_BOARD) B
source D:/FPGA/prj/project_13/scripts/build_synth_only.tcl
