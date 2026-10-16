# 受控取证: 请求/ARL/EMIT 寄存器 + 试探 DDR 槽区是否可从 MicroBlaze 读
connect
puts "=== TARGETS ==="
puts [targets]
targets 3
after 300
puts "REQ =0x34  [format %08x [mrd -value 0x44A00034]]"
puts "ARL =0x38  [format %08x [mrd -value 0x44A00038]]"
puts "EMIT=0x3C  [format %08x [mrd -value 0x44A0003C]]"
set sa 0x00198000
puts "--- slot(152) 区 SA-16 .. SA+64 ---"
for {set i 0} {$i < 21} {incr i} {
    set a [expr {$sa - 16 + $i*4}]
    puts "[format %08x $a] : [format %08x [mrd -value $a]]"
}
disconnect
exit
