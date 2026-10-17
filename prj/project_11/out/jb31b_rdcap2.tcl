# jb31b_rdcap2.tcl - capture ONE emitted byte-stream frame from ILA probe1
# probe set: dbg_mem_rden + mem_rd_data[7:0] (9 bit, see scripts/build_debug.tcl:139-148)
# flow: open_hw_manager -> PROBES.FILE -> find ILA by mem_rd_data* -> reset -> trigger
#       dbg_mem_rden eq1'b1 -> run_hw_ila -> exec send bat -> wait -> upload -> csv
# NOTE: this file is ASCII only on purpose. Vivado decodes tcl sources with the host
#       ANSI codepage (GBK here), so non-ASCII comments can break the script.
# NOTE: every comment is on its own line; a trailing '#' after a command is not a
#       comment in Tcl (pit #19) and would be passed as an extra argument.
# env in:
#   RDCAP_LTX       probes ltx file (default: retire_flag probes_0ecb8438.ltx)
#   RDCAP_OUT       output csv (default: <this script dir>/jb31b_rdcap2_capture.csv)
#   RDCAP_SEND_CMD  bat to run inside the armed window (default: <dir>/jb31b_rdcap2_send.bat)
#   RDCAP_TRIG_DATA optional hex byte (e.g. 55); ANDs the mem_rd_data probe into the trigger
#   RDCAP_PRE_MS    ms between arm and send (default 500)
#   RDCAP_WAIT_S    wait_on_hw_ila timeout seconds (default 60)
#   RDCAP_MODE      label only (retired|green)
# exit marker: RDCAP2_DONE

proc envval {name defval} {
    if {[info exists ::env($name)]} {
        set v $::env($name)
        if {$v ne ""} {
            return $v
        }
    }
    return $defval
}

set here [file dirname [file normalize [info script]]]
set ltx [file normalize [envval RDCAP_LTX "D:/FPGA/prj/project_11/out/archive/b31b_retire_flag_2026-10-17/probes_0ecb8438.ltx"]]
set out [file normalize [envval RDCAP_OUT [file join $here jb31b_rdcap2_capture.csv]]]
set sendcmd [envval RDCAP_SEND_CMD [file join $here jb31b_rdcap2_send.bat]]
set trigdata [envval RDCAP_TRIG_DATA ""]
set prems [envval RDCAP_PRE_MS 500]
set waits [envval RDCAP_WAIT_S 60]
set label [envval RDCAP_MODE unlabeled]

if {![file exists $ltx]} {
    error "RDCAP_LTX not found: $ltx"
}
file mkdir [file dirname $out]

puts "RDCAP2_START mode=$label"
puts "RDCAP2_HOST [info hostname]"
puts "RDCAP2_LTX: $ltx"
puts "RDCAP2_OUT: $out"
puts "RDCAP2_SEND_CMD: $sendcmd"
puts "RDCAP2_PRE_MS: $prems"
puts "RDCAP2_WAIT_S: $waits"

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
puts "RDCAP2_DEV: $dev"
set_property PROBES.FILE $ltx $dev
if {[catch {refresh_hw_device $dev} e]} {
    puts "RDCAP2_REFRESH_NOTE: $e"
}
after 2000

set ila ""
foreach c [get_hw_ilas -quiet] {
    set hits [get_hw_probes -quiet -of_objects $c mem_rd_data*]
    puts "RDCAP2_ILA_CAND: $c mem_rd_data_probes=[llength $hits]"
    if {[llength $hits] > 0 && $ila eq ""} {
        set ila $c
    }
}
if {$ila eq ""} {
    foreach c [get_hw_ilas -quiet] {
        puts "RDCAP2_DUMP_ILA: $c"
        foreach p [get_hw_probes -quiet -of_objects $c] {
            puts "RDCAP2_DUMP_PROBE: $c $p"
        }
    }
    error "no ILA carrying a mem_rd_data* probe (ltx mismatch? see RDCAP2_DUMP_*)"
}
puts "RDCAP2_ILA: $ila"
puts "RDCAP2_PROBE_COUNT: [llength [get_hw_probes -quiet -of_objects $ila]]"
foreach p [get_hw_probes -quiet -of_objects $ila] {
    set w "-"
    catch { set w [get_property WIDTH $p] }
    puts "RDCAP2_PROBE: $p width=$w"
}

set depth "-"
catch { set depth [get_property DATA_DEPTH $ila] }
puts "RDCAP2_DATA_DEPTH: $depth"
set tpos "-"
catch { set_property TRIGGER_POSITION 0 $ila }
catch { set tpos [get_property TRIGGER_POSITION $ila] }
puts "RDCAP2_TRIGGER_POSITION: $tpos"

catch {reset_hw_ila $ila}
after 200

set pen ""
foreach p [get_hw_probes -quiet -of_objects $ila] {
    if {[string match -nocase "*dbg_mem_rden*" $p]} {
        set pen $p
    }
}
if {$pen eq ""} {
    error "dbg_mem_rden probe not found on $ila"
}
if {[catch {set_property TRIGGER_COMPARE_VALUE eq1'b1 $pen} e]} {
    error "cannot set trigger on $pen : $e"
}
set enback "-"
catch { set enback [get_property TRIGGER_COMPARE_VALUE $pen] }
puts "RDCAP2_TRIG: $pen = eq1'b1 readback=$enback"

if {$trigdata ne ""} {
    set pdat ""
    foreach p [get_hw_probes -quiet -of_objects $ila] {
        if {$pdat eq "" && [string match -nocase "*mem_rd_data*" $p]} {
            set pdat $p
        }
    }
    if {$pdat eq ""} {
        puts "RDCAP2_TRIG_DATA_SKIP: no mem_rd_data probe object; trigger stays en-only"
    } else {
        set tv [format "eq8'h%s" $trigdata]
        if {[catch {set_property TRIGGER_COMPARE_VALUE $tv $pdat} e]} {
            puts "RDCAP2_TRIG_DATA_FAIL: $e"
        } else {
            puts "RDCAP2_TRIG_DATA: $pdat = $tv"
        }
    }
}

run_hw_ila $ila
puts "RDCAP2_ARMED"
after [expr {$prems + 0}]

if {[file exists $sendcmd]} {
    if {[catch {exec $sendcmd} e]} {
        puts "RDCAP2_SEND_NOTE: $e"
    } else {
        puts "RDCAP2_SEND: ok $sendcmd"
    }
} else {
    puts "RDCAP2_SEND_MISSING: $sendcmd"
}

if {[catch {wait_on_hw_ila -timeout $waits $ila} e]} {
    puts "RDCAP2_WAIT_NOTE: $e"
} else {
    puts "RDCAP2_WAIT: ok"
}

set d ""
if {[catch {set d [upload_hw_ila_data $ila]} e]} {
    error "upload_hw_ila_data failed: $e (did the trigger fire? check RDCAP2_ARMED and the send log)"
}
write_hw_ila_data -force -csv_file $out $d
puts "RDCAP2_CSV: $out"

set nrows 0
set firstrow ""
if {[catch {
    set fh [open $out r]
    while {[gets $fh line] >= 0} {
        incr nrows
        if {$nrows == 3} {
            set firstrow $line
        }
    }
    close $fh
} e]} {
    puts "RDCAP2_CSV_NOTE: $e"
}
puts "RDCAP2_CSV_ROWS: $nrows"
puts "RDCAP2_CSV_SAMPLES: [expr {$nrows - 2}]"
puts "RDCAP2_CSV_FIRSTROW: $firstrow"

close_hw_target
disconnect_hw_server
puts "RDCAP2_DONE"
exit
