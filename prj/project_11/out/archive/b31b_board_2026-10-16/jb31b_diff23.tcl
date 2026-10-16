# E 轮前后各抓 ILA1 + ILA3, 判定: 帧是否经 Aurora 出去并回来
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE {D:/FPGA/prj/project_11/scripts/probes.ltx} $dev
refresh_hw_device $dev
after 2000

proc grab {ila csv tag} {
    catch {reset_hw_ila $ila} e0
    after 200
    if {[catch {run_hw_ila -trigger_now $ila} e1]} { puts "ARM_FAIL($tag): $e1"; return }
    after 300
    catch {wait_on_hw_ila -timeout 10 $ila} e2
    set d [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file $csv $d
    puts "GRAB_$tag OK"
}

set i1 [get_hw_ilas hw_ila_1]
set i3 [get_hw_ilas hw_ila_3]
puts "i1=$i1 i3=$i3"

grab $i1 D:/FPGA/prj/project_11/out/jb31b_diff_i1_before.csv I1B
grab $i3 D:/FPGA/prj/project_11/out/jb31b_diff_i3_before.csv I3B
exec D:/FPGA/prj/project_11/out/jb31b_eround_cap.bat
after 500
grab $i1 D:/FPGA/prj/project_11/out/jb31b_diff_i1_after.csv I1A
grab $i3 D:/FPGA/prj/project_11/out/jb31b_diff_i3_after.csv I3A
close_hw_target
disconnect_hw_server
puts "DIFF23_DONE"
exit
