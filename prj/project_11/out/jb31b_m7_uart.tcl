# M7: 直接读 UARTLite 状态寄存器(RX_VALID=bit0) —— 判定 'I' 字节是否到达
connect
targets 3
after 200
puts "UART_ST(0x08) = [format %08x [mrd -value 0x40600008]]"
puts "UART_RX(0x00) = [format %08x [mrd -value 0x40600000]]"
# 往 UART TX 写一个字节(0x55)看 TX 通路(软核侧另一头)是否还活着
mwr 0x40600004 0x55
after 100
puts "AFTER_TX UART_ST = [format %08x [mrd -value 0x40600008]]"
disconnect
exit
