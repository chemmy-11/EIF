# N2: JTAG 跨地址连读的滞后形态标定 + 真值取样 (每地址: 先哑读一次, 再取值)
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
proc rd2 {a} {
    set v1 [mrd -value $a]
    set v2 [mrd -value $a]
    return [format "%08x/%08x" $v1 $v2]
}
puts "PAIRORDER: first/second of two back-to-back reads of the SAME address"
foreach a {0x44A0001C 0x44A00034 0x44A0000C 0x44A10000 0x44A10004 0x44A10018 0x44A10028 0x40600008 0x40600000} {
    puts [format "  %s -> %s" $a [rd2 $a]]
}
puts "SWEEP-ALT: A,B,A,B ... to expose one-behind shift"
set seq {0x44A0001C 0x44A00034 0x44A0001C 0x44A00034 0x40600008 0x44A10004 0x40600008 0x44A10004}
foreach a $seq { puts [format "  %s -> %08x" $a [mrd -value $a]] }
con
after 300
disconnect
exit
