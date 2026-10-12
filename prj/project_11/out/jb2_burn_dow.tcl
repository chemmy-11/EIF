# J_B2: 烧录 interconnect 位流 (d14425f2) + 下载 j3_soft.elf + 运行
connect
puts "=== BURN d14425f2 ==="
fpga D:/FPGA/prj/project_11/out/aurora_mem_bridge.bit
after 3000
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
targets $id
stop
after 300
puts "PC_BEFORE: [rrd pc]"
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
puts "J3_SOFT_RUNNING"
exit
