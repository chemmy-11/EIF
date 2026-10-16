# J_B3-1b v3 板场次（2026-10-16）：烧 v3 位流 (a432addd) + 下载 j3_soft.elf (0f4f0bd3)
connect
puts "=== BURN B3-1b v3 bitstream (a432addd) ==="
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
puts "J3_SOFT_B31B_V3_RUNNING"
exit
