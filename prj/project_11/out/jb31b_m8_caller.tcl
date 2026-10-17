# M8: 挂点身份判定 —— PC + R15(返回地址=调用点) + R5(busy_ms 参数) 
connect
targets 3
after 300
stop
after 200
puts "PC  = [rrd pc]"
puts "R15 = [rrd r15]"
puts "R5  = [rrd r5]"
puts "R1  = [rrd r1]"
puts "R19 = [rrd r19]"
puts "DMAREQ = [format %08x [mrd -value 0x44A00034]]"
con
after 400
stop
after 200
puts "PC_2  = [rrd pc]"
puts "R15_2 = [rrd r15]"
puts "R5_2  = [rrd r5]"
disconnect
exit
