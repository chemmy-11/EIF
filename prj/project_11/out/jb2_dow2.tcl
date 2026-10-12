# J_B2: 下载加固版 j3_soft.elf (3fc7a634)
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
stop
after 300
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
puts "J3_SOFT_V2_RUNNING"
exit
