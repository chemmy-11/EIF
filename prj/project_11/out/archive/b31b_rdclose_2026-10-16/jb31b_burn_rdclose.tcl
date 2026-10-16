# 烧读侧收尾位流 (3aa600aa: 退役 + dma_tready 修正 + 发射探针) + 下载 ELF (f8175c32: 驻留服务)
connect
puts "=== BURN read-side closure bitstream ==="
fpga D:/FPGA/prj/project_11/out/aurora_mem_bridge.bit
after 3000
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
targets $id
stop
after 300
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
puts "J3_SOFT_RDCLOSE_RUNNING"
exit
