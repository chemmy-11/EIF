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
# firmware globals (LMB, 0x0-0xFFFF)
rd3 0x00003e74 G_DMA_MODE
rd3 0x00003e70 G_DMA_SERVICE
rd3 0x00003e78 G_WR_LAST_TOGGLE
# lite regs
rd3 0x44A00008 WM_WR
rd3 0x44A0000C WM_RD
rd3 0x44A00040 WRREQ
rd3 0x44A00044 WRDBG
rd3 0x44A00034 REQ34
# S2MM registers
rd3 0x44A10030 DMACR
rd3 0x44A10034 DMASR
rd3 0x44A10048 SA
rd3 0x44A10058 LENGTH
con
puts "DIAG5_DONE"
exit
