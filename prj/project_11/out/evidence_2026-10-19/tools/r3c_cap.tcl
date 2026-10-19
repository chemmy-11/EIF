# =============================================================================
# r3c_cap.tcl -- prj11 R2 round3c : 4-ILA PRE/POST capture (snapshot or triggered)
#
# PURPOSE
#   One Vivado hw_manager batch session captures all ILA cores of the round3c
#   bitstream (expected 4 cores):
#     ILA0 @user_clk   (bridge user-side counters + S2MM reqpend/fault + emit)
#     ILA3 @ui_clk     (bridge ui counters + s2mm state/tvalid/tready)
#     ILA4 @clk_100m   (NEW round3c: axi_lite_regs AXI-lite wedge probes, ~36-40b)
#     ILA5 @ui_clk     (round3b 75b S2MM write stream + round3c probe5 7b:
#                       dbg_wd_go_ui / dbg_wd_ack_ui / dbg_wd_intr_ui /
#                       dbg_wd_go_ok / dbg_s2mm_state[2:0])
#
#   Two capture modes:
#     snapshot mode  (R2_SNAPSHOT_ONLY=1)   : capture the CURRENT state of every
#                                             core with run_hw_ila -trigger_now.
#                                             Use this once the board is already
#                                             wedged (static stuck state).
#     triggered mode (default)              : PRE snapshot of every core, then arm
#                                             each core that has a trigger spec,
#                                             run the stimulus (R2_STIM_CMD), wait
#                                             for trigger (minutes!), upload POST.
#                                             Cores without a trigger spec get a
#                                             plain trigger_now POST snapshot.
#   PRE/POST in one session = "before/after the event" evidence pair.
#
# USAGE (Lead executes on the board; never run by the offline tool author):
#   vivado -mode batch -source <this file> -notrace -log <evid>\R3C_cap_vivado.log
#   env (PowerShell: $env:R2_XXX='...'):
#     R2_LTX               archived probes ltx matching the BURNED bitstream (required)
#     R2_OUT_DIR           CSV output dir (default: the parent evidence dir)
#     R2_TAG               file tag (default: r3c)
#     R2_SNAPSHOT_ONLY     1 = current-state snapshot only, no stimulus, no trigger
#     R2_STIM_CMD          stimulus command executed between arming and waiting
#                          (default: empty = no stimulus; e.g. 'ping -n 1 -w 900 192.168.1.10')
#     R2_SETTLE_MS         settle ms after stimulus for non-armed cores (default: 2000)
#     R2_PRE_MS            ms after hw_server connect before PRE (default: 800)
#     R2_WAIT_MIN          wait_on_hw_ila -timeout value in MINUTES (default: 2)
#                          (pitfall #66 item 2: the unit is minutes, NOT seconds)
#     R2_TRIG_POSITION     trigger position in samples (default: 512; depth 1024 cores)
#     R3C_SKIP_PRE         1 = do not capture PRE (triggered mode only)
#     R3C_EXPECT_ILA_COUNT expected ILA core count (default: 4; warn only)
#     R2C_EXPECT_WIDTH_ILA0 / _ILA3 / _ILA5 / _ILA4
#                          expected total probe bits per core (warn only; leave
#                          ILA4 empty until the round3c ltx is pinned)
#     R2_TRIG_ILA0 / R2_TRIG_ILA3 / R2_TRIG_ILA4 / R2_TRIG_ILA5
#                          per-core trigger spec: '<probe>' or '<probe>=<cmp>' or
#                          '<probe>==1' / '<probe>==0'; several conditions can be
#                          chained with ';' (all combined by TRIGGER_CONDITION AND).
#                          Probe names are matched as LITERAL substrings (a name
#                          like 'dbg_l_bus[35]' is looked up verbatim, brackets
#                          are not glob character classes).
#                          Defaults (round3c build_synth_only.tcl 2026-10-19):
#                                    ILA4 'dbg_l_bus[35]=eq1'b1'
#                                         (bus bit35 = |stuck[3:0], u_ila_4/probe1)
#                                    ILA5 'dbg_wd_go_ui=eq1'b1'
#                                    ILA0/ILA3 empty (snapshot POST only).
#     R2_MATCH_ILA0/3/4/5  comma separated probe-name substrings used to LABEL the
#                          cores (auto discovery; never hardcode hw_ila_N).
#                          ILA4 default 'dbg_l_bus' matches the round3c packed
#                          debug bus probes named dbg_l_bus[0] .. dbg_l_bus[35].
#
# OUTPUT FILES (in R2_OUT_DIR):
#   R3C_<tag>_ILA4_pre.csv  / _post.csv
#   R3C_<tag>_ILA5_pre.csv  / _post.csv
#   R3C_<tag>_ILA3_pre.csv  / _post.csv
#   R3C_<tag>_ILA0_pre.csv  / _post.csv
#   (+ R3C_<tag>_ILAEXTRA<n>_*.csv for any extra core)
#
# MARKERS (machine-readable lines; grep these)
#   R3C_START / R3C_CFG_* / R3C_DEV / R3C_PART / R3C_CORE_TOTAL
#   R3C_ILA_LABEL: <label> = <hw_ila_N> (matched by ...)
#   R3C_LABEL_MISSING / R3C_ILA_COUNT_WARN
#   R3C_PROBE_MAP: label=... core=... probes=N total_bits=M
#   R3C_PROBE: <label> <name> width=<w>
#   R3C_WIDTH: / R3C_WIDTH_WARN:
#   R3C_TRIG_SET / R3C_TRIG_ARMED / R3C_TRIG_PROBE_MISSING / R3C_TRIG_ARM_SKIP
#   R3C_STIM / R3C_STIM_OK / R3C_GRAB(...) / R3C_TRIG_STATUS(...)
#   R3C_TRIGGER_SUMMARY / R3C_CSV / R3C_RESULT: PASS|FAIL|NO_TRIGGER / R3C_DONE
#
# EXIT CODES: 0 PASS (or PASS snapshot), 1 FAIL, 2 NO_TRIGGER (judgement not
#             obtained: trigger never fired; CSVs are pre-trigger data, never
#             read them as PASS -- AGENTS.md 6a rule 3).
#
# DISCIPLINE (AGENTS.md section 6 / pitfall ledger)
#   #40  arm->stimulus->upload in ONE batch session; never read probe VALUE in
#        batch mode (upload + write_hw_ila_data -csv_file, parse offline);
#        locate ILA cores via get_hw_probes -of_objects, never guess hw_ila_N.
#   #66  (1) explicitly set CONTROL.TRIGGER_MODE BASIC_ONLY and
#        CONTROL.TRIGGER_CONDITION AND so multiple compares combine by AND;
#        (2) wait_on_hw_ila -timeout is in MINUTES;
#        (3) write_hw_ila_data -csv_file takes a BASENAME (no .csv suffix).
#   #67  C_DATA_DEPTH minimum legal value in Vivado 2023.1 is 1024 (bitstream
#        property; not touched here).
#   #19  every comment is on its own line (no trailing '#' comments).
#   ASCII ONLY on purpose: Vivado decodes Tcl sources with the host ANSI
#   codepage (GBK here), so non-ASCII bytes in Tcl can break the parse.
#
# EXPECTED round3c probe layout (pinned in r3c_pin.md; check = WARN only):
#   ILA0 @user  probe0 101b + probe1 9b  -> total 110 bits
#   ILA3 @ui    probe0 152b              -> total 152 bits
#   ILA5 @ui    75b (round3b) + probe5 7b -> total 82 bits
#   ILA4 @clk_100m  probe0 36b + probe1 1b -> total 37 bits
#     round3c RTL packs the observation bus dbg_o[35:0] in axi_lite_regs.v
#     -> BD port dbg_l_bus[35:0] -> top-level net dbg_l_bus[i]; the LTX probe
#     names are therefore dbg_l_bus[0] .. dbg_l_bus[35] (probe1 duplicates
#     bit35, so it may appear as dbg_l_bus[35]_1).  Bit map:
#       [0..9]  AR/R/AW/W/B valid+ready
#       [10..13] AR address class: +0x34 DMA_REQ / +0x40 WR_REQ / +0x44 WR_DBG / other
#       [14..17] AW address class: +0x0C SET_ENGINE / +0x48 SET_WRGO / +0x4C SET_WRACK / other
#       [18..21] lwst[1:0] (18,19) / lrst[1:0] (20,21)
#       [22..27] a_req / a_ack_s[1] / r_req / r_ack_s[1] / d_req_s[1] / d_ack
#       [28..30] aresetn / rstuser_s2 / rstuser_evt
#       [31..34] stuck: lrst!=IDLE / lwst!=IDLE / arvalid&!arready / rvalid&!rready
#       [35]    |stuck[3:0]  <-- ILA4 trigger bit (probe1)
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

