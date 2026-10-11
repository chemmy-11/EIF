# rebuild_sw.tcl — 仅重编译现有 hello_regs 工程 (main.c 已更新)
set P D:/FPGA/prj/project_11
cd $P/sw
setws $P/sw
file delete -force $P/sw/hello_regs/src/main.c
file copy -force $P/sw/src/main.c $P/sw/hello_regs/src/main.c
app build -name hello_regs
puts "SW_DONE: $P/sw/hello_regs/Debug/hello_regs.elf"
