# J_B3-1: JTAG ground-truth readback of Lite regs (independent master, bypass MicroBlaze)
connect
set mbid 3
targets $mbid
after 300
puts "=== JTAG READBACK (x2 rounds each) ==="
foreach addr {0x44A00008 0x44A0000C 0x44A00010 0x44A0001C 0x44A00020 0x44A00024 0x44A00028 0x44A0002C 0x44A00030} {
    set v1 [mrd -value $addr]
    after 50
    set v2 [mrd -value $addr]
    puts [format "REG %s: %s  %s" $addr $v1 $v2]
}
disconnect
exit
