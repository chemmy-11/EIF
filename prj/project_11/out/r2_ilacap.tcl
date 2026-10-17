# =============================================================================
# r2_ilacap.tcl - prj11 R2 (B3-2 bridge-1 write path switched to S2MM)
#                 bridge-level counter ILA pre/post snapshot capture
#
# PURPOSE
#   In one Vivado hw_manager batch session: capture PRE snapshot, run a stimulus
#   (default: ping -n 4), settle, capture POST snapshot; export CSVs consumed by
#   out/r2_counter_recon.py:
#     S6  : bridge2 dbg_mem2_rd_frm advances by N, dbg_mem2_ost is 0 before/after;
#           bridge1 dbg_mem_wm/wr_frm/rd_frm each advance by N, dbg_mem_ost 0.
#     S10 : J4 caliber reconciliation, each bridge wm == wr_frm == rd_frm,
#           ost == 0, error counters 0 where observable.
#
# USAGE (Lead executes on board; r2_board.ps1 -Run -IlaCapture calls this):
#   vivado -mode batch -source out/r2_ilacap.tcl -notrace -log <evidence>/R2_ilacap_vivado.log
#   env in (PowerShell: $env:R2_XXX=...):
#     R2_LTX             archived probes ltx matching the burned bit
#                        (default: <this dir>/scripts/probes.ltx)
#     R2_OUT_DIR         output dir (default: <this dir>/evidence_2026-10-17)
#     R2_TAG             file tag (default: r2)
#     R2_STIM_CMD        stimulus command executed between PRE and POST
#                        (default: ping -n 4 -w 900 192.168.1.10)
#     R2_SETTLE_MS       settle ms before POST (default: 2000)
#     R2_PRE_MS          wait ms after hw_server connect before PRE (default: 800)
#     R2_WAIT_S          wait_on_hw_ila timeout seconds (default: 30)
#     R2_SNAPSHOT_ONLY   1 = capture PRE only (no stimulus), for final snapshot
#     R2_ILA_MATCH_UI    ui-domain ILA probe pattern (default: dbg_mem2_rd_frm)
#     R2_ILA_MATCH_USER  user-domain ILA probe pattern (default: dbg_mem2_u_wr)
#     R2_ILA_MATCH_EXTRA optional third ILA pattern (default: empty = none)
#     R2_EXPECT_PROBES   comma separated new-probe presence check list (WARN only)
#
# OUTPUT FILES
#   <R2_OUT_DIR>/R2_ila_<TAG>_ui_pre.csv / _ui_post.csv
#   <R2_OUT_DIR>/R2_ila_<TAG>_user_pre.csv / _user_post.csv
#   (+ optional _extra_pre.csv / _extra_post.csv)
#
# MARKERS
#   R2CAP_RESULT: PASS|FAIL <reason>   <- verdict line (this script has no exit code;
#                                          verdict = this line + CSV existence)
#   R2CAP_START / R2CAP_LTX / R2CAP_ILA_* / R2CAP_PROBE_* / R2CAP_GRAB_* /
#   R2CAP_STIM / R2CAP_SNAPSHOT / R2CAP_EXPECT_PROBE_* / R2CAP_DONE
#
# PROBE LAYOUT (R2 v1.2, mechanically aligned with final build_synth_only.tcl /
# build_debug.tcl, Lead 2026-10-17)
#   ILA3 @ui_clk : dbg_s2mm_state[2:0] / dbg_s2mm_tvalid / dbg_s2mm_tready
#                  + old bridge counters dbg_mem_* (wm/wr_frm/rd_frm/stall/
#                    len_err/bresp/ost/wslot/rslot)
#                  + old bridge counters dbg_mem2_* (wm/wr_frm/rd_frm/ost)
#   ILA0 @user   : dbg_s2mm_reqpend / dbg_wr_fault
#                  + old user-side probes dbg_mem_u_*/dbg_mem2_u_* etc.
#   dbg_wr_timeout is NOT on ILA on purpose (save 300MHz ILA3 margin; R1/W6 lesson:
#   96b on the 300MHz domain once pushed WNS to -1.142). stat_wr_timeout is a 16b
#   bridge counter with NO Lite readback path (not in +0x40/+0x44) => board-side
#   timeout count is unobservable; r2_counter_recon.py reports it as INFO only.
#   Observables usable for interpretation (still not hard criteria):
#     ILA3 dbg_s2mm_state encode 0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE
#                                5=DRAIN 6=HALT
#     ILA0 dbg_wr_fault / 'U' wreq,wdbg,s2sr / ro_wm progression
#   Interpretation notes (DESIGN v1.2, audit A3-A6/A11/A12; INFO only):
#     * state 6 = HALT = fail-stop (STREAM/PUSH/WAITDONE watchdog, fault=1);
#       recovery is firmware-only: S2MM_DMACR reset -> RS+IOC -> clear IOC ->
#       write +0x4C (opcode 0x06) to toggle ACK.
#     * WAITGO timeout (~56ms, 0xFFFFFF @300MHz) is a BENIGN frame drop
#       (pending=0, stat_wr_timeout++, no fault, no halt) - do not read it as HALT.
#     * ro_lat_w is constant 0 on bridge1/u_mem after write-side retirement (D8);
#       never use GET_LATENCY bridge1 values as a criterion.
#     * WR_DBG.last_alloc_slot = last ALLOCATED slot, last_commit_len = last
#       COMMITTED frame length (alloc != commit, A12).
#
# DISCIPLINE (AGENTS.md section 6.2 and pitfall #40)
#   * arm -> stimulus -> upload in ONE batch session; trigger with -trigger_now
#     snapshot (watch_on_hw_ila has no timeout-safe edge condition for silent links).
#   * do not read get_property VALUE in batch mode; export CSV and parse offline.
#   * locate ILA by get_hw_probes -of_objects, never guess hw_ila_N numbering.
#
# NOTE: this file is ASCII ONLY on purpose. Vivado decodes Tcl sources with the
#       host ANSI codepage (GBK here), so non-ASCII bytes can break the script.
#       All comments are on their own lines (a trailing '#' is not a Tcl comment,
#       pitfall #19).
# =============================================================================

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
set ltx [file normalize [envval R2_LTX [file join $here scripts probes.ltx]]]
set outdir [file normalize [envval R2_OUT_DIR [file join $here evidence_2026-10-17]]]
set tag [envval R2_TAG r2]
set stim [envval R2_STIM_CMD "ping -n 4 -w 900 192.168.1.10"]
set settlems [envval R2_SETTLE_MS 2000]
set prems [envval R2_PRE_MS 800]
set waits [envval R2_WAIT_S 30]
set snapshot_only [envval R2_SNAPSHOT_ONLY 0]
set match_ui [envval R2_ILA_MATCH_UI "dbg_mem2_rd_frm"]
set match_user [envval R2_ILA_MATCH_USER "dbg_mem2_u_wr"]
set match_extra [envval R2_ILA_MATCH_EXTRA ""]
set expect_probes [split [envval R2_EXPECT_PROBES "dbg_s2mm_reqpend,dbg_wr_fault,dbg_s2mm_state,dbg_s2mm_tvalid,dbg_s2mm_tready"] ","]

