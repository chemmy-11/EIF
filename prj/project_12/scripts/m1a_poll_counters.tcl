# =============================================================================
# m1a_poll_counters.tcl -- prj12 M1-A-6: 单会话轮询 3 个 ILA 核，输出合并计数 CSV
#
# 为什么要它（2026-11-12 实测）：
#   1) A-6 要"每注入一种坏帧，看各计数器分别怎么动"，而计数器分散在 3 个 ILA 核里
#      （link / mem-ui / mem-user）。用 ila_capture_any.tcl 每核开一次 Vivado，
#      5 种模式 × 3 核 = 15 次启动 ≈ 15 min，不可接受。
#      本脚本在**同一个 hw_server 会话**里轮流 trigger_now 三个核，一次跑完。
#   2) 附带解决"对齐"问题：每行都带 elapsed 秒，注入方只要记录自己动手的时刻，
#      就能把"哪个计数器在第几秒跳了"对上。
#
# 用法:
#   vivado -mode batch -source scripts\m1a_poll_counters.tcl -tclargs ^
#       <hw_server_url> <cable_serial|-> <out_csv> <ltx> <total_seconds> <interval_seconds>
#
# 输出列（全部为十进制）:
#   t_s, link_ok,ch_up,lane_up,pll,rst,hard,soft,evt,hcnt,scnt,
#   pk_frames,up_frames,pfwd_wr,prev_wr,
#   mem_wm,mem_wr_frm,mem_rd_frm,mem_stall,mem_len_err,mem_ost,
#   mem_u_wr,mem_u_rd,mem_u_drop,mem_ost_s,s2mm_reqpend,wr_fault
#
# 退出码: 0 = 正常跑完；1 = 有核没找到
# =============================================================================
set url      [lindex $argv 0]
set cable    [lindex $argv 1]
set outcsv   [lindex $argv 2]
set ltx      [lindex $argv 3]
set total    [lindex $argv 4]
set interval [lindex $argv 5]
if {$url eq "" || $outcsv eq "" || $ltx eq "" || $total eq "" || $interval eq ""} {
    error "usage: -tclargs <url> <cable|-> <out_csv> <ltx> <total_seconds> <interval_seconds>"
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

# 按"独有探针"定位三个核
proc find_ila {dev probe} {
    set hit ""
    foreach i [get_hw_ilas -of_objects $dev] {
        if {[llength [get_hw_probes -quiet $probe -of_objects $i]] >= 1} { set hit $i }
    }
    return $hit
}
set ila_link [find_ila $dev dbg_ch_up]
set ila_ui   [find_ila $dev dbg_mem_wr_frm]
set ila_user [find_ila $dev dbg_mem_u_wr]
puts "POLL_CORES: link=$ila_link ui=$ila_ui user=$ila_user"
if {$ila_link eq "" || $ila_ui eq "" || $ila_user eq ""} {
    puts "POLL_ERR: missing core (link/ui/user)"
    close_hw_target; disconnect_hw_server; close_hw_manager
    exit 1
}

# 抓一次并返回该核 CSV 的最后一个数据行（split by comma）
proc snap {ila tmpcsv} {
    current_hw_ila $ila
    run_hw_ila -trigger_now $ila
    wait_on_hw_ila $ila
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -force -csv_file $tmpcsv $data
    set fh [open $tmpcsv r]
    set txt [read $fh]
    close $fh
    set last ""
    foreach ln [split $txt "\n"] { if {[string trim $ln] ne ""} { set last [string trim $ln] } }
    return [split $last ","]
}

set tmpdir [file dirname $outcsv]
set lc "$tmpdir/.poll_link.csv"
set uc "$tmpdir/.poll_ui.csv"
set rc "$tmpdir/.poll_user.csv"

set fh [open $outcsv w]
puts $fh "t_s,link_ok,ch_up,lane_up,pll,rst,hard,soft,evt,hcnt,scnt,pk_frames,up_frames,pfwd_wr,prev_wr,mem_wm,mem_wr_frm,mem_rd_frm,mem_stall,mem_len_err,mem_ost,mem_u_wr,mem_u_rd,mem_u_drop,mem_ost_s,s2mm_reqpend,wr_fault"
flush $fh

set t0 [clock seconds]
set n 0
while {([clock seconds] - $t0) < $total} {
    set L [snap $ila_link $lc]
    set U [snap $ila_ui   $uc]
    set R [snap $ila_user $rc]
    if {[llength $L] < 17 || [llength $U] < 15 || [llength $R] < 14} {
        puts "POLL_ERR: short row L=[llength $L] U=[llength $U] R=[llength $R]"
        break
    }
    # link: 3=link_ok 4=ch_up 5=lane 6=pll 7=hard 8=soft 9=evt 10=hcnt 11=scnt 12=pk 13=up 14=pfwd 15=prev 16=rst
    # ui  : 4=mem_wm 5=wr_frm 6=rd_frm 7=stall 8=len_err 9=ost
    # user: 3=mem_u_wr 4=mem_u_rd 5=mem_u_drop 7=ost_s 10=reqpend 11=wr_fault
    set row [list [expr {[clock seconds]-$t0}] \
        [lindex $L 3] [lindex $L 4] [lindex $L 5] [lindex $L 6] [lindex $L 16] \
        [lindex $L 7] [lindex $L 8] [lindex $L 9] [lindex $L 10] [lindex $L 11] \
        [lindex $L 12] [lindex $L 13] [lindex $L 14] [lindex $L 15] \
        [lindex $U 4] [lindex $U 5] [lindex $U 6] [lindex $U 7] [lindex $U 8] [lindex $U 9] \
        [lindex $R 3] [lindex $R 4] [lindex $R 5] [lindex $R 7] [lindex $R 10] [lindex $R 11]]
    puts $fh [join $row ","]
    flush $fh
    incr n
    puts "SAMPLE t=[lindex $row 0]s pfwd=[lindex $L 14] pk=[lindex $L 12] mwr=[lindex $U 5] len_err=[lindex $U 8] u_drop=[lindex $R 5]"
    after [expr {$interval * 1000}]
}
close $fh
puts "POLL_DONE: samples=$n elapsed=[expr {[clock seconds]-$t0}]s csv=$outcsv"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
