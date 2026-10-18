connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
proc rd3 {addr label} {
    mrd -value $addr
    mrd -value $addr
    set v [mrd -value $addr]
    puts "$label=[format %08x $v]"
}
rd3 0x00003f3c G_DMA_MODE
rd3 0x00003f40 G_WR_LAST_TOGGLE
rd3 0x00003f44 G_SERVE_CALL
rd3 0x00003f48 G_WRREQ_SEEN
rd3 0x00003f4c G_WRREQ_LAST
rd3 0x00003f50 G_ARM_CNT
rd3 0x44A00008 WM_WR
rd3 0x44A0000C WM_RD
rd3 0x44A00040 WRREQ
rd3 0x44A00044 WRDBG
rd3 0x44A10034 DMASR
rd3 0x44A10058 LENGTH
con
puts "DIAG8_DONE"
exit
