# 列出 v3 位流的 ILA 与探针（配对 probes.ltx = 2026-10-16 0:24）
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE {D:/FPGA/prj/project_11/scripts/probes.ltx} $dev
refresh_hw_device $dev
after 2000
puts "=== HW_ILAS ==="
foreach ila [get_hw_ilas] {
    puts "ILA: $ila"
    set pl [get_hw_probes -quiet -of_objects $ila]
    puts "  probes([llength $pl]): [join $pl {, }]"
}
close_hw_target
disconnect_hw_server
puts "ILA_LIST_DONE"
exit
