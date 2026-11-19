# =============================================================================
# build_variant_A_synth.tcl — 2026-11-19 板 A 参数组综合（默认组，与旧版等价）
#   用法：vivado -mode batch -source D:\FPGA\prj\project_13\scripts\build_variant_A_synth.tcl -notrace
# =============================================================================
set ::env(P13_BOARD) A
source D:/FPGA/prj/project_13/scripts/build_synth_only.tcl
