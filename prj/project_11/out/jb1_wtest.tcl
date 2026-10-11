# 写路径定位: axi_lite_regs(M01) 可写否?
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
puts "== write axi_lite_regs MODE(0x44A00000) =="
if {[catch {mwr 0x44A00000 0x1} emsg]} { puts "MWR_LITE_FAIL: $emsg" } else { puts "MWR_LITE_OK" }
after 200
puts "STAT after: [mrd 0x44A00018 1]"
con
exit
