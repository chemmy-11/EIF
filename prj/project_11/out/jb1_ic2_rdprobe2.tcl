# J_B1 恢复: 读通道探针2 — 常量寄存器连读 8 次 + 计数器连读 (原始输出)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
for {set i 1} {$i <= 8} {incr i} {
    puts -nonewline "ID#$i  : "; puts [string trim [mrd 0x44A0001C 1]]
}
for {set i 1} {$i <= 6} {incr i} {
    puts -nonewline "WMWR#$i: "; puts [string trim [mrd 0x44A00008 1]]
}
for {set i 1} {$i <= 4} {incr i} {
    puts -nonewline "WMRD#$i: "; puts [string trim [mrd 0x44A0000C 1]]
}
for {set i 1} {$i <= 3} {incr i} {
    puts -nonewline "SLOT#$i: "; puts [string trim [mrd 0x44A00014 1]]
}
puts "PROBE2_DONE"
exit
