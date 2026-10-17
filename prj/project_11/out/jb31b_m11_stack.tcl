# M11: busy_ms 挂死机制判定 —— 读栈上的倒计数值 n (r19+4) 看它在不在递减
connect
set tg [targets]
set id ""
foreach line [split $tg "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze not found" }
targets $id
after 300
stop
after 200
set r19 [rrd r19]
puts "R19(帧基址) = $r19"
# n 在 r19+4 (busy_ms 栈帧: swi r19,r1,12 / addk r19,r1,0 / swi r5,r19,8 / ... n 在 r19+4)
set addr [expr {$r19 + 4}]
puts "N_ADDR = $addr"
puts "N_val_1 = [format %08x [mrd -value $addr]]"
con
after 200
stop
after 100
puts "N_val_2 = [format %08x [mrd -value $addr]]"
con
after 200
stop
after 100
puts "N_val_3 = [format %08x [mrd -value $addr]]"
# 也读 r19+8 (原 ms 参数)
set addr8 [expr {$r19 + 8}]
puts "R19+8(ms参数区) = [format %08x [mrd -value $addr8]]"
# 再看 r15 与 pc 确认还在原地
puts "PC_now = [rrd pc]"
disconnect
exit
