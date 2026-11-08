# rebuild_j3.tcl — 仅重编译现有 j3_soft 工程 (main.c 已更新)
set P D:/FPGA/prj/project_11
cd $P/sw
setws $P/sw
file delete -force $P/sw/j3_soft/src/main.c
file copy -force $P/sw/src_j3/main.c $P/sw/j3_soft/src/main.c
app build -name j3_soft
puts "J3_DONE: $P/sw/j3_soft/Debug/j3_soft.elf"
