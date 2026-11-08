# =============================================================================
# write_cfgmem.tcl -- prj13 P1-7  QSPI flash image build / backup / programming
# -----------------------------------------------------------------------------
# ONE script, three modes, selected by the first -tclargs word.  Keeping the Tcl
# in a single file means it can be syntax-gated offline with the kit's Tcl gate
# (tools/tcl-check.ps1, Tcl 8.5.14) before any board is involved.
#
# Usage (Vivado batch, ASCII working directory, no other Vivado session alive):
#   vivado -mode batch -source scripts/write_cfgmem.tcl -notrace -tclargs ^
#       build   <bit> <mcs> <size_mb> <interface> [compress]
#   vivado -mode batch -source scripts/write_cfgmem.tcl -notrace -tclargs ^
#       backup  <out_file> <size_mb> <interface> <flash_part> [hw_server] [cable]
#   vivado -mode batch -source scripts/write_cfgmem.tcl -notrace -tclargs ^
#       program <mcs> <size_mb> <interface> <flash_part> [hw_server] [cable]
#
#   e.g. -tclargs build D:/FPGA/prj/project_13/out/aurora_mem_bridge.bit \
#                      D:/FPGA/prj/project_13/out/aurora_mem_bridge_ku060.mcs \
#                      16 SPIx4
#
# Measured/reference numbers this script is built around (2026-11-08):
#   aurora_mem_bridge.bit  = 10,302,552 bytes  (P1 baseline C856BA83, prj12)
#   B1 candidate bit       = 10,636,592 bytes  (b1_E9BE2B14)
#   N25Q128 flash          = 128 Mbit = 16,777,216 bytes
#   -> the raw .bit fits with ~5.7-6.5 MB headroom; compression is optional, not
#      required.  The .mcs TEXT file is ~2.81x the payload (45 chars per 16-byte
#      record) => ~29 MB on the host disk, which is irrelevant to the flash.
#
# Marker lines (judge by these, never by "no ERROR in the log"):
#   CFGMEM_PARTS_LISTED / CFGMEM_BUILD_OK / CFGMEM_BUILD_FAIL
#   CFGMEM_BACKUP_OK / CFGMEM_BACKUP_UNSUPPORTED / CFGMEM_BACKUP_FAIL
#   CFGMEM_PROGRAM_OK / CFGMEM_PROGRAM_FAIL
#   FLASH_BOOT_ISSUED
#
# ERROR CONTRACT: every failure path prints the *_FAIL marker and exits non-zero.
# =============================================================================

set mode [lindex $argv 0]

if {$mode eq ""} {
    puts "CFGMEM_BUILD_FAIL: usage: -tclargs build|backup|program ..."
    exit 2
}

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
proc cfgmem_say {msg} {
    puts "CFGMEM: $msg"
}

proc cfgmem_check_part {part_name} {
    # The cfgmem part string must match one of get_cfgmem_parts exactly; print the
    # whole list so the operator can correct the argument from the log.
    set all [get_cfgmem_parts]
    puts "CFGMEM_PARTS_LISTED: [llength $all]"
    foreach p $all {
        puts "CFGMEM_PART: $p"
    }
    set sel [get_cfgmem_parts -quiet $part_name]
    if {[llength $sel] == 0} {
        puts "CFGMEM_PART_RESOLVE_FAIL: '$part_name' matched nothing above"
        return ""
    }
    return [lindex $sel 0]
}

proc cfgmem_connect {hw_server cable} {
    open_hw_manager
    if {[catch {connect_hw_server -url $hw_server} err]} {
        puts "CFGMEM_CONNECT_FAIL: $err"
        return ""
    }
    set targets [get_hw_targets]
    puts "CFGMEM_HW_TARGETS: $targets"
    if {[llength $targets] == 0} {
        puts "CFGMEM_NO_TARGET: nothing on $hw_server"
        return ""
    }
    set tgt [lindex $targets 0]
    if {$cable ne "" && $cable ne "-"} {
        set sel [get_hw_targets -quiet *$cable*]
        if {[llength $sel] != 1} {
            puts "CFGMEM_CABLE_FAIL: *$cable* -> $sel (all=$targets)"
            return ""
        }
        set tgt [lindex $sel 0]
    }
    current_hw_target $tgt
    if {[catch {open_hw_target} err]} {
        puts "CFGMEM_OPEN_TARGET_FAIL: $err"
        return ""
    }
    set dev [lindex [get_hw_devices] 0]
    current_hw_device $dev
    puts "CFGMEM_HW_DEVICE: $dev"
    return $dev
}

