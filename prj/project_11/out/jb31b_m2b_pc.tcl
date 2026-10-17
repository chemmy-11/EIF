# M2b: 软核卡点定位 —— stop 后读 PC/SP, 并回读关键寄存器
connect
targets 3
after 300
stop
after 200
puts "PC = [rrd pc]"
puts "R1 = [rrd r1]"
puts "R2 = [rrd r2]"
puts "SP = [rrd r1]"
puts "MSR= [rrd msr]"
# 关键寄存器快照
puts "DMASR(0x04)  = [format %08x [mrd -value 0x44A10004]]"
puts "DMACR(0x00)  = [format %08x [mrd -value 0x44A10000]]"
puts "DMAREQ(0x34) = [format %08x [mrd -value 0x44A00034]]"
puts "WM_WR(0x08)  = [format %08x [mrd -value 0x44A00008]]"
puts "WM_RD(0x0C)  = [format %08x [mrd -value 0x44A0000C]]"
disconnect
exit
