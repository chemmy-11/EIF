# =============================================================================
# build_variant_B_synth_lean.tcl — 2026-11-19 时序回退版（B 参数组）
#   与 build_variant_B_synth.tcl 差异：额外置 env R3C_SKIP_ILA4=1
#   （跳掉 u_ila_4 = lite AXI 调试核 37bit@1024，为新增 u_ila_7 让出时序余量）
#   背景：首版 ILA7 53bit 使 route 后 WNS -0.214，impl 时序门拒绝写位流。
# =============================================================================
set ::env(P13_BOARD) B
set ::env(R3C_SKIP_ILA4) 1
source D:/FPGA/prj/project_13/scripts/build_synth_only.tcl
