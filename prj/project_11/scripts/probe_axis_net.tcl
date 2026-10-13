# probe_axis_net.tcl — 离线取证: M_AXIS_MM2S -> dma_sink 的实际网表连接
open_checkpoint D:/FPGA/prj/project_11/scripts/post_route.dcp
puts "=== CHECKPOINT: post_route.dcp ==="
# 1) dma_sink 的输入引脚各由谁驱动
foreach pn {s_tdata s_tkeep s_tlast s_tvalid} {
    set pins [get_pins -quiet -hier -filter "NAME =~ *u_dma_sink/$pn*"]
    puts "--- u_dma_sink/$pn : [llength $pins] pins"
    set npin 0
    foreach p $pins {
        set net [get_nets -quiet -of_objects $p]
        set drv [get_pins -quiet -of_objects $net -filter {DIRECTION == OUT}]
        if {$npin < 3} { puts "    $p  <- net=$net  drv=$drv" }
        incr npin
    }
}
# 2) axi_dma 的 M_AXIS 输出引脚
set dpins [get_pins -quiet -hier -filter "NAME =~ *axi_dma_0*M_AXIS_MM2S*tkeep*"]
puts "--- axi_dma M_AXIS tkeep pins = [llength $dpins]"
foreach p [lrange $dpins 0 2] {
    set net [get_nets -quiet -of_objects $p]
    set loads [get_pins -quiet -of_objects $net -filter {DIRECTION == IN}]
    puts "    $p -> net=$net  loads=[llength $loads]"
}
puts "PROBE_DONE"
