# 清 workspace 残留注册 -> 重建 j3_soft 项目
set P D:/FPGA/prj/project_11
cd $P/sw

# 1) 清 .metadata 里的项目注册(残留)
file delete -force $P/sw/.metadata/.plugins/org.eclipse.core.resources/.projects/j3_soft
file delete -force $P/sw/.metadata/.plugins/org.eclipse.core.resources/.projects/j3_soft_system
# 2) 清目录残骸
file delete -force $P/sw/j3_soft
file delete -force $P/sw/j3_soft_system

setws $P/sw
app create -name j3_soft -platform mbplat -domain {standalone_domain} \
    -template {Empty Application(C)}
file delete -force $P/sw/j3_soft/src/main.c
file copy -force $P/sw/src_j3/main.c $P/sw/j3_soft/src/main.c
app build -name j3_soft
puts "RECREATE2_ELF: [file exists $P/sw/j3_soft/Debug/j3_soft.elf]"
