# =============================================================================
# read_link_health.tcl — 读 prj13 决策 C 的链路丢失粘滞告警（VIO u_vio_link）
#
# 用法:
#   vivado -mode batch -source read_link_health.tcl -tclargs \
#          <hw_server_url> <cable_serial|-> <ltx> <board> [seq]
#   例: -tclargs localhost:3121 210512180081 probes_C_A_b6df1075.ltx A 7
#
# 输出（每次成功刷新一行，并立即 flush）:
#   LINK_HEALTH <board> <timestamp> <seq> <ui_rst_n> <calib> <armed> <down> <sticky>
# 失败（统一，不允许"沿用上次样本"）:
#   UNKNOWN <board> <reason>
#
# 设计要点（对应 结论_prj13_FIFO复位补丁去留_2026-11-20.md §4.2）:
#   · 每次现读，refresh_hw_vio **不加 -quiet**，刷新异常必须暴露
#   · 目标 / VIO 核 / 每个探针都必须**唯一**命中，多命中即 UNKNOWN
#   · 只接受二值（0/1）；读到 x/z/空/超时一律 UNKNOWN
#   · 不复用上一轮缓冲，历史样本不得当新读数
#   · 不走 UART/AXI-Lite 邮箱（链路复位或 user 时钟停摆时邮箱可能等不到应答）
#
# 探针顺序硬绑定（与 rtl/aurora_mem_bridge.v 的 u_vio_link 实例一致，勿改序）:
#   probe_in0 = ui_rst_n   probe_in1 = calib   probe_in2 = armed
#   probe_in3 = down       probe_in4 = sticky
# =============================================================================

set PROBE_ORDER {probe_in0 probe_in1 probe_in2 probe_in3 probe_in4}
set PROBE_LABEL {ui_rst_n calib armed down sticky}
# 网名兜底：硬件对象名可能是端口名（probe_inN）也可能是网名，只在板上才知道。
# 两级查找：先按端口名，再按网名；两级都必须唯一命中，否则 UNKNOWN。
set PROBE_NETNAME {dbg_link_ui_rst_n dbg_link_calib_ui dbg_link_armed_ui dbg_link_down_ui dbg_link_lost_sticky_ui}

proc emit_unknown {board reason} {
    puts "UNKNOWN $board $reason"
    flush stdout
    exit 2
}

set url    [lindex $argv 0]
set cable  [lindex $argv 1]
set ltx    [lindex $argv 2]
set board  [expr {[lindex $argv 3] eq "" ? "?" : [lindex $argv 3]}]
set seq    [expr {[lindex $argv 4] eq "" ? "-" : [lindex $argv 4]}]

if {$url eq "" || $ltx eq "" || $ltx eq "-"} {
    puts "UNKNOWN $board usage: -tclargs <url> <cable|-> <ltx> <board> \[seq\]"
    flush stdout
    exit 2
}
if {![file exists $ltx]} {
    puts "UNKNOWN $board ltx_not_found:$ltx"
    flush stdout
    exit 2
}

# ---- 连接（与 ila_capture_any.tcl 同一套路）----
if {[catch {
    open_hw_manager
    connect_hw_server -url $url
} e]} { emit_unknown $board "connect_failed:$e" }

if {[catch {
    set targets [get_hw_targets]
    if {$cable ne "" && $cable ne "-"} {
        set sel [get_hw_targets -quiet *$cable*]
        if {[llength $sel] != 1} { error "cable_select_not_unique(*$cable*) -> $sel" }
        set tgt [lindex $sel 0]
    } else {
        if {[llength $targets] != 1} { error "target_not_unique -> $targets" }
        set tgt [lindex $targets 0]
    }
    current_hw_target $tgt
    open_hw_target
} e]} { emit_unknown $board "target_failed:$e" }

if {[catch {
    set devs [get_hw_devices]
    if {[llength $devs] != 1} { error "device_not_unique -> $devs" }
    set dev [lindex $devs 0]
    current_hw_device $dev
    set_property PROBES.FILE     $ltx $dev
    set_property FULL_PROBES.FILE $ltx $dev
    refresh_hw_device $dev
} e]} { emit_unknown $board "device_failed:$e" }

# ---- 定位唯一的 VIO 核 ----
if {[catch {
    set vios [get_hw_vios -of_objects $dev]
} e]} { emit_unknown $board "get_hw_vios_failed:$e" }
# 多核时按 INSTANCE_NAME 收窄到 u_vio_link；该属性在 2023.1 是否可用未在板上验证，
# 因此只在"多核"时尝试，且失败不影响单核情形。
if {[llength $vios] > 1} {
    if {![catch {
        set f [get_hw_vios -quiet -of_objects $dev -filter {INSTANCE_NAME =~ *u_vio_link*}]
    }]} {
        if {[llength $f] == 1} { set vios $f }
    }
}
if {[llength $vios] != 1} {
    emit_unknown $board "vio_not_unique -> [llength $vios] core(s): $vios"
}
set vio [lindex $vios 0]
# 注意：Vivado 2023.1 **没有 current_hw_vio 命令**（2026-11-20 实测 info commands=0），
# 不要照搬新版文档里的 current_hw_vio $vio —— refresh/get_hw_probes 直接收对象即可。
if {[llength [info commands current_hw_vio]] > 0} { current_hw_vio $vio }

# ---- 现读一次（不 -quiet，异常必须暴露）----
if {[catch {
    refresh_hw_vio $vio
} e]} { emit_unknown $board "refresh_hw_vio_failed:$e" }

# ---- 逐探针读值，要求唯一且二值 ----
set vals {}
set idx 0
foreach pn $PROBE_ORDER {
    set netn [lindex $PROBE_NETNAME $idx]
    incr idx
    # 两级查找：端口名优先，找不到再按网名
    set p ""
    foreach cand [list $pn $netn] {
        if {[catch {
            set hits [get_hw_probes -quiet $cand -of_objects $vio]
        } e]} { emit_unknown $board "probe_query_failed($cand):$e" }
        if {[llength $hits] == 1} { set p [lindex $hits 0]; break }
        if {[llength $hits] > 1} { emit_unknown $board "probe_not_unique($cand) -> [llength $hits]" }
    }
    if {$p eq ""} { emit_unknown $board "probe_not_found($pn|$netn)" }
    if {[catch {
        set v [get_property INPUT_VALUE $p]
    } e]} { emit_unknown $board "probe_read_failed($pn):$e" }
    set v [string trim $v]
    if {$v ni {0 1}} {
        emit_unknown $board "probe_not_binary($pn) -> '$v'"
    }
    lappend vals $v
}

set ts [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]
puts "LINK_HEALTH $board $ts $seq [lindex $vals 0] [lindex $vals 1] [lindex $vals 2] [lindex $vals 3] [lindex $vals 4]"
flush stdout
exit 0
