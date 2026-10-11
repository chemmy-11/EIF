# J_B1: SLOTMAP 独立验证 — 连读 6 次 @0x14, CPU 心跳稳态下
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
for {set i 1} {$i <= 6} {incr i} {
    puts -nonewline "SLOT#$i: "; puts [string trim [mrd 0x44A00014 1]]
}
puts -nonewline "WMWR#1 : "; puts [string trim [mrd 0x44A00008 1]]
puts -nonewline "WMWR#2 : "; puts [string trim [mrd 0x44A00008 1]]
con
puts "SLOTPROBE_DONE"
exit
