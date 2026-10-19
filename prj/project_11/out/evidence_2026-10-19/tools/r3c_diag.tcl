# =============================================================================
# r3c_diag.tcl -- prj11 R2 round3c : post-wedge JTAG/LMB field read (xsct)
#
# RUN (Lead, on the board; NOT vivado and NOT run by the offline author):
#   D:\Xilinx\Vitis\2023.1\bin\xsct.bat D:\FPGA\prj\project_11\out\evidence_2026-10-19\tools\r3c_diag.tcl
#   (redirect: cmd /c "xsct.bat <this> > <evid>\R3C_diag_xsct.log 2>&1")
#   Same invocation family as out\r2_...\r2_step_diag.tcl / r2_wa_diag.tcl.
#
# WHAT IT DOES
#   1. connect hw_server, locate the MicroBlaze target (same regex as the
#      proven r2_step_diag.tcl / jb31b_burn_pair.tcl), select it
#   2. print R3C_PC_RUNNING (rrd pc while running)
#   3. stop the CPU (freeze the wedge scene), print R3C_PC_STOPPED
#   4. resolve diagnostic global symbols from the ELF symbol table (mb-nm)
#      and compare them against the offline-verified table below
#   5. read PC + g_step + g_dma_mode/g_dma_service + g_wr_last_toggle +
#      all g_wa_* snapshots from LMB (pitfall #54 discipline: every address
#      is dummy-read twice, then re-read until two consecutive reads agree)
#   6. con (resume), print R3C_PC_RESUMED
#   7. KEY=VALUE lines + R3C_DIAG_DONE
#
# SYMBOL TABLE VERIFICATION (offline, 2026-10-19, this file author)
#   ELF checked : D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
#                 size 54,224 B, SHA256 F5E0F1F3...  (live diagnostic firmware
#                 burned in round3b board session 2026-10-19 11:4x; contains
#                 g_step / g_wa_* globals added 2026-10-19)
#   command     : D:\Xilinx\Vitis\2023.1\gnu\microblaze\nt\bin\mb-nm.exe
#                 --print-size --numeric-sort --defined-only <elf>
#   LMB base    : 0x00000000 (LMB BRAM occupies the low address space; the
#                 symbol values below are absolute MicroBlaze addresses and
#                 equal the addresses already used on-board by r2_step_diag.tcl,
#                 which returned sane values: GDMA_MODE=1, G_STEP=0x0e/0x0b)
#   verified symbols (addr, nm type, size):
#     g_dma_service    0x00004508  b  4   serve_any() enable flag (static)
#     g_dma_mode       0x0000450c  b  4   1 = DMA residency service ('d' toggle)
#     g_wa_s2cr        0x00004510  B  4   S2MM_DMACR snapshot right after GO
#     g_wa_s2sr        0x00004514  B  4   S2MM_DMASR snapshot right after GO
#     g_wa_s2len       0x00004518  B  4   S2MM_LENGTH snapshot right after GO
#     g_wa_s2sr2       0x0000451c  B  4   S2MM_DMASR after pending fell (done)
#     g_wa_s2len2      0x00004520  B  4   S2MM_LENGTH after pending fell (done)
#     g_wa_wreq        0x00004524  B  4   WR_REQ  (+0x40) snapshot after GO
#     g_wa_wdbg        0x00004528  B  4   WR_DBG  (+0x44) snapshot after GO
#     g_wa_cnt         0x0000452c  B  4   number of armed write services
#     g_wa_done        0x00004530  B  4   1 = post-completion snapshot taken
#     g_step           0x00004534  B  4   PRECISE wedge step number (map below)
#     g_wr_last_toggle 0x00004538  b  4   last armed request toggle value
#     __bss_end        0x0000453c  B  -   end of .bss (sanity marker)
#
# g_step MAP (live firmware, sw/j3_soft/src/main.c, round3b/3c diagnostic build)
#    10  serve_write_once entry
#    11  after dread(R_WRDBG 0x44)        <-- observed wedge step (g_step=11)
#    12  after dread(R_WRREQ 0x40)
#    13  before S2MM_LENGTH write
#    14  after  S2MM_LENGTH write (transfer starts)
#    15  after  R_WRGO write (+0x48)
#    16  after  busy_ms(20)
#    17  after  dread(S2MM_LENGTH)
#    18  after  dread(S2MM_DMASR) then s2cr/wreq/wdbg snapshots, g_wa_cnt++
#    19  serve_write_once return
#     1  serve_any entry
#     2  after dread(REGS_BASE + 0x34) (DMA_REQ read)
#     3  no read request -> enter write service
#     9  read request present -> serve_dma_once()
#
# PITFALL #54 DISCIPLINE
#   JTAG mrd across consecutive different addresses returns lagged values.
#   rd{} below does: 2 x dummy mrd, then read up to 8 times until two
#   consecutive values agree; raw/stability flags are printed so that a
#   non-stable read can never be mistaken for a measurement.
#
# ASCII ONLY on purpose (Vivado/domain ANSI(GBK) decoding of Tcl sources).
# =============================================================================