puts "R2CAP_START tag=$tag"
puts "R2CAP_HOST [info hostname]"
puts "R2CAP_TCL: [file normalize [info script]]"
puts "R2CAP_LTX: $ltx"
puts "R2CAP_OUT_DIR: $outdir"
puts "R2CAP_STIM_CMD: $stim"
puts "R2CAP_SETTLE_MS: $settlems"
puts "R2CAP_PRE_MS: $prems"
puts "R2CAP_WAIT_S: $waits"
puts "R2CAP_SNAPSHOT_ONLY: $snapshot_only"
puts "R2CAP_MATCH_UI: $match_ui"
puts "R2CAP_MATCH_USER: $match_user"
puts "R2CAP_MATCH_EXTRA: $match_extra"
puts "R2CAP_EXPECT_PROBES: $expect_probes"

if {![file exists $ltx]} {
    puts "R2CAP_RESULT: FAIL ltx not found: $ltx (set R2_LTX to the ARCHIVED probes ltx matching the burned bit)"
    exit
}
file mkdir $outdir

proc find_ila {pat} {
    foreach c [get_hw_ilas -quiet] {
        if {[llength [get_hw_probes -quiet -of_objects $c $pat]] > 0} {
            return $c
        }
    }
    return ""
}

proc dump_probes {ila label} {
    set n 0
    foreach p [get_hw_probes -quiet -of_objects $ila] {
        set w "-"
        catch { set w [get_property WIDTH $p] }
        puts "R2CAP_PROBE($label): $p width=$w"
        incr n
    }
    puts "R2CAP_PROBE_COUNT($label): $n"
}

proc count_probes {ila pats} {
    set n 0
    set names {}
    foreach p [get_hw_probes -quiet -of_objects $ila] {
        foreach pat $pats {
            if {[string match -nocase $pat $p]} {
                incr n
                lappend names $p
                break
            }
        }
    }
    return [list $n $names]
}

