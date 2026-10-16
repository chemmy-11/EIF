# 恢复绿配置: 烧 v5-RTL 位流 (708f15a4, 归档) + 下载 v5-RTL 配对 ELF (c13a54f5, 归档)
connect
puts "=== RESTORE v5-RTL green config ==="
fpga D:/FPGA/prj/project_11/out/archive/b31b_v5rtl_2026-10-16/aurora_mem_bridge.bit
after 3000
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
targets $id
stop
after 300
dow D:/FPGA/prj/project_11/out/archive/b31b_v5rtl_2026-10-16/j3_soft_v5rtl.elf
after 500
con
puts "J3_SOFT_V5RTL_RESTORED"
exit
