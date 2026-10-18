connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
for {set i 1} {$i <= 6} {incr i} {
    puts "R$i=[format %08x [mrd -value 0x44A0001C]]"
}
puts "---mem---"
for {set i 1} {$i <= 4} {incr i} {
    puts "M$i=[format %08x [mrd -value 0x00000000]]"
}
con
puts "CAL_DONE"
exit
