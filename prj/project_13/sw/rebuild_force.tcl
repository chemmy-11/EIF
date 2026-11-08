# 强制全量重建: 清 app 的 Debug 全目录 + 重新 build (最朴素可靠的路径)
set P D:/FPGA/prj/project_11
cd $P/sw
setws $P/sw
file delete -force $P/sw/j3_soft/src/main.c
file copy -force $P/sw/src_j3/main.c $P/sw/j3_soft/src/main.c
file delete -force $P/sw/j3_soft/Debug
file delete -force $P/sw/j3_soft/_system
app build -name j3_soft
puts "REBUILD_ELF_EXISTS: [file exists $P/sw/j3_soft/Debug/j3_soft.elf]"
