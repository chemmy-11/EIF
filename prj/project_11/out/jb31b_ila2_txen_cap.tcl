# E 轮发射判定: 武装 ILA2 于 dbg_stack_txen, 跑 E 轮(bat 包装), 上传捕获
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE {D:/FPGA/prj/project_11/scripts/probes.ltx} $dev
refresh_hw_device $dev
after 2000

set ila [get_hw_ilas hw_ila_2]
puts "ILA2 = $ila"
catch {reset_hw_ila $ila} e0
puts "RESET_NOTE: $e0"
after 500
set p [get_hw_probes -quiet -of_objects $ila dbg_stack_txen]
puts "probe = $p"
set_property TRIGGER_COMPARE_VALUE eq1'b1 $p
run_hw_ila $ila
puts "ARMED_STACK_TXEN"
after 500

exec D:/FPGA/prj/project_11/out/jb31b_eround_cap.bat

if {[catch {wait_on_hw_ila -timeout 30 $ila} e]} { puts "WAIT_NOTE: $e" }
set d [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file D:/FPGA/prj/project_11/out/jb31b_ila2_txen.csv $d
close_hw_target
disconnect_hw_server
puts "ILA2_CAP_DONE"
exit