proc envalias {names defval} {
    foreach n $names {
        if {[info exists ::env($n)]} {
            set v $::env($n)
            if {$v ne ""} {
                return $v
            }
        }
    }
    return $defval
}

set here     [file dirname [file normalize [info script]]]
set ltx      [envalias {R2_LTX R3C_LTX} ""]
set outdir   [file normalize [envalias {R2_OUT_DIR R3C_OUT_DIR} [file join $here ".."]]]
set tag      [envalias {R2_TAG R3C_TAG} r3c]
set snap_only [envalias {R2_SNAPSHOT_ONLY R3C_SNAPSHOT_ONLY} 0]
set stim     [envalias {R2_STIM_CMD R3C_STIM_CMD} ""]
set settlems [envalias {R2_SETTLE_MS R3C_SETTLE_MS} 2000]
set prems    [envalias {R2_PRE_MS R3C_PRE_MS} 800]
set waitmin  [envalias {R2_WAIT_MIN R2_TRIG_TIMEOUT_MIN R3C_TRIG_TIMEOUT_MIN} 2]
set trigpos  [envalias {R2_TRIG_POSITION R3C_TRIG_POSITION} 512]
set skip_pre [envalias {R3C_SKIP_PRE R2_SKIP_PRE} 0]
set expect_ila [envalias {R3C_EXPECT_ILA_COUNT R2_EXPECT_ILA_COUNT} 4]
set w0 [envalias {R2C_EXPECT_WIDTH_ILA0} 110]
set w3 [envalias {R2C_EXPECT_WIDTH_ILA3} 152]
set w5 [envalias {R2C_EXPECT_WIDTH_ILA5} 82]
set w4 [envalias {R2C_EXPECT_WIDTH_ILA4} 37]
set trig_ila0 [envalias {R2_TRIG_ILA0} ""]
set trig_ila3 [envalias {R2_TRIG_ILA3} ""]
set trig_ila4 [envalias {R2_TRIG_ILA4} "dbg_l_bus\[35\]=eq1'b1"]
set trig_ila5 [envalias {R2_TRIG_ILA5} "dbg_wd_go_ui=eq1'b1"]
set match_ila0 [envalias {R2_MATCH_ILA0} "dbg_mem2_u_wr,dbg_mem_u_wr,dbg_s2mm_reqpend,dbg_pfwd_en,dbg_wr_fault"]
set match_ila3 [envalias {R2_MATCH_ILA3} "dbg_mem2_rd_frm,dbg_mem_wm,dbg_mem_rd_frm,dbg_calib,dbg_mem_len_err"]
set match_ila4 [envalias {R2_MATCH_ILA4} "dbg_l_bus,dbg_l_stuck_or,dbg_l_arvalid,dbg_l_aresetn,dbg_l_lrst,dbg_l_stuck"]
set match_ila5 [envalias {R2_MATCH_ILA5} "dbg_wd_go_ui,dbg_wd_ack_ui,dbg_wd_intr_ui,dbg_wd_go_ok,dbg_s2mm_tdata64,dbg_s2mm_tkeep8,dbg_s2mm_tlast_w"]

