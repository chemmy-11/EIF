# r3c_lmb_dump.tcl -- one-off rehearsal: dump LMB 0x44E0-0x4560 to check g_wa_* values
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 200
puts "PC=[rrd pc]"
proc rd {addr} {
    mrd -value $addr
    mrd -value $addr
    set a [mrd -value $addr]
    set b [mrd -value $addr]
    set c [mrd -value $addr]
    return "$a $b $c"
}
foreach a {0x000044f0 0x000044f4 0x000044f8 0x000044fc 0x00004500 0x00004504 0x00004508 0x0000450c 0x00004510 0x00004514 0x00004518 0x0000451c 0x00004520 0x00004524 0x00004528 0x0000452c 0x00004530 0x00004534 0x00004538 0x0000453c 0x00004540 0x00004544} {
    puts [format "LMB %08x = %s" $a [rd $a]]
}
con
puts "LMB_DUMP_DONE"
exit
