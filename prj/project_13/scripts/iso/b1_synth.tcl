# =============================================================================
# b1_synth.tcl -- B1 正式 V4：隔离工程综合（角色由 env P13_BOARD = A / B 选择）
# -----------------------------------------------------------------------------
# 用法（ASCII 工作目录；先确认没有别的 vivado 进程）：
#   set P13_BOARD=A
#   vivado -mode batch -source <root>\scripts\iso\b1_synth.tcl -notrace -log <log>
#
# 与 B2 的差异：
#   · 不带暂停诊断端口（正式数据面，保持生产语义）
#   · 追加 u_ila_8@eth / u_ila_9@user 两个按域拆开的分类观测核
#   · 综合前做一次**角色参数静态审计**（EIF #18 要求逐项审六个参数）
# 产物：<root>/scripts/pre_impl_debug.dcp
# =============================================================================

set _sd  [file normalize [file dirname [info script]]]
set _prj [file normalize [file join $_sd .. ..]]

set _board A
if {[info exists ::env(P13_BOARD)] && $::env(P13_BOARD) ne ""} { set _board $::env(P13_BOARD) }

set ::env(P13_ROOT)      $_prj
set ::env(P13_BOARD)     $_board
set ::env(P13_ILA_EXTRA) [file join $_sd b1_ila_ext.tcl]

puts "B1_ISO_SYNTH: root=$_prj"
puts "B1_ISO_SYNTH: board=$_board  (A = 不定义 BOARD_B / 软 A；B = -define BOARD_B / 软 B)"
puts "B1_ISO_SYNTH: ila_extra=$::env(P13_ILA_EXTRA)"

# -----------------------------------------------------------------------------
# 角色参数静态审计：直接从 rtl/aurora_mem_bridge.v 的 ifdef 段取六个参数，
# 与 EIF #18 / A1·A2 操作单的期望值逐条比对。任何不符立即 error（不进入综合）。
# -----------------------------------------------------------------------------
set _rtl [file join $_prj rtl aurora_mem_bridge.v]
set _fp  [open $_rtl r]
set _txt [read $_fp]
close $_fp

if {$_board eq "B"} {
    if {![regexp {`ifdef BOARD_B(.*?)`else} $_txt -> _seg]} { error "BOARD_B ifdef 段未找到" }
} else {
    if {![regexp {`else(.*?)`endif} $_txt -> _seg]} { error "板 A 参数段未找到" }
}

array set _got {}
foreach _p {BOARD_MAC BOARD_IP PEER_MAC PC_MAC PEER_IP PC_IP} {
    if {[regexp "parameter\\s+$_p\\s*=\\s*(\[^;\]+);" $_seg -> _v]} {
        set _got($_p) [string trim $_v]
    } else {
        error "参数 $_p 未在参数段中找到"
    }
    puts "B1_ROLE_PARAM: board=$_board $_p = $_got($_p)"
}

# 期望值（大小写与下划线无关，比值不比起写法）
array set _expA {
    BOARD_MAC 020000000A01  BOARD_IP 10.10.0.11  PEER_MAC A82BDD76DFA2
    PC_MAC    083C03A02696  PEER_IP 10.10.0.2   PC_IP    10.10.0.1
}
array set _expB {
    BOARD_MAC 020000000B01  BOARD_IP 10.10.0.12  PEER_MAC 083C03A02696
    PC_MAC    A82BDD76DFA2  PEER_IP 10.10.0.1   PC_IP    10.10.0.2
}
if {$_board eq "B"} { array set _exp [array get _expB] } else { array set _exp [array get _expA] }

proc _norm_mac {v} { return [string toupper [string map {_ "" ' "" h "" H ""} $v]] }
proc _norm_ip  {v} {
    # {8'd10,8'd10,8'd0,8'd11} -> 10.10.0.11
    set nums [regexp -all -inline {8'd([0-9]+)} $v]
    set out {}
    foreach {m n} $nums { lappend out $n }
    if {[llength $out] == 4} { return [join $out .] }
    return $v
}

set _bad {}
foreach _p {BOARD_MAC PEER_MAC PC_MAC} {
    set _g [_norm_mac $_got($_p)]
    set _e $_exp($_p)
    if {![string match "*$_e*" $_g]} { lappend _bad "$_p got=$_got($_p) exp=$_e" }
}
foreach _p {BOARD_IP PEER_IP PC_IP} {
    set _g [_norm_ip $_got($_p)]
    set _e $_exp($_p)
    if {$_g ne $_e} { lappend _bad "$_p got=$_g exp=$_e" }
}
if {[llength $_bad] > 0} {
    foreach _b $_bad { puts "B1_ROLE_PARAM_MISMATCH: $_b" }
    error "B1 角色参数审计失败（board=$_board）：[join $_bad {; }]"
}
puts "B1_ROLE_AUDIT_OK: board=$_board 六个参数与期望一致（GE1 业务口 / 本板直连 PC / 对端 PC）"

source [file join $_sd .. build_synth_only.tcl]