puts "R3C_START tag=$tag"
puts "R3C_HOST [info hostname]"
puts "R3C_TCL: [file normalize [info script]]"
puts "R3C_LTX: $ltx"
puts "R3C_OUT_DIR: $outdir"
puts "R3C_TAG: $tag"
puts "R3C_SNAPSHOT_ONLY: $snap_only"
puts "R3C_STIM_CMD: $stim"
puts "R3C_SETTLE_MS: $settlems"
puts "R3C_PRE_MS: $prems"
puts "R3C_WAIT_MIN: $waitmin"
puts "R3C_TRIG_POSITION: $trigpos"
puts "R3C_SKIP_PRE: $skip_pre"
puts "R3C_EXPECT_ILA_COUNT: $expect_ila"
puts "R3C_TRIG_ILA0: '$trig_ila0'"
puts "R3C_TRIG_ILA3: '$trig_ila3'"
puts "R3C_TRIG_ILA4: '$trig_ila4'"
puts "R3C_TRIG_ILA5: '$trig_ila5'"
puts "R3C_MATCH_ILA0: $match_ila0"
puts "R3C_MATCH_ILA3: $match_ila3"
puts "R3C_MATCH_ILA4: $match_ila4"
puts "R3C_MATCH_ILA5: $match_ila5"

