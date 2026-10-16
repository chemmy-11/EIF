# jb31b_rdcap.tcl — 抓「发射字节流」: u_ila_0 新 probe1 (dbg_mem_rden + mem_rd_data[7:0])
# 模式由环境变量 RDCAP_MODE (bridge|e) 决定 -> exec 对应 bat -> 上传 CSV
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE {D:/FPGA/prj/project_11/out/probes_rdprobe.ltx} $dev
refresh_hw_device $dev
after 2000

set ila ""
foreach c [get_hw_ilas] {
    if {[llength [get_hw_probes -quiet -of_objects $c mem_rd_data*]]} { set ila $c; break }
}
if {$ila eq ""} { error "ILA with mem_rd_data probe not found" }
puts "RDCAP_ILA: $ila"
puts "RDCAP_PROBES: [join [get_hw_probes -quiet -of_objects $ila] {, }]"
catch {reset_hw_ila $ila}
after 200
set p [get_hw_probes -quiet -of_objects $ila dbg_mem_rden]
if {$p eq ""} { error "dbg_mem_rden probe not found" }
set_property TRIGGER_COMPARE_VALUE eq1'b1 $p
run_hw_ila $ila
puts "RDCAP_ARMED"
after 500

set mode $::env(RDCAP_MODE)
exec [format "D:/FPGA/prj/project_11/out/jb31b_rdcap_%s.bat" $mode]
after 500
if {[catch {wait_on_hw_ila -timeout 60 $ila} e]} { puts "RDCAP_WAIT_NOTE: $e" }
set d [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file [format "D:/FPGA/prj/project_11/out/jb31b_rdcap_%s.csv" $mode] $d
close_hw_target
disconnect_hw_server
puts "RDCAP_DONE mode=$mode"
exit
