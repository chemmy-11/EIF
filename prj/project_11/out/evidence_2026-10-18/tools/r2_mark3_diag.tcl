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
rd4 0x00003fa8 G_CODE
rd4 0x00003fac G_ADDR
rd4 0x00003fb0 G_LASTOK
con
puts "MARK3_DIAG_DONE"
exit
