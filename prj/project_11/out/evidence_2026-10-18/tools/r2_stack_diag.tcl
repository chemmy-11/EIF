connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 200
puts "PC=[rrd pc]"
puts "R19=[rrd r19]"
puts "R15=[rrd r15]"
puts "R1=[rrd r1]"
set r19v [rrd -value r19]
puts "R19_VAL=[format %08x $r19v]"
# dread 栈帧: [r19+12] = 传入的寄存器指针
set p [expr {$r19v + 12}]
mrd -value $p
set v [mrd -value $p]
puts "ARG_PTR=[format %08x $v]"
puts "R3=[rrd r3]"
con
puts "STACKDIAG_DONE"
exit
