# =============================================================================
# b1_impl.tcl -- B1 正式 V4：隔离工程实现 + 位流（角色由 env P13_BOARD 选择）
# -----------------------------------------------------------------------------
# 前置：b1_synth.tcl（同 P13_BOARD）已产出 <root>/scripts/pre_impl_debug.dcp
# 产物：<root>/out/<P13_OUT_SUB>/ 下的 bit / ltx / 时序·DRC·CDC·check_timing 报告
#   P13_OUT_SUB = p13_B1_A（软 A）或 p13_B1_B（软 B）
# =============================================================================

set _sd  [file normalize [file dirname [info script]]]
set _prj [file normalize [file join $_sd .. ..]]

set _board A
if {[info exists ::env(P13_BOARD)] && $::env(P13_BOARD) ne ""} { set _board $::env(P13_BOARD) }

set ::env(P13_ROOT)     $_prj
set ::env(P13_BOARD)    $_board
set ::env(P12_SKIP_XSA) 1
# ★2026-11-27：A 角首次实现用默认 ExtraTimingOpt 得 WNS=-0.080（B1 的 ILA 合计 545 bit，
#   比 B2 的 43 bit 重得多）。B2 收口时实测 ExtraPostPlacementOpt 明显更好，故正式件改用它。
if {![info exists ::env(P12_PLACE_DIRECTIVE)]} { set ::env(P12_PLACE_DIRECTIVE) ExtraPostPlacementOpt }
puts "B1_ISO_IMPL: place_directive=$::env(P12_PLACE_DIRECTIVE)"
if {$_board eq "B"} {
    set ::env(P13_OUT_SUB) p13_B1_B
} else {
    set ::env(P13_OUT_SUB) p13_B1_A
}

puts "B1_ISO_IMPL: root=$_prj  board=$_board"
puts "B1_ISO_IMPL: outdir=$_prj/out/$::env(P13_OUT_SUB)"
puts "B1_ISO_IMPL: dcp=$_prj/scripts/pre_impl_debug.dcp"

source [file join $_sd .. build_impl.tcl]
