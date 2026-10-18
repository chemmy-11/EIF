connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 200
proc rd4 {addr label} {
    mrd -value $addr
    mrd -value $addr
    mrd -value $addr
    set v [mrd -value $addr]
    puts "$label=[format %08x $v]"
}
puts "PC=[rrd pc]"
rd4 0x00003ff8 G_CODE
rd4 0x00003ffc G_ADDR
rd4 0x00004000 G_LASTOK
con
puts "MARK_DIAG_DONE"
exit
