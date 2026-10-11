# J_B1 恢复: PC 归零重跑自检 (配合串口监听)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
puts "PC_BEFORE: [rrd pc]"
rwr pc 0x0
after 200
con
puts "RERUN_STARTED"
exit
