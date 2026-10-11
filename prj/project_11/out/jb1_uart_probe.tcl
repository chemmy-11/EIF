# 直接读 UARTLite 寄存器 + 实验: 写 TX 前后状态变化
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
puts "RX   (0x40600000): [mrd 0x40600000 1]"
puts "TX   (0x40600004): [mrd 0x40600004 1]"
puts "STAT (0x40600008): [mrd 0x40600008 1]"
mwr 0x40600004 0x55
after 100
puts "STAT-after-TX(0x55): [mrd 0x40600008 1]"
mwr 0x40600004 0xAA
mwr 0x40600004 0x33
after 100
puts "STAT-after-TXx2: [mrd 0x40600008 1]"
after 300
puts "STAT-after-drain: [mrd 0x40600008 1]"
con
exit
