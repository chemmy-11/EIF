# M5: 读当前卡死现场 —— 寄存器 + PC 连续采样
connect
targets 3
after 300
stop
after 200
puts "PC_1 = [rrd pc]"
puts "R19  = [rrd r19]"
puts "DMASR  = [format %08x [mrd -value 0x44A10004]]"
puts "DMACR  = [format %08x [mrd -value 0x44A10000]]"
puts "DMAREQ = [format %08x [mrd -value 0x44A00034]]"
puts "WM_WR  = [format %08x [mrd -value 0x44A00008]]"
puts "WM_RD  = [format %08x [mrd -value 0x44A0000C]]"
con
after 500
stop
after 200
puts "PC_2 = [rrd pc]"
con
after 500
stop
after 200
puts "PC_3 = [rrd pc]"
disconnect
exit
