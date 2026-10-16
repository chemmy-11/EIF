# 诊断: MB 状态 + Lite 关键寄存器 (ID / wm_wr / engine)
connect
puts "=== TARGETS ==="
puts [targets]
targets 3
after 300
puts "ID(0x1C)   = [format %08x [mrd -value 0x44A0001C]]"
puts "WM_WR(0x08)= [format %08x [mrd -value 0x44A00008]]"
puts "WM_RD(0x0C)= [format %08x [mrd -value 0x44A0000C]]"
puts "STAT(0x18) = [format %08x [mrd -value 0x44A00018]]"
puts "DMAREQ(0x34)=[format %08x [mrd -value 0x44A00034]]"
disconnect
exit
