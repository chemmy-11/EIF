# J_B1 ②: JTAG 下载 ELF 并运行 (v2: 原始 targets 输出 + 稳健选择)
connect
puts "=== TARGETS RAW ==="
puts [targets]
puts "=== END RAW ==="
# 选 MicroBlaze CPU（注意区分 "MicroBlaze Debug Module"=MDM 与 "MicroBlaze #0"=CPU）
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
puts "MB_ID: $id"
targets $id
stop
dow D:/FPGA/prj/project_11/sw/hello_regs/Debug/hello_regs.elf
after 500
con
after 1500
puts "=== REG READBACK (AXI-Lite over JTAG) ==="
puts "ID   (0x44A0001C): [mrd 0x44A0001C 1]"
puts "STAT (0x44A00018): [mrd 0x44A00018 1]"
puts "WMWR (0x44A00008): [mrd 0x44A00008 1]"
puts "SLOTMAP(0x44A00014): [mrd 0x44A00014 1]"
puts "ELF_RUNNING"
exit
