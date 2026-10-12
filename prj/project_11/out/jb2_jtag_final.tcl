# J_B2 收尾对照: JTAG 直读 wr/rd (对账轮后快照语义)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
puts "WMWR: [string trim [mrd 0x44A00008 1]]"
puts "WMRD: [string trim [mrd 0x44A0000C 1]]"
puts "DROP: [string trim [mrd 0x44A00010 1]]"
puts "SLOTMAP: [string trim [mrd 0x44A00014 1]]"
con
puts "JTAG_FINAL_DONE"
exit