proc collect_all_probes {} {
    set acc {}
    foreach c [get_hw_ilas -quiet] {
        foreach p [get_hw_probes -quiet -of_objects $c] { lappend acc $p }
    }
    return $acc
}

proc csv_rows {path} {
    set nrows 0
    if {[catch {
        set fh [open $path r]
        while {[gets $fh line] >= 0} { incr nrows }
        close $fh
    } e]} {
        return -1
    }
    return $nrows
}

proc grab {ila csv label} {
    global waits
    if {[catch {reset_hw_ila $ila} e]} { puts "R2CAP_RESET_NOTE($label): $e" }
    after 300
    if {[catch {run_hw_ila -trigger_now $ila} e1]} {
        puts "R2CAP_GRAB_FAIL($label): run_hw_ila: $e1"
        return 0
    }
    after 300
    if {[catch {wait_on_hw_ila -timeout $waits $ila} e2]} {
        puts "R2CAP_WAIT_NOTE($label): $e2"
    }
    if {[catch {set d [upload_hw_ila_data $ila]} e3]} {
        puts "R2CAP_GRAB_FAIL($label): upload_hw_ila_data: $e3"
        return 0
    }
    if {[catch {write_hw_ila_data -force -csv_file $csv $d} e4]} {
        puts "R2CAP_GRAB_FAIL($label): write_hw_ila_data: $e4"
        return 0
    }
    set n [csv_rows $csv]
    puts "R2CAP_GRAB_$label: OK $csv rows=$n"
    return 1
}

# ---- connect hw_server (same flow as R1 jb31b_r1cap.tcl / jb31b_rdcap2.tcl) ----
if {[catch {open_hw_manager} e]} { puts "R2CAP_OPEN_NOTE: $e" }
if {[catch {connect_hw_server} e]} { puts "R2CAP_CONNECT_NOTE: $e" }
if {[catch {open_hw_target} e]} { puts "R2CAP_TARGET_NOTE: $e" }
set dev [lindex [get_hw_devices -quiet] 0]
if {$dev eq ""} {
    puts "R2CAP_RESULT: FAIL no hw_device (hw_server/JTAG not connected; power-cycle or check Digilent USB-JTAG)"
    exit
}
current_hw_device $dev
puts "R2CAP_DEV: $dev"
set partid ""
if {[catch {set partid [get_property PART $dev]} e]} { set partid "?" }
puts "R2CAP_PART: $partid"
if {[catch {set_property PROBES.FILE $ltx $dev} e]} {
    puts "R2CAP_RESULT: FAIL set PROBES.FILE failed: $e (ltx does not match the bitstream?)"
    exit
}
if {[catch {refresh_hw_device $dev} e]} {
    puts "R2CAP_REFRESH_NOTE: $e"
}
after $prems

# ---- locate ILA by probes (pitfall #40 item 3: never guess hw_ila_N) ----
puts "R2CAP_ILA_INVENTORY:"
foreach c [get_hw_ilas -quiet] {
    set np [llength [get_hw_probes -quiet -of_objects $c]]
    puts "R2CAP_ILA: $c probes=$np"
}

set ila_ui [find_ila $match_ui]
if {$ila_ui eq ""} {
    set ila_ui [find_ila "dbg_s2mm_state"]
    if {$ila_ui ne ""} { puts "R2CAP_ILA_UI_FALLBACK: matched by dbg_s2mm_state" }
}
set ila_user ""
if {$match_user ne ""} { set ila_user [find_ila $match_user] }
if {$ila_user eq ""} {
    set ila_user [find_ila "dbg_s2mm_reqpend"]
    if {$ila_user ne ""} { puts "R2CAP_ILA_USER_FALLBACK: matched by dbg_s2mm_reqpend" }
}
set ila_extra ""
if {$match_extra ne ""} { set ila_extra [find_ila $match_extra] }
puts "R2CAP_ILA_UI: $ila_ui"
puts "R2CAP_ILA_USER: $ila_user"
puts "R2CAP_ILA_EXTRA: $ila_extra"

if {$ila_ui eq ""} {
    puts "R2CAP_RESULT: FAIL no ILA carrying '$match_ui' nor 'dbg_s2mm_state' (ltx mismatch? dump follows)"
    foreach c [get_hw_ilas -quiet] {
        foreach p [get_hw_probes -quiet -of_objects $c] {
            puts "R2CAP_DUMP_PROBE: $c $p"
        }
    }
    exit
}

# ---- probe inventory + R2 new-probe presence ----
dump_probes $ila_ui UI
if {$ila_user ne ""} { dump_probes $ila_user USER }

