# probe_axis_net3.tcl — 定向验证: keep/bytes 路径是否被折叠 + tkeep 网络驱动
open_checkpoint D:/FPGA/prj/project_11/scripts/post_route.dcp
puts "=== KEEP/BYTES cells ==="
puts [get_cells -quiet -hier -filter {NAME =~ *dma_sink*keep*}]
puts [get_cells -quiet -hier -filter {NAME =~ *dma_sink*bytes*}]
puts "=== dma_tkeep nets ==="
set nt [get_nets -quiet -hier -filter {NAME =~ *dma_tkeep*}]
puts "net count=[llength $nt]"
foreach n [lrange $nt 0 3] {
    set drv [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
    set ld  [get_pins -quiet -of_objects $n -filter {DIRECTION == IN}]
    puts "NET $n"
    puts "   drv: $drv"
    puts "   loads: [llength $ld]  first: [lrange $ld 0 2]"
}
puts "=== u_mb_ctrl M_AXIS port pins ==="
set cp [get_pins -quiet u_mb_ctrl/M_AXIS_MM2S_0_tkeep*]
puts "count=[llength $cp]"
foreach p [lrange $cp 0 3] {
    set net [get_nets -quiet -of_objects $p]
    puts "$p -> $net"
}
puts "PROBE3_DONE"
