# J_B1 恢复: 净室复跑 — 重烧同 bit(复位全部 fabric 状态) + 下载新 ELF + 运行
connect
puts "=== REBURN: aurora_mem_bridge.bit (d14425f2) ==="
fpga D:/FPGA/prj/project_11/out/aurora_mem_bridge.bit
after 2000
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
targets $id
stop
after 300
dow D:/FPGA/prj/project_11/sw/hello_regs/Debug/hello_regs.elf
after 500
con
puts "CLEANRUN_STARTED"
exit
