# J_B1 诊断: CPU PC 采样 + 寄存器复读
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
puts "MB_ID: $id"
puts "PC1: [rrd pc]"
after 1200
puts "PC2: [rrd pc]"
puts "STAT_A: [mrd 0x44A00018 1]"
after 2100
puts "STAT_B: [mrd 0x44A00018 1]"
puts "MSR: [rrd msr]"
exit
