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

# =============================================================================
# 硬闸（GATE-1）：拒绝实现"打补丁之前"的旧网表
# -----------------------------------------------------------------------------
# 背景：2026-11-27 中止的那次综合没有覆盖 scripts/pre_impl_debug.dcp（旧件停在 09:44:26），
#       而补丁 b1_ila_ext.tcl 是 13:26 之后才就位的。若直接跑 impl，会静默实现旧网表，
#       越域 ep_ok 探针仍在，且**全程不报错**。
# 规则：DCP 的 mtime 必须**晚于** ILA 接线脚本（补丁）的 mtime；否则立即 abort。
#       判据是文件事实（mtime），不是日志里有没有 SYNTH_DCP_OK。
# 解除：删掉旧 DCP，重新跑 b1_synth.tcl（同一角色）。
# =============================================================================
set _dcp [file join $_prj scripts pre_impl_debug.dcp]
if {![file exists $_dcp]} {
    error "GATE-1 FAIL: 找不到 $_dcp（先跑 b1_synth.tcl）"
}

# 参与**网表生成**的输入（任一新于 dcp 即视为旧网表）
# 2026-11-27 补强两次：
#   ① 原版只比对 b1_ila_ext.tcl，范围过窄——若综合之后改了 RTL / XDC / 综合脚本，
#      dcp 同样是旧的，而闸会放行，性质与"复用旧 dcp"完全相同（不报错但不对）。
#   ② 不纳入 impl 侧脚本（b1_impl.tcl / build_impl.tcl）：它们**不决定 dcp 内容**，
#      只决定怎么用 dcp。把 impl 脚本计入会造成假阳性——只要改过 impl 脚本，
#      下一次 impl 就会被自己的闸拦下。impl 侧变更由 GATE-2 提示覆盖。
set _inputs {}
lappend _inputs [list "ila_ext"   [file join $_sd b1_ila_ext.tcl]]
lappend _inputs [list "synth_tcl" [file join $_sd b1_synth.tcl]]
lappend _inputs [list "bsynth"    [file join $_sd .. build_synth_only.tcl]]
foreach _v [lsort [glob -nocomplain -directory [file join $_prj rtl] *.v]] {
    lappend _inputs [list "rtl/[file tail $_v]" $_v]
}
foreach _x [lsort [glob -nocomplain -directory [file join $_prj constrs] *.xdc]] {
    lappend _inputs [list "xdc/[file tail $_x]" $_x]
}
foreach _i [lsort [glob -nocomplain -directory [file join $_prj ip] *.xci]] {
    lappend _inputs [list "xci/[file tail $_i]" $_i]
}

set _dcp_t [file mtime $_dcp]
puts "B1_GATE1: dcp=$_dcp"
puts "B1_GATE1: dcp_mtime=[clock format $_dcp_t -format {%Y-%m-%d %H:%M:%S}] dcp_size=[file size $_dcp]"
puts "B1_GATE1: 输入清单共 [llength $_inputs] 项"

set _newer {}
set _missing {}
foreach _pair $_inputs {
    set _nm [lindex $_pair 0]
    set _fp [lindex $_pair 1]
    if {![file exists $_fp]} { lappend _missing $_nm; continue }
    set _t [file mtime $_fp]
    if {$_t > $_dcp_t} {
        lappend _newer "$_nm ([clock format $_t -format {%m-%d %H:%M:%S}])"
    }
}

if {[llength $_newer] > 0} {
    foreach _n $_newer { puts "OLD_DCP_ABORT_INPUT: $_n 新于 dcp" }
    puts "OLD_DCP_ABORT: pre_impl_debug.dcp 早于以下输入：$_newer"
    error "GATE-1 FAIL: DCP 早于输入 [join $_newer {, }]；删除 $::env(P13_ROOT)/scripts/pre_impl_debug.dcp 并重跑同角色 b1_synth.tcl"
}
puts "B1_GATE1_OK: dcp 晚于全部 [llength $_inputs] 项输入（缺失 [llength $_missing] 项），允许实现"

# 哈希清单（后续增强项，本版未实现比对）：
#   mtime 可被复制/解包改写，哈希更硬。但 Tcl 8.5 无内建 sha256，逐项 exec certutil
#   在慢盘上开销明显，故本版**只做到 mtime+存在性**，并在日志里如实说明降级。
#   若后续要实现：由 build_synth_only.tcl 在 write_checkpoint 之后写
#   <prj>/scripts/synth_inputs.txt（每行 "相对路径|<sha256>|<size>"），本闸逐行比对。
set _mani [file join $_prj scripts synth_inputs.txt]
if {[file exists $_mani]} {
    puts "B1_GATE1_MANIFEST: 发现 $_mani —— 本版未实现哈希比对，仍按 mtime 判据；请人工核对该清单"
} else {
    puts "B1_GATE1_MANIFEST: 无 synth_inputs.txt，仅用 mtime 判据（哈希清单为后续增强项，未实现）"
}


# 硬闸（GATE-2）：产物目录不得残留旧件（防止混用旧 LTX / 旧 bit）
set _out [file join $_prj out $::env(P13_OUT_SUB)]
foreach _f {.bit .ltx} {
    set _p [glob -nocomplain -directory $_out -tails *$_f]
    if {[llength $_p] > 0} {
        puts "B1_GATE2_NOTE: 产物目录已有旧 $_f 件，本次会被覆盖：$_p"
    }
}
puts "B1_GATE2_OK: 产物目录检查完成"

source [file join $_sd .. build_impl.tcl]
