# J_B1 恢复清单步骤1: 烧 axi_interconnect 版 bit (SHA d14425f2..a114) + JTAG T1 基线
connect
puts "=== BURN: aurora_mem_bridge.bit (ic v2) ==="
fpga D:/FPGA/prj/project_11/out/aurora_mem_bridge.bit
after 2000
puts "=== TARGETS ==="
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
puts "MB_ID: $id"
targets $id
stop
after 500
puts "=== T1 BASELINE: ID expect 50314231 ==="
puts "ID   (0x44A0001C): [mrd 0x44A0001C 1]"
puts "STAT (0x44A00018): [mrd 0x44A00018 1]"
puts "WMWR (0x44A00008): [mrd 0x44A00008 1]"
puts "WMRD (0x44A0000C): [mrd 0x44A0000C 1]"
puts "BURN_BASELINE_DONE"
exit
