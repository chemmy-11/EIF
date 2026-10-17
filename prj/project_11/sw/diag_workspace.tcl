# 诊断 app build 为什么静默无产物: 打开 workspace 看项目状态
set P D:/FPGA/prj/project_11
cd $P/sw
setws $P/sw
puts "PROJECTS: [projects]"
set projs [projects]
foreach pr $projs {
    puts "  proj: $pr  type: [get_property app.type $pr]  platform: [get_property platform $pr]  active: [get_property active.build.config $pr]"
}
# 看是不是 app 项目还在但构建配置丢了
catch { puts "J3 platform: [get_property platform [lindex $projs 0]]" } e
puts "ERR: $e"
