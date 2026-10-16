# 烧 v5-RTL 位流 (708f15a4, DROP_BYTES=0) + 下载 v5-RTL 配对 ELF ('E' 用基址对齐 + LEN=len)
connect
puts "=== BURN v5-RTL bitstream (DROP_BYTES=0) ==="
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
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
puts "J3_SOFT_V5RTL_RUNNING"
exit
