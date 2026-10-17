# M11b: busy_ms 挂死机制判定 —— 读栈上的 n (r19+4) 连续三次看是否递减
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
# rrd 返回带前缀 "r19: 00003bdc" —— 提取纯十六进制
set raw19 [rrd r19]
set r19 0x[string range $raw19 [string last " " $raw19]+1 end]
puts "R19 = $r19"
set addr [format "0x%08x" [expr {$r19 + 4}]]
puts "N_ADDR = $addr"
puts "N_val_1 = [format %08x [mrd -value $addr]]"
con
after 300
stop
after 100
puts "N_val_2 = [format %08x [mrd -value $addr]]"
con
after 300
stop
after 100
puts "N_val_3 = [format %08x [mrd -value $addr]]"
puts "PC_now = [rrd pc]"
disconnect
exit
