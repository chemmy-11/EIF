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
rd3 0x00003eec G_DMA_MODE
rd3 0x00003ef0 G_WR_LAST_TOGGLE
rd3 0x00003ef4 G_SERVE_CALL
rd3 0x00003ef8 G_WRREQ_SEEN
rd3 0x00003efc G_WRREQ_LAST
rd3 0x00003f00 G_ARM_CNT
rd3 0x44A00008 WM_WR
rd3 0x44A00040 WRREQ
rd3 0x44A10030 DMACR
rd3 0x44A10034 DMASR
rd3 0x44A10058 LENGTH
con
puts "DIAG7_DONE"
exit
