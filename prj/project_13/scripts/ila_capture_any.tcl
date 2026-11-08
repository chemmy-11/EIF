# =============================================================================
# ila_capture_any.tcl — prj12: capture ANY ILA core by naming one of its probes.
# Usage:
#   vivado -mode batch -source ila_capture_any.tcl -tclargs ^
#       <hw_server_url> <cable_serial|-> <out_csv> <ltx> <probe_name> [trigger_probe]
#   e.g. -tclargs localhost:3121 210512180081 out/ila3.csv scripts/probes.ltx dbg_calib
# Notes:
#   * probe_name is an RTL net name present in probes.ltx (e.g. dbg_calib, dbg_ch_up).
#   * trigger_probe optional; default = trigger_now.
# =============================================================================
set url    [lindex $argv 0]
set cable  [lindex $argv 1]
set out    [lindex $argv 2]
set ltx    [lindex $argv 3]
set pname  [lindex $argv 4]
set trig   [lindex $argv 5]
if {$url eq "" || $out eq "" || $ltx eq "" || $pname eq ""} {
    error "usage: -tclargs <url> <cable|-> <out_csv> <ltx> <probe_name> [trigger_probe]"
}
if {![file exists $ltx]} { error "ltx not found: $ltx" }

open_hw_manager
connect_hw_server -url $url
set targets [get_hw_targets]
puts "ILA_HW_TARGETS: $targets"
set tgt [lindex $targets 0]
if {$cable ne "" && $cable ne "-"} {
    set sel [get_hw_targets -quiet *$cable*]
    if {[llength $sel] != 1} { error "cable select failed: *$cable* -> $sel" }
    set tgt [lindex $sel 0]
}
current_hw_target $tgt
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
refresh_hw_device $dev
puts "ILA_HW_DEVICE: $dev"

set ila ""
foreach i [get_hw_ilas -of_objects $dev] {
    set n [llength [get_hw_probes -quiet $pname -of_objects $i]]
    set np [llength [get_hw_probes -quiet -of_objects $i]]
    puts "ILA_CAND: $i probes=$np has_${pname}=$n"
    if {$n >= 1} { set ila $i }
}
if {$ila eq ""} { error "no ILA has probe $pname" }
current_hw_ila $ila
puts "ILA_SELECTED: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "ILA_PROBE: $p" }

if {$trig ne "" && $trig ne "-"} {
    set p [get_hw_probes -quiet $trig -of_objects $ila]
    if {[llength $p] == 1} {
        set_property TRIGGER_COMPARE_VALUE eq1 $p
        if {[catch {run_hw_ila $ila; wait_on_hw_ila -timeout 10 $ila} e]} {
            puts "ILA_TRIGGER_TIMEOUT: $e -> trigger_now"
            run_hw_ila -trigger_now $ila
        }
    } else {
        run_hw_ila -trigger_now $ila
    }
} else {
    run_hw_ila -trigger_now $ila
}
wait_on_hw_ila $ila
set data [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file $out $data
puts "ILA_CSV_OK: $out"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
