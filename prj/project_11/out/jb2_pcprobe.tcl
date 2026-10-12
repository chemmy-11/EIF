# J_B2 诊断: CPU PC 采样 (卡死点定位)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
puts "PC1: [rrd pc]"
after 500
puts "PC2: [rrd pc]"
con
puts "PCPROBE_DONE"
exit
