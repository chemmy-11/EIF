# J_B3-0: 烧 B3-0 位流（含 lat_w/lat_r + GET_LATENCY 0x05）+ 下载 j3_soft.elf
connect
puts "=== BURN B3-0 bitstream ==="
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
puts "J3_SOFT_B30_RUNNING"
exit
