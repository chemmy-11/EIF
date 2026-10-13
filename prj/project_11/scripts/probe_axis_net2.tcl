# probe_axis_net2.tcl — 离线取证 v2: 扁平命名下的 AXIS 连接
open_checkpoint D:/FPGA/prj/project_11/scripts/post_route.dcp
puts "=== CELLS dma_sink ==="
puts [get_cells -quiet -hier -filter {NAME =~ *dma_sink*}]
puts "=== PINS tkeep (sink) ==="
set pins [get_pins -quiet -hier -filter {NAME =~ *u_dma_sink*s_tkeep*}]
puts "count=[llength $pins]"
foreach p [lrange $pins 0 6] {
    set net [get_nets -quiet -of_objects $p]
    set drv [get_pins -quiet -of_objects $net -filter {DIRECTION == OUT}]
    puts "$p <- $net  drv=$drv"
}
puts "=== PINS tkeep (dma out) ==="
set dp [get_pins -quiet -hier -filter {NAME =~ *axi_dma_0*M_AXIS_MM2S*tkeep*}]
puts "count=[llength $dp]"
foreach p [lrange $dp 0 4] {
    set net [get_nets -quiet -of_objects $p]
    set loads [get_pins -quiet -of_objects $net -filter {DIRECTION == IN}]
    puts "$p -> $net loads=[llength $loads]"
}
puts "PROBE2_DONE"
