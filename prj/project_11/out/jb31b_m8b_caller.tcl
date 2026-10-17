# M8: 挂点身份判定 —— PC + R15(busy_ms 返回地址=调用点) + R5(busy_ms 参数) + R14(二级返回)
connect
set tg [targets]
puts "TARGETS: $tg"
# 找 MicroBlaze 目标号
set id ""
foreach line [split $tg "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze not found" }
puts "MB_ID = $id"
targets $id
after 300
stop
after 200
puts "PC  = [rrd pc]"
puts "R1  = [rrd r1]"
puts "R5  = [rrd r5]"
puts "R14 = [rrd r14]"
puts "R15 = [rrd r15]"
puts "R18 = [rrd r18]"
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
