# 同帧对照: 桥模式(control16) vs E 模式(eround), 三 ILA 全计数差分
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
    after 150
    if {[catch {run_hw_ila -trigger_now $ila} e1]} { puts "ARM_FAIL($tag): $e1"; return }
    after 250
    catch {wait_on_hw_ila -timeout 10 $ila} e2
    set d [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file $csv $d
    puts "GRAB_$tag OK"
}

set i1 [get_hw_ilas hw_ila_1]
set i2 [get_hw_ilas hw_ila_2]
set i3 [get_hw_ilas hw_ila_3]
set B D:/FPGA/prj/project_11/out

grab $i1 $B/cmp_p0_i1.csv P0_I1
grab $i2 $B/cmp_p0_i2.csv P0_I2
grab $i3 $B/cmp_p0_i3.csv P0_I3

exec D:/FPGA/prj/project_11/out/jb31b_control16.bat
after 500
grab $i1 $B/cmp_p1_i1.csv P1_I1
grab $i2 $B/cmp_p1_i2.csv P1_I2
grab $i3 $B/cmp_p1_i3.csv P1_I3

exec D:/FPGA/prj/project_11/out/jb31b_eround_cap.bat
after 500
grab $i1 $B/cmp_p2_i1.csv P2_I1
grab $i2 $B/cmp_p2_i2.csv P2_I2
grab $i3 $B/cmp_p2_i3.csv P2_I3

close_hw_target
disconnect_hw_server
puts "CMP_DONE"
exit
