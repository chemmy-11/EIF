# r1cap: snapshot cumulative counters of bridge1(ui) and bridge2(user+ui) around a ping burst
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE {D:/FPGA/prj/project_11/out/archive/b31b_rdfix_2026-10-17/probes_rdfix_c8cd3a32.ltx} $dev
refresh_hw_device $dev
after 2000

set o D:/FPGA/prj/project_11/out/evidence_2026-10-17

proc find_ila {probe} {
  foreach c [get_hw_ilas] {
    if {[llength [get_hw_probes -quiet -of_objects $c $probe]]} { return $c }
  }
  return ""
}
proc grab {ila csv tag} {
  catch {reset_hw_ila $ila}
  after 200
  if {[catch {run_hw_ila -trigger_now $ila} e1]} { puts "ARM_FAIL($tag): $e1"; return }
  after 300
  if {[catch {wait_on_hw_ila -timeout 10 $ila} e2]} { puts "WAIT_NOTE($tag): $e2" }
  set d [upload_hw_ila_data $ila]
  write_hw_ila_data -force -csv_file $csv $d
  puts "GRAB_$tag OK"
}
set ilaU [find_ila dbg_mem2_u_wr]
set ilaC [find_ila dbg_mem2_rd_frm]
puts "ILAU=$ilaU ILAC=$ilaC"
grab $ilaU $o/ilacap_pre_user.csv PRE_USER
grab $ilaC $o/ilacap_pre_ui.csv PRE_UI
puts "=== PING_PHASE (ping -n 4) ==="
catch {exec cmd /c "ping -n 4 -w 900 192.168.1.10 > NUL"}
after 800
grab $ilaU $o/ilacap_post_user.csv POST_USER
grab $ilaC $o/ilacap_post_ui.csv POST_UI
close_hw_target
disconnect_hw_server
puts "R1CAP_DONE"
exit
