# 隔离实验 v2(重烧后干净总线): 第一笔写 -> UARTLite(完整 AXI-Lite IP)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
puts "== R0: UART STAT (sanity read) =="
if {[catch {puts [mrd 0x40600008 1]} e]} { puts "R0_STALL" }
puts "== W1: UART TX (Xilinx IP first write) =="
if {[catch {mwr 0x40600004 0x41} e]} { puts "W1_UART_STALL" } else { puts "W1_UART_OK" }
puts "== R1: UART STAT after =="
if {[catch {puts [mrd 0x40600008 1]} e]} { puts "R1_STALL" }
exit
