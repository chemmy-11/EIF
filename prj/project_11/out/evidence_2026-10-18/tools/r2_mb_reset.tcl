connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
puts "MB=$id"
targets $id
stop
after 200
puts "PC_BEFORE_RESET=[rrd pc]"
rst -processor
after 200
con
after 800
puts "PC_AFTER_RESET=[rrd pc]"
con
puts "RESET_DONE"
exit
