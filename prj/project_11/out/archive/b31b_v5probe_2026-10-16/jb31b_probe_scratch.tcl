# scratch: 验证 pre_impl_debug.dcp 可续跑, 并确认目标网名与现有 ILA0 连接
open_checkpoint D:/FPGA/prj/project_11/scripts/pre_impl_debug.dcp
puts "CORES: [get_debug_cores]"
puts "PORTS: [get_debug_ports u_ila_0/*]"
set cur [get_nets -quiet -of_objects [get_debug_ports u_ila_0/probe0]]
puts "P0_WIDTH_CONN: [llength $cur]"
puts "P0_LAST3: [lrange $cur end-2 end]"
puts "mem_rd_data: [get_nets -quiet mem_rd_data*]"
puts "mem_rd_en: [get_nets -quiet mem_rd_en]"
puts "SCRATCH_DONE"
exit
