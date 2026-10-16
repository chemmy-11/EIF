# scratch2: 验证在 pre_impl_debug.dcp 上给 u_ila_0 新建 probe1 并接入 9 根发射字节网
open_checkpoint D:/FPGA/prj/project_11/scripts/pre_impl_debug.dcp
set nets {}
lappend nets [get_nets -quiet dbg_mem_rden]
foreach i {0 1 2 3 4 5 6 7} { lappend nets [get_nets -quiet "mem_rd_data\[$i\]"] }
puts "TARGET_NETS: [llength $nets] -> $nets"
puts "--- create_debug_port 尝试 ---"
if {[catch {create_debug_port u_ila_0 probe} e]} { puts "TRY1_FAIL: $e" } else { puts "TRY1_OK" }
puts "PORTS_NOW: [get_debug_ports u_ila_0/*]"
set p [get_debug_ports u_ila_0/probe1]
if {$p eq ""} { puts "NO_PROBE1"; exit }
set_property port_width 9 $p
if {[catch {connect_debug_port u_ila_0/probe1 $nets} e2]} { puts "CONNECT_FAIL: $e2" } else { puts "CONNECT_OK" }
puts "P1_WIDTH: [get_property port_width $p]"
puts "VERIFY_NET: [get_nets -quiet -of_objects $p]"
puts "SCRATCH2_DONE"
exit
