# J_B3-1 诊断: JTAG 直读 DMA Lite 寄存器 + 桥水位
# axi_dma MM2S 直通寄存器(0x44A10000): 00 DMACR 04 DMASR 18 SA 28 LENGTH
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
puts "DMACR:  [string trim [mrd 0x44A10000 1]]"
puts "DMASR:  [string trim [mrd 0x44A10004 1]]"
puts "SA:     [string trim [mrd 0x44A10018 1]]"
puts "LENGTH: [string trim [mrd 0x44A10028 1]]"
puts "WMWR:   [string trim [mrd 0x44A00008 1]]"
puts "WMRD:   [string trim [mrd 0x44A0000C 1]]"
con
puts "DMA_REG_DUMP_DONE"
exit