set ELF    "D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf"
set MBNM   "D:/Xilinx/Vitis/2023.1/gnu/microblaze/nt/bin/mb-nm.exe"
set LMB_BASE 0x00000000

# offline-verified symbol table (used as fallback and as a mismatch check)
array set EXPECT {
    g_dma_service    0x00004508
    g_dma_mode       0x0000450c
    g_wa_s2cr        0x00004510
    g_wa_s2sr        0x00004514
    g_wa_s2len       0x00004518
    g_wa_s2sr2       0x0000451c
    g_wa_s2len2      0x00004520
    g_wa_wreq        0x00004524
    g_wa_wdbg        0x00004528
    g_wa_cnt         0x0000452c
    g_wa_done        0x00004530
    g_step           0x00004534
    g_wr_last_toggle 0x00004538
    __bss_end        0x0000453c
}

# ---------------------------------------------------------------------------
# symbol resolution: prefer the ELF (mb-nm), fall back to the verified table
# ---------------------------------------------------------------------------
proc load_symbols {} {
    global EXPECT MBNM ELF
    array set res {}
    foreach {k v} [array get EXPECT] { set res($k) $v }
    set used_nm 0
    if {[file exists $MBNM] && [file exists $ELF]} {
        if {[catch {
            set out [exec $MBNM --print-size --numeric-sort --defined-only $ELF]
            set used_nm 1
        } e]} {
            puts "R3C_SYMTAB_WARN: mb-nm failed: $e (using offline-verified fallback table)"
        } else {
            set n 0
            foreach line [split $out "\n"] {
                if {![regexp {^\s*([0-9a-fA-F]+)\s+(?:[0-9a-fA-F]+\s+)?([bBdD])\s+(\S+)\s*$} $line -> a t nmx]} { continue }
                set res($nmx) "0x$a"
                incr n
            }
            puts "R3C_SYMTAB_SOURCE: mb-nm ($ELF) entries=$n"
        }
    } else {
        puts "R3C_SYMTAB_WARN: mb-nm or ELF missing (mb-nm=[file exists $MBNM] elf=[file exists $ELF]); using offline-verified fallback table"
    }
    if {!$used_nm} { puts "R3C_SYMTAB_SOURCE: offline-verified fallback table" }
    return [array get res]
}

# ---------------------------------------------------------------------------
# pitfall #54 safe reader
# ---------------------------------------------------------------------------
proc rd {addr label} {
    # 2 dummy reads (discard; they may return the previous address's value)
    catch {mrd -value $addr}
    catch {mrd -value $addr}
    set prev ""
    set v ""
    set stable 0
    for {set k 0} {$k < 8} {incr k} {
        if {[catch {set v [mrd -value $addr]} e]} {
            puts "R3C_READ_FAIL: $label addr=$addr err=$e"
            return ""
        }
        if {($prev ne "") && ($v == $prev)} { set stable 1; break }
        set prev $v
    }
    set raw [format %08x [expr {$v & 0xffffffff}]]
    puts "R3C_RAW: $label addr=0x[format %08x $addr] value=$raw stable=$stable"
    return $raw
}

proc rd_sym {name label} {
    global S LMB_BASE VAL
    if {![info exists S($name)]} {
        puts "R3C_SYMBOL_MISSING: $name ($label)"
        return ""
    }
    set addr [expr {$LMB_BASE + $S($name)}]
    set v [rd $addr $label]
    if {$v ne ""} {
        set VAL($label) $v
        puts "R3C_KEY: $label=$v"
    }
    return $v
}

proc decode_step {raw} {
    set n [expr {[scan $raw %x] + 0}]
    set m {}
    array set stepmap {
        10 {serve_write_once entry}
        11 {after dread(R_WRDBG 0x44) - round3b/3c observed wedge step}
        12 {after dread(R_WRREQ 0x40)}
        13 {before S2MM_LENGTH write}
        14 {after S2MM_LENGTH write}
        15 {after R_WRGO write (+0x48)}
        16 {after busy_ms(20)}
        17 {after dread(S2MM_LENGTH)}
        18 {after dread(S2MM_DMASR) + s2cr/wreq/wdbg snapshots}
        19 {serve_write_once return}
        1  {serve_any entry}
        2  {after dread(REGS_BASE+0x34) DMA_REQ read}
        3  {no read request -> write service}
        9  {read request -> serve_dma_once()}
    }
    if {[info exists stepmap($n)]} { set m $stepmap($n) } else { set m "unknown step" }
    puts "R3C_STEP_DECODE: g_step=$n -> $m"
}

