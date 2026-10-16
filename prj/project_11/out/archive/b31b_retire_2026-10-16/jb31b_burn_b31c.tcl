# 烧退役版位流 (7064368d, 桥②读引擎已退役) + 下载 B3-1c ELF (d73c5a97, DMA 服务默认开)
connect
puts "=== BURN B3-1c retire bitstream ==="
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
puts "J3_SOFT_B31C_RETIRE_RUNNING"
exit
