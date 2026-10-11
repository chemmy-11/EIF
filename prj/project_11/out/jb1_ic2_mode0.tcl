# J_B1: JTAG 写 MODE=0 (回 SEQ, 恢复回显数据面) — 顺带验证 interconnect 版 JTAG 写通路
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
puts "=== JTAG WRITE MODE=0 (SEQ) ==="
mwr 0x44A00000 0
after 500
puts -nonewline "MODE_READBACK(dbg via STAT): "; puts [string trim [mrd 0x44A00018 1]]
puts -nonewline "STAT 2nd: "; puts [string trim [mrd 0x44A00018 1]]
con
puts "MODE0_DONE (CPU resumed)"
exit
