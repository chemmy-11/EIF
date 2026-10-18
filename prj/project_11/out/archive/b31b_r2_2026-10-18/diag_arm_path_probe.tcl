open_checkpoint D:/FPGA/prj/project_11/scripts/post_route_ExtraTimingOpt.dcp
set p [get_timing_paths -delay_type max -max_paths 1 -sort_by slack]
puts "PATH_SLACK: [get_property SLACK $p]"
report_timing -of_objects $p -path_type full_clock_expanded -input_pins -file D:/FPGA/prj/project_11/out/path_dbg.rpt
puts "CELLS byte_valid_q: [get_cells -hier -quiet -filter {NAME =~ *byte_valid_q*}]"
puts "CELLS byte_q: [get_cells -hier -quiet -filter {NAME =~ *byte_q*}]"
puts "NETS wd_fetch: [get_nets -hier -quiet -filter {NAME =~ *wd_fetch*}]"
puts "PINS CE of wd_data_r 410: [get_pins -quiet {u_mem/u_bridge/g_wr_dma.wd_data_r_reg[410]/CE}]"
puts "PATH_DBG_DONE"
exit
