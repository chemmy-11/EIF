# 烧 rdprobe 位流 (442ca75a, 含发射字节流探针) + 下载 j3_soft.elf ('F' 版)
connect
puts "=== BURN rdprobe bitstream ==="
fpga D:/FPGA/prj/project_11/out/aurora_mem_bridge_rdprobe.bit
after 3000
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
targets $id
stop
after 300
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
puts "J3_SOFT_RDPROBE_RUNNING"
exit