# ---------------------------------------------------------------------------
# connect + select MicroBlaze target
# ---------------------------------------------------------------------------
puts "R3C_DIAG_START"
puts "R3C_DIAG_HOST [info hostname]"
puts "R3C_DIAG_TCL: [file normalize [info script]]"
puts "R3C_DIAG_ELF: $ELF"
puts "R3C_DIAG_LMB_BASE: [format 0x%08x $LMB_BASE]"

catch {connect}
set id ""
if {[catch {set tg [targets]}]} {
    puts "R3C_DIAG_RESULT: FAIL cannot list JTAG targets (hw_server down or board unplugged)"
    exit 1
}
foreach line [split $tg "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> nid]} { set id $nid; break }
}
if {$id eq ""} {
    puts "R3C_DIAG_RESULT: FAIL no MicroBlaze target"
    puts "R3C_TARGETS_BEGIN"
    puts $tg
    puts "R3C_TARGETS_END"
    exit 1
}
puts "R3C_MB_TARGET: $id"
if {[catch {targets $id} e]} {
    puts "R3C_DIAG_RESULT: FAIL targets $id: $e"
    exit 1
}

set pcr "?"
catch {set pcr [rrd pc]}
puts "R3C_PC_RUNNING: $pcr"

if {[catch {stop} e]} {
    puts "R3C_STOP_WARN: $e"
}
after 300
set pcs "?"
catch {set pcs [rrd pc]}
puts "R3C_PC_STOPPED: $pcs"

# ---------------------------------------------------------------------------
# symbol table check (mb-nm vs offline-verified table)
# ---------------------------------------------------------------------------
array set S [load_symbols]
set sym_mismatch 0
foreach name [array names EXPECT] {
    if {![info exists S($name)]} {
        puts "R3C_SYMTAB_MISSING: $name"
        incr sym_mismatch
        continue
    }
    set a [expr {$S($name) + 0}]
    set e [expr {$EXPECT($name) + 0}]
    if {$a == $e} {
        puts "R3C_SYMTAB: $name = 0x[format %08x $a] OK"
    } else {
        puts "R3C_SYMTAB_WARN: $name = 0x[format %08x $a] but offline-verified 0x[format %08x $e] (ELF changed? re-run mb-nm and update this file; reads below use the ELF value)"
        incr sym_mismatch
    }
}
puts "R3C_SYMTAB_MISMATCH: $sym_mismatch"

# ---------------------------------------------------------------------------
# field reads (LMB, no AXI access: the AXI bus may be wedged)
# ---------------------------------------------------------------------------
array set VAL {}
rd_sym g_step           G_STEP
rd_sym g_dma_mode       GDMA_MODE
rd_sym g_dma_service    G_DMA_SERVICE
rd_sym g_wr_last_toggle G_WR_LAST_TOGGLE
rd_sym g_wa_cnt         WA_CNT
rd_sym g_wa_done        WA_DONE
rd_sym g_wa_s2cr        WA_S2CR
rd_sym g_wa_s2sr        WA_S2SR
rd_sym g_wa_s2len       WA_S2LEN
rd_sym g_wa_s2sr2       WA_S2SR2
rd_sym g_wa_s2len2      WA_S2LEN2
rd_sym g_wa_wreq        WA_WREQ
rd_sym g_wa_wdbg        WA_WDBG
rd_sym __bss_end        BSS_END

set step_raw ""
catch {set step_raw [rd_sym g_step STEP_RECHECK]}
if {$step_raw ne ""} { decode_step $step_raw }

set pcs2 "?"
catch {set pcs2 [rrd pc]}
puts "R3C_PC_STOPPED_AFTER_READS: $pcs2"

# compact one-line summary for the runbook/session log
set sumlist {}
foreach k {G_STEP GDMA_MODE G_DMA_SERVICE G_WR_LAST_TOGGLE WA_CNT WA_DONE WA_S2CR WA_S2SR WA_S2LEN WA_S2SR2 WA_S2LEN2 WA_WREQ WA_WDBG} {
    if {[info exists VAL($k)]} { lappend sumlist "$k=$VAL($k)" } else { lappend sumlist "$k=MISSING" }
}
puts "R3C_SUMMARY: [join $sumlist " "]"

set pcs2 "?"
catch {set pcs2 [rrd pc]}
puts "R3C_PC_STOPPED_AFTER_READS: $pcs2"

# resume the processor (board stays in its wedged loop if that is the state)
if {[catch {con} e]} { puts "R3C_CON_WARN: $e" }
after 300
set pcr2 "?"
catch {set pcr2 [rrd pc]}
puts "R3C_PC_RESUMED: $pcr2"

if {$sym_mismatch == 0} {
    puts "R3C_DIAG_RESULT: PASS"
} else {
    puts "R3C_DIAG_RESULT: PARTIAL (symbol table mismatch count=$sym_mismatch; re-check ELF/header addresses)"
}
puts "R3C_DIAG_DONE"
exit 0
