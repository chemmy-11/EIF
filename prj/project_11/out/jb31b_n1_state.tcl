# N1: 驻留固件静默时的系统状态快照 (不重建任何东西, 只读)
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
proc hexof {s} { return [string range $s [string last " " $s]+1 end] }
puts "PC   = [rrd pc]"
puts "R01  = [rrd r1]"
puts "R05  = [rrd r5]"
puts "R14  = [rrd r14]"
puts "R15  = [rrd r15]"
puts "R19  = [rrd r19]"
# 关键寄存器/状态
puts "REQ34   = [format %08x [mrd -value 0x44A00034]]"
puts "ID1C    = [format %08x [mrd -value 0x44A0001C]]"
puts "ENG0C   = [format %08x [mrd -value 0x44A0000C]]"
puts "DMACR   = [format %08x [mrd -value 0x44A10000]]"
puts "DMASR   = [format %08x [mrd -value 0x44A10004]]"
puts "DMASA   = [format %08x [mrd -value 0x44A10018]]"
puts "DMALEN  = [format %08x [mrd -value 0x44A10028]]"
puts "UART_ST = [format %08x [mrd -value 0x40600008]]"
puts "UART_RX = [format %08x [mrd -value 0x40600000]]"
# 栈顶 8 字 (R1 指向栈顶)
set sp [expr {0x[string range [rrd r1] [string last " " [rrd r1]]+1 end]}]
puts "SP = [format %08x $sp]"
for {set i 0} {$i < 8} {incr i} {
    set a [format "0x%08x" [expr {$sp + $i*4}]]
    puts "  [$a] = [format %08x [mrd -value $a]]"
}
con
after 300
disconnect
exit
