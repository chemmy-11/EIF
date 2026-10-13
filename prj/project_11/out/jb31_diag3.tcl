# J_B3-1 诊断3: JTAG 触发 LENGTH=4096 整槽读, 观察是否仍 tkeep=0
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
mwr 0x44A10000 0x4
after 50
mwr 0x44A10000 0x1
after 50
mwr 0x44A10018 0x00116000
after 10
mwr 0x44A10028 0x1000
after 2000
puts "DMASR: [string trim [mrd 0x44A10004 1]]"
# 连读 Q0 六次 (坑#39: 首读陈旧)
for {set i 1} {$i <= 6} {incr i} {
    puts "Q0#$i: [string trim [mrd 0x44A00028 1]]"
}
puts "Q1: [string trim [mrd 0x44A0002C 1]]"
puts "Q1b: [string trim [mrd 0x44A0002C 1]]"
puts "Q2: [string trim [mrd 0x44A00030 1]]"
con
puts "DIAG3_DONE"
exit
