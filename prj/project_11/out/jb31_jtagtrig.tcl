# J_B3-1 诊断2: JTAG 手动编程 DMA 读槽 0 的地址(0x00100000) -> 观察 sink
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
# 复位通道
mwr 0x44A10000 0x4
after 50
mwr 0x44A10000 0x1
after 50
# SA = 槽 0 基址, LENGTH=64 触发
mwr 0x44A10018 0x00100000
after 10
mwr 0x44A10028 0x40
after 1000
puts "DMASR_after: [string trim [mrd 0x44A10004 1]]"
puts "SINK_Q0: [string trim [mrd 0x44A00028 1]]"
puts "SINK_Q1: [string trim [mrd 0x44A0002C 1]]"
puts "SINK_Q2: [string trim [mrd 0x44A00030 1]]"
con
puts "JTAG_DMA_TRIG_DONE"
exit
