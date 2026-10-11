# J_B1 恢复步骤3: 下载 hello_regs.elf 并运行 (ic v2 验收)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
puts "PC_BEFORE: [rrd pc]"
dow D:/FPGA/prj/project_11/sw/hello_regs/Debug/hello_regs.elf
after 500
con
puts "ELF_RUNNING"
exit
