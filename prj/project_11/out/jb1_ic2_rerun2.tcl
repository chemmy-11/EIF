# J_B1 恢复: 诊断版 ELF 复跑 (stop -> PC=0 -> con)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
rwr pc 0x0
after 200
con
puts "DIAGRUN_STARTED"
exit
