# 重建 j3_soft 项目(平台 mbplat 复用) + 全量构建 —— 恢复被误删的项目注册
set P D:/FPGA/prj/project_11
cd $P/sw
setws $P/sw

# 0) 清掉残骸(目录还在但 workspace 已注销)
file delete -force $P/sw/j3_soft

# 1) 校验平台存在
if {![file exists $P/sw/mbplat/export/mbplat/mbplat.xpfm]} {
    error "platform mbplat not found"
}

# 2) 重新创建应用项目并构建
app create -name j3_soft -platform mbplat -domain {standalone_domain} \
    -template {Empty Application(C)}
file delete -force $P/sw/j3_soft/src/main.c
file copy -force $P/sw/src_j3/main.c $P/sw/j3_soft/src/main.c
app build -name j3_soft
puts "RECREATE_ELF: [file exists $P/sw/j3_soft/Debug/j3_soft.elf]"
