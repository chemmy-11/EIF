# 鉴别: 写未映射地址(0x44B00000) 挂还是 DECERR?
# 当前位流已楔(CPU死+总线挂) —— 先重烧拿干净总线, 再测
connect
after 100
# 由 vivado 侧重烧后此处仅需写测试
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
puts "== W: UNMAPPED 0x44B00000 =="
if {[catch {mwr 0x44B00000 0x1} e]} { puts "W_UNMAPPED_STALL" } else { puts "W_UNMAPPED_OK" }
puts "== W: my slave MODE =="
if {[catch {mwr 0x44A00000 0x1} e]} { puts "W_LITE_STALL" } else { puts "W_LITE_OK" }
exit