proc cfgmem_make_object {dev part_obj} {
    if {[catch {create_hw_cfgmem -hw_device $dev $part_obj} err]} {
        puts "CFGMEM_CREATE_FAIL: $err"
        return ""
    }
    return [current_hw_cfgmem]
}

# ===========================================================================
# MODE build : .bit -> .mcs  (host side only, no hardware touched)
# ===========================================================================
if {$mode eq "build"} {
    set bit   [lindex $argv 1]
    set mcs   [lindex $argv 2]
    set size  [lindex $argv 3]
    set iface [lindex $argv 4]
    set comp  [lindex $argv 5]

    if {$size  eq ""} { set size 16 }
    if {$iface eq ""} { set iface SPIx4 }

    if {![file exists $bit]} {
        puts "CFGMEM_BUILD_FAIL: bitstream not found: $bit"
        exit 1
    }
    set bit_bytes [file size $bit]
    set cap_bytes [expr {$size * 1024 * 1024}]
    puts "CFGMEM_IN_BIT: $bit"
    puts "CFGMEM_BIT_BYTES: $bit_bytes"
    puts "CFGMEM_FLASH_BYTES: $cap_bytes"
    if {$bit_bytes > $cap_bytes} {
        puts "CFGMEM_BUILD_FAIL: bitstream ($bit_bytes B) exceeds flash ($cap_bytes B)"
        exit 1
    }
    puts "CFGMEM_HEADROOM_BYTES: [expr {$cap_bytes - $bit_bytes}]"

    # loadbit offset 0x0 = the address the SPI boot ROM reads on power-up
    set lb "up 0x0 $bit"
    set cmd [list write_cfgmem -format mcs -interface $iface -size $size -loadbit $lb -force $mcs]
    if {$comp eq "compress"} {
        lappend cmd -compress
        puts "CFGMEM_COMPRESS: on"
    }
    cfgmem_say "write_cfgmem: $cmd"
    if {[catch {eval $cmd} err]} {
        puts "CFGMEM_BUILD_FAIL: $err"
        exit 1
    }
    if {![file exists $mcs]} {
        puts "CFGMEM_BUILD_FAIL: write_cfgmem returned but $mcs is missing"
        exit 1
    }
    puts "CFGMEM_MCS_BYTES: [file size $mcs]"
    puts "CFGMEM_BUILD_OK: $mcs"
    exit 0
}

# ===========================================================================
# MODE backup : read the flash back to a host file (FACTORY IMAGE SAFETY)
#   This is the only way to keep the image that is currently in the flash.  If
#   the installed Vivado has no readback_hw_cfgmem, the script says so loudly and
#   exits 3: programming must then be treated as IRREVERSIBLE for the factory
#   image (the board is still recoverable over JTAG, see docs/P1_QSPI固化方案).
# ===========================================================================
if {$mode eq "backup"} {
    set out    [lindex $argv 1]
    set size   [lindex $argv 2]
    set iface  [lindex $argv 3]
    set pname  [lindex $argv 4]
    set url    [lindex $argv 5]
    set cable  [lindex $argv 6]

    if {$size  eq ""} { set size 16 }
    if {$iface eq ""} { set iface SPIx4 }
    if {$url   eq ""} { set url localhost:3121 }
    if {$pname eq ""} { set pname n25q128-3.3v-spi-x1_x2_x4 }

    if {[llength [info commands readback_hw_cfgmem]] == 0} {
        puts "CFGMEM_BACKUP_UNSUPPORTED: this Vivado has no readback_hw_cfgmem command"
        puts "CFGMEM_BACKUP_UNSUPPORTED_ADVICE: do NOT overwrite the flash until a known-good image exists on disk"
        exit 3
    }

    set dev [cfgmem_connect $url $cable]
    if {$dev eq ""} {
        puts "CFGMEM_BACKUP_FAIL: no hardware device"
        exit 1
    }
    set part_obj [cfgmem_check_part $pname]
    if {$part_obj eq ""} {
        puts "CFGMEM_BACKUP_FAIL: flash part '$pname' not a valid cfgmem part"
        exit 1
    }
    set cfg [cfgmem_make_object $dev $part_obj]
    if {$cfg eq ""} {
        puts "CFGMEM_BACKUP_FAIL: create_hw_cfgmem failed"
        exit 1
    }
    cfgmem_say "cfgmem object: $cfg"
    if {[catch {set_property PROGRAM.FILES [list $out] $cfg} err]} {
        puts "CFGMEM_BACKUP_FAIL: cannot set PROGRAM.FILES: $err"
        exit 1
    }
    if {[catch {readback_hw_cfgmem -hw_cfgmem $cfg} err]} {
        puts "CFGMEM_BACKUP_FAIL: $err"
        exit 1
    }
    if {![file exists $out]} {
        puts "CFGMEM_BACKUP_FAIL: readback reported success but $out is missing"
        exit 1
    }
    puts "CFGMEM_BACKUP_BYTES: [file size $out]"
    puts "CFGMEM_BACKUP_OK: $out"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 0
}

