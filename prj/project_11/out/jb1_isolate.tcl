# 隔离实验(在重烧后的干净总线上):
#   第一笔写 -> axi_lite_regs(0x44A00000, 我方从机)
#   第二笔写 -> UARTLite TX(0x40600004, Xilinx IP)
# 谁挂谁说清楚。
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
puts "== W1: axi_lite_regs MODE =="
if {[catch {mwr 0x44A00000 0x1} e]} { puts "W1_LITE_STALL" } else { puts "W1_LITE_OK" }
puts "== R: STATUS =="
if {[catch {puts [mrd 0x44A00018 1]} e]} { puts "R_STAT_STALL" }
puts "== W2: UART TX =="
if {[catch {mwr 0x40600004 0x55} e]} { puts "W2_UART_STALL" } else { puts "W2_UART_OK" }
exit
