# J_B1 ③: ILA0 读回 (v6: CSV 导出离线解析)
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE {D:/FPGA/prj/project_11/out/archive/b1_ic_v2_2026-10-11/probes.ltx} $dev
refresh_hw_device $dev
after 2000
set target_ila ""
foreach ila [get_hw_ilas] {
    if {[llength [get_hw_probes -quiet -of_objects $ila dbg_lite_owner*]]} {
        set target_ila $ila
        break
    }
}
if {$target_ila eq ""} { error "ILA with dbg_lite_owner not found" }
puts "ILA0: $target_ila"
set po [get_hw_probes -quiet -of_objects $target_ila dbg_lite_owner*]
set_property TRIGGER_COMPARE_VALUE eq1'b1 $po
run_hw_ila $target_ila
after 3000
wait_on_hw_ila $target_ila
set iladata [upload_hw_ila_data $target_ila]
write_hw_ila_data -csv_file D:/FPGA/prj/project_11/out/jb1_ic2_ila_capture.csv $iladata
close_hw_target
disconnect_hw_server
puts "ILA_DONE_CSV"
exit
