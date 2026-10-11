# J_B1 恢复: 读陈旧模式判别实验 (ic v2, CPU 停, idle 态)
# 判别: 首笔粘滞 / 落后一笔 / 间歇 — 用非零值寄存器(SLOTMAP=01000000, ID=50314231)当标记
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
targets $id
stop
after 300
puts "A1 ID   1C: [lindex [mrd 0x44A0001C 1] 1]"
puts "B1 STAT 18: [lindex [mrd 0x44A00018 1] 1]"
puts "B2 STAT 18: [lindex [mrd 0x44A00018 1] 1]"
puts "B3 STAT 18: [lindex [mrd 0x44A00018 1] 1]"
puts "C1 WMWR 08: [lindex [mrd 0x44A00008 1] 1]"
puts "C2 WMWR 08: [lindex [mrd 0x44A00008 1] 1]"
puts "D1 SLOT 14: [lindex [mrd 0x44A00014 1] 1]"
puts "E1 RD   0C: [lindex [mrd 0x44A0000C 1] 1]"
puts "F1 ID   1C: [lindex [mrd 0x44A0001C 1] 1]"
puts "G1 STAT 18: [lindex [mrd 0x44A00018 1] 1]"
puts "PATTERN_DONE"
exit
