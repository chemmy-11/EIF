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
rd 0x4450 WA_S2CR
rd 0x4454 WA_S2SR
rd 0x4458 WA_S2LEN
rd 0x445c WA_S2SR2
rd 0x4460 WA_S2LEN2
rd 0x4464 WA_WREQ
rd 0x4468 WA_WDBG
rd 0x446c WA_CNT
rd 0x4470 WA_DONE
con
puts "WA_DIAG_DONE"
exit
