# rebuild_f.tcl — B3-1b v4: 重编 j3_soft (main.c 加 'F' DMA 流起点取证命令)
set P D:/FPGA/prj/project_11
cd $P/sw
setws $P/sw
file delete -force $P/sw/j3_soft/src/main.c
file copy -force $P/sw/src_j3/main.c $P/sw/j3_soft/src/main.c
app build -name j3_soft
puts "F_ELF_DONE: $P/sw/j3_soft/Debug/j3_soft.elf"