# ===========================================================================
# MODE program : .mcs -> QSPI flash, then boot from flash
#   The four properties are exactly the documented pin set; PROGRAM.ERASE wipes
#   the whole device, CFG_PROGRAM writes, VERIFY reads back and compares.
# ===========================================================================
if {$mode eq "program"} {
    set mcs    [lindex $argv 1]
    set size   [lindex $argv 2]
    set iface  [lindex $argv 3]
    set pname  [lindex $argv 4]
    set url    [lindex $argv 5]
    set cable  [lindex $argv 6]

    if {$size  eq ""} { set size 16 }
    if {$iface eq ""} { set iface SPIx4 }
    if {$url   eq ""} { set url localhost:3121 }
    if {$pname eq ""} { set pname n25q128-3.3v-spi-x1_x2_x4 }

    if {![file exists $mcs]} {
        puts "CFGMEM_PROGRAM_FAIL: mcs not found: $mcs"
        exit 1
    }
    set cap_bytes [expr {$size * 1024 * 1024}]
    puts "CFGMEM_IN_MCS: $mcs"
    puts "CFGMEM_MCS_BYTES: [file size $mcs]"
    puts "CFGMEM_FLASH_BYTES: $cap_bytes"

    set dev [cfgmem_connect $url $cable]
    if {$dev eq ""} {
        puts "CFGMEM_PROGRAM_FAIL: no hardware device"
        exit 1
    }
    set part_obj [cfgmem_check_part $pname]
    if {$part_obj eq ""} {
        puts "CFGMEM_PROGRAM_FAIL: flash part '$pname' not a valid cfgmem part"
        exit 1
    }
    set cfg [cfgmem_make_object $dev $part_obj]
    if {$cfg eq ""} {
        puts "CFGMEM_PROGRAM_FAIL: create_hw_cfgmem failed"
        exit 1
    }
    cfgmem_say "cfgmem object: $cfg"

    if {[catch {set_property PROGRAM.FILES [list $mcs] $cfg} err]} {
        puts "CFGMEM_PROGRAM_FAIL: PROGRAM.FILES: $err"
        exit 1
    }
    if {[catch {set_property PROGRAM.ERASE 1 $cfg} err]} {
        puts "CFGMEM_PROGRAM_FAIL: PROGRAM.ERASE: $err"
        exit 1
    }
    if {[catch {set_property PROGRAM.CFG_PROGRAM 1 $cfg} err]} {
        puts "CFGMEM_PROGRAM_FAIL: PROGRAM.CFG_PROGRAM: $err"
        exit 1
    }
    if {[catch {set_property PROGRAM.VERIFY 1 $cfg} err]} {
        puts "CFGMEM_PROGRAM_FAIL: PROGRAM.VERIFY: $err"
        exit 1
    }
    foreach prop {PROGRAM.FILES PROGRAM.ERASE PROGRAM.CFG_PROGRAM PROGRAM.VERIFY} {
        cfgmem_say "$prop = [get_property $prop $cfg]"
    }

    if {[catch {program_hw_cfgmem -hw_cfgmem $cfg} err]} {
        puts "CFGMEM_PROGRAM_FAIL: $err"
        exit 1
    }
    puts "CFGMEM_PROGRAM_OK: $mcs"
    if {[catch {boot_hw_device $dev} err]} {
        puts "FLASH_BOOT_FAIL: $err"
        exit 1
    }
    puts "FLASH_BOOT_ISSUED: $dev"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 0
}

puts "CFGMEM_BUILD_FAIL: unknown mode '$mode' (expected build|backup|program)"
exit 2
