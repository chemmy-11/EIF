# probe_axis_net4.tcl — 校准查询: tdata vs tkeep vs uart_txd 的网络归属
open_checkpoint D:/FPGA/prj/project_11/scripts/post_route.dcp
proc show {pin} {
    set p [get_pins -quiet $pin]
    if {$p eq ""} { puts "$pin : NO PIN"; return }
    set n [get_nets -quiet -of_objects $p]
    puts "$pin : pin=$p net=$n"
}
puts "=== CALIBRATION ==="
show "u_mb_ctrl/uart_txd"
show "u_mb_ctrl/M_AXIS_MM2S_0_tdata[511]"
show "u_mb_ctrl/M_AXIS_MM2S_0_tdata[31]"
show "u_mb_ctrl/M_AXIS_MM2S_0_tlast"
show "u_mb_ctrl/M_AXIS_MM2S_0_tvalid"
show "u_mb_ctrl/M_AXIS_MM2S_0_tready"
show "u_mb_ctrl/M_AXIS_MM2S_0_tkeep[63]"
show "u_mb_ctrl/M_AXIS_MM2S_0_tkeep[0]"
puts "=== NET NAME GREP ==="
puts "tdata nets: [get_nets -quiet -hier -filter {NAME =~ *dma_tdata*}]"
puts "tkeep nets: [get_nets -quiet -hier -filter {NAME =~ *dma_tkeep*}]"
puts "tlast nets: [get_nets -quiet -hier -filter {NAME =~ *dma_tlast*}]"
puts "valid nets: [get_nets -quiet -hier -filter {NAME =~ *dma_tvalid*}]"
puts "PROBE4_DONE"