# ---------------------------------------------------------------------------
# helper procs
# ---------------------------------------------------------------------------
proc csv_rows {path} {
    set n 0
    if {[catch {
        set fh [open $path r]
        while {[gets $fh line] >= 0} { incr n }
        close $fh
    } e]} {
        return -1
    }
    return $n
}

proc str_contains {haystack needle} {
    # LITERAL case-insensitive substring test. Do NOT use string match here:
    # probe names such as dbg_l_bus[35] contain '[' ']' which string match
    # would treat as glob character classes.
    if {$needle eq ""} { return 0 }
    return [expr {[string first [string tolower $needle] [string tolower $haystack]] >= 0}]
}

proc probe_width {p} {
    set w ""
    if {![catch {set w [get_property PROBE_PORT_BIT_COUNT $p]} e]} {
        if {[string is integer -strict $w]} { return $w }
    }
    if {![catch {set w [get_property WIDTH $p]} e]} {
        if {[string is integer -strict $w]} { return $w }
    }
    return "?"
}

proc set_prop_catch {prop val obj} {
    if {[catch {set_property $prop $val $obj} e]} {
        puts "R3C_SET_WARN: $prop=$val -> $e"
    }
}

proc norm_cmp {val width} {
    set v [string trim $val]
    if {![string is integer -strict $width]} { set width 1 }
    if {[regexp {^[0-9]+'[bhdous]} $v]} { return $v }
    if {[regexp {^(eq|neq|lt|lteq|gt|gteq)[0-9]+'} $v]} { return $v }
    if {[regexp {^[RFBNLS]$} $v]} { return "eq${width}'b$v" }
    if {$v eq "1"} { return "eq${width}'b1" }
    if {$v eq "0"} { return "eq${width}'b0" }
    if {[regexp {^0[xX]([0-9a-fA-F]+)$} $v -> h]} { return "eq${width}'h$h" }
    if {[regexp {^[0-9a-fA-F]+$} $v]} { return "eq${width}'h$v" }
    return $v
}

proc probe_names {core} {
    set names {}
    foreach p [get_hw_probes -quiet -of_objects $core] {
        lappend names [get_property NAME $p]
    }
    return $names
}

proc core_stat {core} {
    set n 0
    set tot 0
    foreach p [get_hw_probes -quiet -of_objects $core] {
        set w [probe_width $p]
        if {[string is integer -strict $w]} { incr tot $w }
        incr n
    }
    return [list $n $tot]
}

proc match_core {pats assigned} {
    global cores
    set i 0
    foreach core $cores {
        if {[lsearch -exact $assigned $i] < 0} {
            foreach pat $pats {
                foreach pn [probe_names $core] {
                    if {[str_contains $pn $pat]} {
                        return [list $i $pn $pat]
                    }
                }
            }
        }
        incr i
    }
    return {}
}

proc find_probe {core pat} {
    set exact ""
    set loose ""
    foreach p [get_hw_probes -quiet -of_objects $core] {
        set pn [get_property NAME $p]
        if {[string equal -nocase $pn $pat]} { set exact $p }
        if {($loose eq "") && [str_contains $pn $pat]} { set loose $p }
    }
    if {$exact ne ""} { return $exact }
    return $loose
}

proc configure_one {core pat cmp} {
    set probe [find_probe $core $pat]
    if {$probe eq ""} {
        puts "R3C_TRIG_PROBE_MISSING: core=$core probe_pattern='$pat'"
        return ""
    }
    set pn [get_property NAME $probe]
    set wd [probe_width $probe]
    set ncmp [norm_cmp $cmp $wd]
    if {[catch {set_property TRIGGER_COMPARE_VALUE $ncmp $probe} e]} {
        puts "R3C_TRIG_SET_WARN: $pn <= $ncmp failed: $e"
        return ""
    }
    puts "R3C_TRIG_SET: core=$core probe=$pn width=$wd cmp=$ncmp"
    return $probe
}

proc arm_core {label core spec pos} {
    if {[catch {reset_hw_ila $core} e0]} {
        puts "R3C_RESET_NOTE($label): $e0"
    }
    after 200
    set_prop_catch CONTROL.TRIGGER_MODE BASIC_ONLY $core
    set_prop_catch CONTROL.TRIGGER_CONDITION AND $core
    set_prop_catch CONTROL.TRIGGER_POSITION $pos $core
    set items {}
    foreach it [split $spec ";"] {
        set it [string trim $it]
        if {$it eq ""} { continue }
        set pat ""
        set cmp "eq1'b1"
        if {[regexp {^([^=]+)=+(.*)$} $it -> p1 p2]} {
            set pat [string trim $p1]
            set cmp [string trim $p2]
        } else {
            set pat $it
        }
        if {$pat eq ""} { continue }
        set probe [configure_one $core $pat $cmp]
        if {$probe ne ""} { lappend items $probe }
    }
    if {[llength $items] == 0} {
        puts "R3C_TRIG_ARM_SKIP($label): no probe could be configured"
        return 0
    }
    if {[catch {run_hw_ila $core} e1]} {
        puts "R3C_TRIG_ARMFAIL($label): $e1"
        return 0
    }
    puts "R3C_TRIG_ARMED: $label core=$core conditions=[llength $items] position=$pos"
    return 1
}

proc grab_snapshot {label core csvbase} {
    if {[catch {reset_hw_ila $core} e0]} {
        puts "R3C_RESET_NOTE($label): $e0"
    }
    after 200
    if {[catch {run_hw_ila -trigger_now $core} e1]} {
        puts "R3C_GRAB_FAIL($label): run_hw_ila: $e1"
        return 0
    }
    after 200
    if {[catch {wait_on_hw_ila -timeout 1 $core} e2]} {
        puts "R3C_WAIT_NOTE($label): $e2"
    }
    if {[catch {set d [upload_hw_ila_data $core]} e3]} {
        puts "R3C_GRAB_FAIL($label): upload_hw_ila_data: $e3"
        return 0
    }
    if {[catch {write_hw_ila_data -force -csv_file $csvbase $d} e4]} {
        puts "R3C_GRAB_FAIL($label): write_hw_ila_data: $e4"
        return 0
    }
    set n [csv_rows "${csvbase}.csv"]
    puts "R3C_GRAB($label): OK ${csvbase}.csv rows=$n"
    return 1
}

proc grab_armed {label core csvbase} {
    global waitmin
    set wok [catch {wait_on_hw_ila -timeout $waitmin $core} e1]
    if {$wok != 0} {
        puts "R3C_TRIG_WAIT_NOTE($label): $e1"
    }
    set trig "NO_TRIGGER"
    if {$wok == 0} { set trig "TRIGGERED" }
    set tprop "?"
    catch {set tprop [get_property IS_TRIGGERED $core]}
    puts "R3C_TRIG_STATUS($label): $trig (IS_TRIGGERED=$tprop)"
    if {[catch {set d [upload_hw_ila_data $core]} e3]} {
        puts "R3C_GRAB_FAIL($label): upload_hw_ila_data: $e3"
        return [list 0 $trig]
    }
    if {[catch {write_hw_ila_data -force -csv_file $csvbase $d} e4]} {
        puts "R3C_GRAB_FAIL($label): write_hw_ila_data: $e4"
        return [list 0 $trig]
    }
    set n [csv_rows "${csvbase}.csv"]
    puts "R3C_GRAB($label): OK ${csvbase}.csv rows=$n trigger=$trig"
    return [list 1 $trig]
}

proc width_check {label actual expect} {
    if {$expect eq ""} {
        puts "R3C_WIDTH($label): actual=$actual expect=(unset) SKIP"
        return
    }
    if {[string is integer -strict $expect] && ($actual == $expect)} {
        puts "R3C_WIDTH($label): actual=$actual expect=$expect OK"
    } else {
        puts "R3C_WIDTH_WARN($label): actual=$actual expect=$expect MISMATCH (ltx/probe layout differs from pin doc; INFO only, capture still valid)"
    }
}

# ---------------------------------------------------------------------------
# sanity checks before touching the hardware
# ---------------------------------------------------------------------------
if {$ltx eq ""} {
    puts "R3C_RESULT: FAIL R2_LTX not set (point it to the archived probes ltx matching the burned bit)"
    exit 1
}
if {![file exists $ltx]} {
    puts "R3C_RESULT: FAIL ltx not found: $ltx"
    exit 1
}
file mkdir $outdir

# ---------------------------------------------------------------------------
# connect hw_server / open the target (same flow as r2_ilacap.tcl)
# ---------------------------------------------------------------------------
if {[catch {open_hw_manager} e]} { puts "R3C_OPEN_NOTE: $e" }
if {[catch {connect_hw_server -url localhost:3121} e]} { puts "R3C_CONNECT_NOTE: $e" }
if {[catch {open_hw_target} e]} { puts "R3C_TARGET_NOTE: $e" }
set dev [lindex [get_hw_devices -quiet] 0]
if {$dev eq ""} {
    puts "R3C_RESULT: FAIL no hw_device (hw_server/JTAG not connected; power-cycle or check Digilent USB-JTAG)"
    exit 1
}
current_hw_device $dev
puts "R3C_DEV: $dev"
set partid "?"
catch {set partid [get_property PART $dev]}
puts "R3C_PART: $partid"

set probe_ok 0
if {![catch {set_property PROBES.FILE $ltx $dev} e]} { set probe_ok 1 } else {
    puts "R3C_PROBES_FILE_NOTE: $e"
}
catch {set_property FULL_PROBES.FILE $ltx $dev}
catch {refresh_hw_device $dev}
if {!$probe_ok} {
    puts "R3C_RESULT: FAIL set PROBES.FILE failed (ltx does not match the burned bitstream?)"
    catch {close_hw_target}
    catch {disconnect_hw_server}
    exit 1
}
after $prems

# ---------------------------------------------------------------------------
# auto discovery: label cores by probe-name substrings (pitfall #40 item 3)
# ---------------------------------------------------------------------------
set cores [get_hw_ilas -quiet]
set ncores [llength $cores]
puts "R3C_CORE_TOTAL: $ncores"
if {$ncores == 0} {
    puts "R3C_RESULT: FAIL no ILA core found (bitstream without ILA, or ltx mismatch)"
    foreach c [get_hw_ilas -quiet] {
        foreach p [get_hw_probes -quiet -of_objects $c] {
            puts "R3C_DUMP_PROBE: $c [get_property NAME $p]"
        }
    }
    catch {close_hw_target}
    catch {disconnect_hw_server}
    exit 1
}
if {[string is integer -strict $expect_ila] && ($ncores < $expect_ila)} {
    puts "R3C_ILA_COUNT_WARN: found=$ncores expected=$expect_ila (round3b ltx has 3 cores; round3c expects 4 -- check ltx/bit pairing)"
}

set labels {ILA4 ILA5 ILA3 ILA0}
set matchers [dict create ILA4 $match_ila4 ILA5 $match_ila5 ILA3 $match_ila3 ILA0 $match_ila0]
set triggers [dict create ILA0 $trig_ila0 ILA3 $trig_ila3 ILA4 $trig_ila4 ILA5 $trig_ila5]
set core_by_label [dict create]
set label_by_core [dict create]
set assigned {}
foreach label $labels {
    set pats {}
    foreach p [split [dict get $matchers $label] ","] {
        set p [string trim $p]
        if {$p ne ""} { lappend pats $p }
    }
    set hit [match_core $pats $assigned]
    if {[llength $hit] == 0} {
        puts "R3C_LABEL_MISSING: $label (probe patterns: [dict get $matchers $label])"
        continue
    }
    set idx [lindex $hit 0]
    set pn  [lindex $hit 1]
    set pat [lindex $hit 2]
    set core [lindex $cores $idx]
    lappend assigned $idx
    dict set core_by_label $label $core
    dict set label_by_core [get_property NAME $core] $label
    puts "R3C_ILA_LABEL: $label = $core (probe '$pn' matched pattern '$pat')"
}
set extra_n 0
set i 0
foreach core $cores {
    if {[lsearch -exact $assigned $i] < 0} {
        incr extra_n
        set xl "ILAEXTRA$extra_n"
        dict set core_by_label $xl $core
        puts "R3C_ILA_LABEL: $xl = $core (unmatched extra core; captured for completeness)"
    }
    incr i
}

# ---------------------------------------------------------------------------
# probe map + width check
# ---------------------------------------------------------------------------
set width_expect [dict create ILA0 $w0 ILA3 $w3 ILA5 $w5 ILA4 $w4]
set core_bits [dict create]
dict for {label core} $core_by_label {
    set st [core_stat $core]
    set np [lindex $st 0]
    set nb [lindex $st 1]
    dict set core_bits $label $nb
    puts "R3C_PROBE_MAP: label=$label core=$core probes=$np total_bits=$nb"
    foreach p [get_hw_probes -quiet -of_objects $core] {
        set pn [get_property NAME $p]
        set wd [probe_width $p]
        puts "R3C_PROBE: $label $pn width=$wd"
    }
    if {[dict exists $width_expect $label]} {
        width_check $label $nb [dict get $width_expect $label]
    }
}

# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------
set fail_labels {}
set pre_ok {}
set post_ok {}
set trig_status [dict create]
set armed_labels {}

if {$snap_only eq "1"} {
    puts "R3C_MODE: snapshot-only (R2_SNAPSHOT_ONLY=1)"
    dict for {label core} $core_by_label {
        set base [file join $outdir "R3C_${tag}_${label}_pre"]
        if {[grab_snapshot $label $core $base]} {
            lappend pre_ok $label
            puts "R3C_CSV: $label pre ${base}.csv"
        } else {
            lappend fail_labels $label
        }
    }
    catch {close_hw_target}
    catch {disconnect_hw_server}
    if {[llength $fail_labels] == 0} {
        puts "R3C_RESULT: PASS snapshot"
        puts "R3C_DONE"
        exit 0
    }
    puts "R3C_RESULT: FAIL snapshot capture failed for: $fail_labels"
    puts "R3C_DONE"
    exit 1
}

puts "R3C_MODE: triggered (pre snapshot -> arm -> stim -> post)"
if {$skip_pre ne "1"} {
    dict for {label core} $core_by_label {
        set base [file join $outdir "R3C_${tag}_${label}_pre"]
        if {[grab_snapshot $label $core $base]} {
            lappend pre_ok $label
            puts "R3C_CSV: $label pre ${base}.csv"
        } else {
            lappend fail_labels $label
        }
    }
} else {
    puts "R3C_MODE: PRE capture skipped (R3C_SKIP_PRE=1)"
}

dict for {label core} $core_by_label {
    if {![dict exists $triggers $label]} { continue }
    set spec [dict get $triggers $label]
    if {$spec eq ""} { continue }
    if {[arm_core $label $core $spec $trigpos]} {
        lappend armed_labels $label
    } else {
        dict set trig_status $label "ARM_FAILED"
        lappend fail_labels $label
    }
}
if {[llength $armed_labels] == 0} {
    puts "R3C_TRIGGER_SUMMARY: no core armed (all trigger specs empty); POST = trigger_now snapshots"
}

if {$stim ne ""} {
    puts "R3C_STIM: $stim"
    if {[catch {exec cmd /c $stim} es]} {
        puts "R3C_STIM_NOTE: $es"
    } else {
        puts "R3C_STIM_OK"
    }
} else {
    puts "R3C_STIM: (none; waiting for an already-pending/sticky trigger condition)"
}

foreach label $armed_labels {
    set core [dict get $core_by_label $label]
    set base [file join $outdir "R3C_${tag}_${label}_post"]
    set r [grab_armed $label $core $base]
    dict set trig_status $label [lindex $r 1]
    if {[lindex $r 0]} {
        lappend post_ok $label
        puts "R3C_CSV: $label post ${base}.csv"
    } else {
        lappend fail_labels $label
    }
}

if {[llength $armed_labels] == 0} {
    after $settlems
} else {
    after 200
}
dict for {label core} $core_by_label {
    if {[lsearch -exact $armed_labels $label] >= 0} { continue }
    set base [file join $outdir "R3C_${tag}_${label}_post"]
    if {[grab_snapshot $label $core $base]} {
        lappend post_ok $label
        puts "R3C_CSV: $label post ${base}.csv"
    } else {
        lappend fail_labels $label
    }
}

catch {close_hw_target}
catch {disconnect_hw_server}

# ---------------------------------------------------------------------------
# verdict
# ---------------------------------------------------------------------------
dict for {label spec} $triggers {
    if {[dict exists $trig_status $label]} {
        puts "R3C_TRIGGER_SUMMARY: label=$label spec='$spec' status=[dict get $trig_status $label]"
    } else {
        puts "R3C_TRIGGER_SUMMARY: label=$label spec='$spec' status=SKIPPED"
    }
}
dict for {label core} $core_by_label {
    set st "ARM_FAILED"
    if {[dict exists $trig_status $label]} { set st [dict get $trig_status $label] }
    puts "R3C_TRIGGER_SUMMARY: label=$label core=$core status=$st"
}

set notrig {}
dict for {label st} $trig_status {
    if {$st ne "TRIGGERED"} { lappend notrig $label }
}
set fail_labels [lsort -unique $fail_labels]
if {[llength $fail_labels] > 0} {
    puts "R3C_RESULT: FAIL capture/arming failed for: [join $fail_labels ,]"
    puts "R3C_DONE"
    exit 1
}
if {[llength $notrig] > 0} {
    puts "R3C_RESULT: NO_TRIGGER armed but not triggered: [join $notrig ,] (CSV contains pre-trigger samples only; judgement NOT obtained)"
    puts "R3C_DONE"
    exit 2
}
puts "R3C_RESULT: PASS (pre=[llength $pre_ok] post=[llength $post_ok] cores=[dict size $core_by_label])"
puts "R3C_DONE"
exit 0
