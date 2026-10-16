# E 轮前后各抓一次 ILA1 (累计计数), 用于差分判定帧是否进入上行(Aurora)路径
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE {D:/FPGA/prj/project_11/scripts/probes.ltx} $dev
refresh_hw_device $dev
after 2000

set ila [get_hw_ilas hw_ila_1]
puts "ILA1 = $ila"

proc grab {ila csv tag} {
    catch {reset_hw_ila $ila} e0
    after 200
    if {[catch {run_hw_ila -trigger_now $ila} e1]} { puts "ARM_FAIL($tag): $e1"; return }
    after 300
    if {[catch {wait_on_hw_ila -timeout 10 $ila} e2]} { puts "WAIT_NOTE($tag): $e2" }
    set d [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file $csv $d
    puts "GRAB_$tag OK"
}

grab $ila D:/FPGA/prj/project_11/out/jb31b_ila1_before.csv BEFORE
after 300
exec D:/FPGA/prj/project_11/out/jb31b_eround_cap.bat
after 500
grab $ila D:/FPGA/prj/project_11/out/jb31b_ila1_after.csv AFTER
close_hw_target
disconnect_hw_server
puts "ILA1_DIFF_DONE"
exit
