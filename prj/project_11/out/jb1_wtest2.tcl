# 修复版位流上的写测试: CPU 已楔死, 先 stop, 再 JTAG 写我的从机
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
puts "MB_ID: $id"
puts "PC: [rrd pc]"
stop
puts "== W: my MODE (fixed bitstream) =="
if {[catch {mwr 0x44A00000 0x1} e]} { puts "W_LITE_STALL" } else { puts "W_LITE_OK" }
after 200
puts "== R: STATUS =="
if {[catch {puts [mrd 0x44A00018 1]} e]} { puts "R_STALL" }
exit
