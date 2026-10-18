connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
puts "MB=$id"
targets $id
stop
after 300
proc rd3 {addr label} {
    mrd -value $addr
    mrd -value $addr
    set v [mrd -value $addr]
    puts "$label=[format %08x $v]"
}
puts "PC1=[rrd pc]"
rd3 0x00003f3c G_DMA_MODE
rd3 0x00003f40 G_WR_LAST_TOGGLE
rd3 0x00003f44 G_SERVE_CALL
rd3 0x00003f48 G_WRREQ_SEEN
rd3 0x00003f4c G_WRREQ_LAST
rd3 0x00003f50 G_ARM_CNT
puts "PC2=[rrd pc]"
con
after 300
stop
puts "PC3=[rrd pc]"
con
puts "DIAG9_DONE"
exit
