# r3c_evt_dump.tcl -- dump g_evt[512] + g_evt_n from LMB (diag firmware 3251406F)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 200
puts "EVT_N_ADDR=0x00005d30"
puts "EVT_BASE=0x00005530"
set n [mrd -value 0x00005d30]
puts [format "EVT_N=%08x" $n]
for {set i 0} {$i < 512} {incr i} {
    set a [expr {0x00005530 + $i * 4}]
    set v [mrd -value $a]
    puts [format "E %03d %08x" $i $v]
}
con
puts "EVT_DUMP_DONE"
exit
