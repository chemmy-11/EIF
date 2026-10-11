# 隔离实验 v3(同一次干净总线, UART 写已通, 现在写我的从机)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
puts "== R: my ID =="
if {[catch {puts [mrd 0x44A0001C 1]} e]} { puts "R_ID_STALL" }
puts "== W: my MODE =="
if {[catch {mwr 0x44A00000 0x1} e]} { puts "W_LITE_STALL" } else { puts "W_LITE_OK" }
exit
