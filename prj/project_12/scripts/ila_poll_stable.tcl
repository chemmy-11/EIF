# =============================================================================
# ila_poll_stable.tcl — prj12: 单会话轮询 ILA，判「链路稳定 / 计数被复位」
#
# 为什么不用 ILA 触发（2026-11-06 实测）：Vivado 2023.1 的
#   `set_property TRIGGER_COMPARE_VALUE eq0/ne1` 在 1-bit 探针上报
#   `[Designutils 20-614] No apostrophe specified in string`，无法可靠武装「ch_up 落下」触发。
#   而两次抓取对比会被「计数随复位清零」骗过（掉链后又恢复 → 0==0 假 PASS）。
#
# 本脚本在**同一个 hw_server 会话**里反复 trigger_now 抓 1024 点，逐次取 ch_up / 粘滞计数：
#   * 任一次 ch_up/link_ok != 1        → DROP（掉链）
#   * 粘滞计数（pk/up/pfwd/prev）出现回退 → RESET（设计/链路被复位过）
#   * 全程 ch_up=1 且计数单调           → STABLE_OK
#
# 用法:
#   vivado -mode batch -source scripts\ila_poll_stable.tcl -tclargs ^
#       <url> <cable|-> <work_csv> <ltx> <total_seconds> <interval_seconds>
# 判据行：STABLE_OK（exit 0）/ DROP_DETECTED 或 RESET_DETECTED（exit 1）
# =============================================================================
set url      [lindex $argv 0]
set cable    [lindex $argv 1]
set workcsv  [lindex $argv 2]
set ltx      [lindex $argv 3]
set total    [lindex $argv 4]
set interval [lindex $argv 5]
if {$url eq "" || $workcsv eq "" || $ltx eq "" || $total eq "" || $interval eq ""} {
    error "usage: -tclargs <url> <cable|-> <work_csv> <ltx> <total_seconds> <interval_seconds>"
}
if {![file exists $ltx]} { error "ltx not found: $ltx" }

open_hw_manager
connect_hw_server -url $url
set tgt [lindex [get_hw_targets] 0]
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

set ila ""
foreach i [get_hw_ilas -of_objects $dev] {
    if {[llength [get_hw_probes -quiet dbg_ch_up -of_objects $i]] >= 1} { set ila $i }
}
if {$ila eq ""} { error "no ILA with dbg_ch_up" }
current_hw_ila $ila
puts "POLL_ILA: $ila  total=${total}s interval=${interval}s"

# CSV 列序（probes.ltx / ila_capture.tcl 一致）:
# Sample,SampleWindow,TRIGGER,link_ok,ch_up,lane_up,pll,hard,soft,evt,hcnt,scnt,pk,up,pfwd,prev,rst
set last_pk -1; set last_up -1; set last_pfwd -1; set last_prev -1
set n 0; set drops 0; set resets 0
set t0 [clock seconds]

proc poll_once {} {
    global ila workcsv
    run_hw_ila -trigger_now $ila
    wait_on_hw_ila $ila
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -force -csv_file $workcsv $data
    set fh [open $workcsv r]
    set lines [split [read $fh] "\n"]
    close $fh
    set last ""
    foreach ln $lines { if {[string trim $ln] ne ""} { set last $ln } }
    return [split $last ","]
}

while {([clock seconds] - $t0) < $total} {
    set v [poll_once]
    incr n
    if {[llength $v] < 17} {
        puts "POLL_ERR: bad row: $v"
        break
    }
    lassign $v _s _w _t link chup lane pll hard soft evt hcnt scnt pk up pfwd prev rst
    set tag "OK"
    if {$chup != 1 || $link != 1 || $lane != 1 || $pll != 1 || $rst != 0 || $hard != 0 || $soft != 0} {
        set tag "DROP"; incr drops
    }
    if {$last_pk >= 0 && ($pk < $last_pk || $up < $last_up || $pfwd < $last_pfwd || $prev < $last_prev)} {
        set tag "RESET"; incr resets
    }
    puts "POLL: t=[expr {[clock seconds]-$t0}]s ch_up=$chup link=$link lane=$lane pll=$pll rst=$rst hard=$hard soft=$soft pk=$pk up=$up pfwd=$pfwd prev=$prev -> $tag"
    set last_pk $pk; set last_up $up; set last_pfwd $pfwd; set last_prev $prev
    if {$tag ne "OK"} { break }
    after [expr {$interval * 1000}]
}

puts "POLL_SUMMARY: samples=$n drops=$drops resets=$resets elapsed=[expr {[clock seconds]-$t0}]s"
close_hw_target
disconnect_hw_server
close_hw_manager
if {$drops > 0} { puts "DROP_DETECTED"; exit 1 }
if {$resets > 0} { puts "RESET_DETECTED"; exit 1 }
puts "STABLE_OK"
exit 0