set r2p [count_probes $ila_ui [list "dbg_s2mm_*" "dbg_wr_timeout*" "dbg_wr_fault*"]]
puts "R2CAP_R2PROBE_COUNT: [lindex $r2p 0]"
puts "R2CAP_R2PROBES: [lindex $r2p 1]"
if {[lindex $r2p 0] == 0} {
    puts "R2CAP_R2PROBE_WARN: no dbg_s2mm_*/dbg_wr_timeout*/dbg_wr_fault* probe on ui ILA; old counters still usable for reconciliation"
}

set allprobes [collect_all_probes]
puts "R2CAP_ALLPROBE_COUNT: [llength $allprobes]"
set miss {}
foreach e $expect_probes {
    set e [string trim $e]
    if {$e eq ""} { continue }
    set hit 0
    foreach p $allprobes {
        if {[string match -nocase "*$e*" $p]} { set hit 1; break }
    }
    if {!$hit} { lappend miss $e }
}
puts "R2CAP_EXPECT_PROBE_TOTAL: [llength $expect_probes]"
if {[llength $miss] == 0} {
    puts "R2CAP_EXPECT_PROBE_OK: all R2 probes present"
} else {
    puts "R2CAP_EXPECT_PROBE_MISSING: $miss"
    puts "R2CAP_EXPECT_PROBE_NOTE: missing probe means probes.ltx does not match the burned bitstream, or the build did not include it; old-probe reconciliation can still proceed"
}

# ---- snapshot capture ----
set ui_pre [file join $outdir "R2_ila_${tag}_ui_pre.csv"]
set ui_post [file join $outdir "R2_ila_${tag}_ui_post.csv"]
set user_pre [file join $outdir "R2_ila_${tag}_user_pre.csv"]
set user_post [file join $outdir "R2_ila_${tag}_user_post.csv"]

set ok_ui_pre 0
set ok_ui_post 0
set ok_user_pre 0
set ok_user_post 0

set ok_ui_pre [grab $ila_ui $ui_pre PRE_UI]
if {$ila_user ne ""} { set ok_user_pre [grab $ila_user $user_pre PRE_USER] }

if {$snapshot_only eq "1"} {
    puts "R2CAP_SNAPSHOT: only PRE captured (R2_SNAPSHOT_ONLY=1); no stimulus executed"
    set ok_ui_post $ok_ui_pre
} else {
    puts "R2CAP_STIM: $stim"
    if {[catch {exec cmd /c $stim} es]} {
        puts "R2CAP_STIM_NOTE: $es"
    } else {
        puts "R2CAP_STIM_OK"
    }
    after $settlems
    puts "R2CAP_SETTLE_DONE: $settlems ms"
    set ok_ui_post [grab $ila_ui $ui_post POST_UI]
    if {$ila_user ne ""} { set ok_user_post [grab $ila_user $user_post POST_USER] }
}

if {$ila_extra ne ""} {
    set ex_pre [file join $outdir "R2_ila_${tag}_extra_pre.csv"]
    set ex_post [file join $outdir "R2_ila_${tag}_extra_post.csv"]
    set ok_ex_pre [grab $ila_extra $ex_pre PRE_EXTRA]
    if {$snapshot_only ne "1"} {
        after $settlems
        set ok_ex_post [grab $ila_extra $ex_post POST_EXTRA]
    }
}

catch {close_hw_target}
catch {disconnect_hw_server}

if {$snapshot_only eq "1"} {
    if {$ok_ui_pre} {
        puts "R2CAP_CSV_UI_PRE: $ui_pre"
        puts "R2CAP_RESULT: PASS snapshot"
    } else {
        puts "R2CAP_RESULT: FAIL snapshot capture failed"
    }
} else {
    if {$ok_ui_pre && $ok_ui_post} {
        puts "R2CAP_CSV_UI_PRE: $ui_pre"
        puts "R2CAP_CSV_UI_POST: $ui_post"
        if {$ila_user ne ""} {
            puts "R2CAP_CSV_USER_PRE: $user_pre"
            puts "R2CAP_CSV_USER_POST: $user_post"
        }
        if {$ila_user ne "" && !($ok_user_pre && $ok_user_post)} {
            puts "R2CAP_RESULT: PASS ui-only (user-domain capture incomplete; bridge2 user-side evidence missing)"
        } else {
            puts "R2CAP_RESULT: PASS"
        }
    } else {
        puts "R2CAP_RESULT: FAIL ui pre/post capture incomplete (pre=$ok_ui_pre post=$ok_ui_post)"
    }
}
puts "R2CAP_DONE"
exit
