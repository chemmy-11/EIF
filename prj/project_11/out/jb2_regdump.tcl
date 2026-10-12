# J_B2: JTAG 对照读四寄存器 (C 打印 wr=01 rd=798 drop=?)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
for {set i 1} {$i <= 3} {incr i} {
    puts "TR$i ID:   [string trim [mrd 0x44A0001C 1]]"
    puts "TR$i WMWR: [string trim [mrd 0x44A00008 1]]"
    puts "TR$i WMRD: [string trim [mrd 0x44A0000C 1]]"
    puts "TR$i DROP: [string trim [mrd 0x44A00010 1]]"
    after 400
}
con
puts "REGDUMP_DONE"
exit
