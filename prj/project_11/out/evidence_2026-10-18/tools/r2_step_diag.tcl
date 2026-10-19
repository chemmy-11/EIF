connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 200
proc rd {addr label} {
    mrd -value $addr
    mrd -value $addr
    set v [mrd -value $addr]
    puts "$label=[format %08x $v]"
}
puts "PC=[rrd pc]"
rd 0x450c GDMA_MODE
rd 0x4510 WA_S2CR
rd 0x4514 WA_S2SR
rd 0x4518 WA_S2LEN
rd 0x451c WA_S2SR2
rd 0x4520 WA_S2LEN2
rd 0x4524 WA_WREQ
rd 0x4528 WA_WDBG
rd 0x452c WA_CNT
rd 0x4530 WA_DONE
rd 0x4534 G_STEP
con
puts "STEP_DIAG_DONE"
exit
