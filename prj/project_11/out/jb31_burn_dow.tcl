# J_B3-1: 烧 DMA 集成位流 (ae9d24a2) + 下载 j3_soft.elf (92e2ab52)
connect
puts "=== BURN B3-1 DMA bitstream ==="
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
puts "J3_SOFT_B31_RUNNING"
exit
