# =============================================================================
# build_j3.tcl — prj11 B2: j3_soft 应用首建 (platform 复用 mbplat)
#   源: sw/src_j3/main.c   产物: sw/j3_soft/Debug/j3_soft.elf
# 用法: D:\Xilinx\Vitis\2023.1\bin\xsct.bat D:\FPGA\prj\project_11\sw\build_j3.tcl
# 改源后重编用 rebuild_j3.tcl (app create 不幂等, 坑 #41)
# =============================================================================
set P D:/FPGA/prj/project_11

if {![file exists $P/out/mb_ctrl.xsa]} {
    error "XSA not found: $P/out/mb_ctrl.xsa"
}
if {![file exists $P/sw/mbplat/export/mbplat/mbplat.xpfm]} {
    error "platform mbplat not found (run build_sw.tcl first)"
}

cd $P/sw
setws $P/sw

app create -name j3_soft -platform mbplat -domain {standalone_domain} \
    -template {Empty Application(C)}
file delete -force $P/sw/j3_soft/src/main.c
file copy -force $P/sw/src_j3/main.c $P/sw/j3_soft/src/main.c
app build -name j3_soft
puts "J3_DONE: $P/sw/j3_soft/Debug/j3_soft.elf"
