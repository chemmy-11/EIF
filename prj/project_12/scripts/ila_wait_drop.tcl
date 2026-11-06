# =============================================================================
# ila_wait_drop.tcl — prj12: 监测「链路是否掉过」（比两次抓取更可靠）
#
# 背景（2026-11-06 踩坑）：`ch_up_evt / hard_err_cnt / soft_err_cnt` 这些粘滞计数
#   与 `aurora_rst` 同域复位——链路一掉，计数自己先清零，于是「两次抓取都不增长」
#   会把「掉过一次又恢复」误判成稳定。可靠做法是**武装 ILA 触发**：
#   触发条件 = `dbg_ch_up` 落下（eq0）；等待 N 秒：
#     - 超时未触发 ⇒ 这 N 秒内 ch_up 没有掉落（PASS）
#     - 触发 ⇒ 掉了（FAIL，并把触发时刻的 CSV 落盘留证）
#
# 用法:
#   vivado -mode batch -source scripts\ila_wait_drop.tcl -tclargs ^
#       <hw_server_url> <cable_serial|-> <out_csv_if_drop> <ltx> <wait_seconds>
#   例: -tclargs localhost:3121 210512180081 out\ila_drop.csv scripts\probes.ltx 300
#
# 判据行：STABLE_TIMEOUT（PASS，exit 0）/ DROP_DETECTED（FAIL，exit 1）
# =============================================================================
set url    [lindex $argv 0]
set cable  [lindex $argv 1]
set out    [lindex $argv 2]
set ltx    [lindex $argv 3]
set wait   [lindex $argv 4]

if {$url eq "" || $out eq "" || $ltx eq "" || $wait eq ""} {
    error "usage: -tclargs <url> <cable|-> <out_csv> <ltx> <wait_seconds>"
}
if {![file exists $ltx]} { error "ltx not found: $ltx" }

open_hw_manager
connect_hw_server -url $url
set targets [get_hw_targets]
set tgt [lindex $targets 0]
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
if {$ila eq ""} { error "no ILA with dbg_ch_up (P1 bitstream not loaded?)" }
current_hw_ila $ila
puts "ARM_ILA: $ila  wait=${wait}s  trigger=dbg_ch_up ne1 (== ch_up fell)"

set p [get_hw_probes -quiet dbg_ch_up -of_objects $ila]
if {[llength $p] != 1} { error "dbg_ch_up probe not uniquely found" }
set_property TRIGGER_COMPARE_VALUE ne1 $p
run_hw_ila $ila

if {[catch {wait_on_hw_ila -timeout $wait $ila} emsg]} {
    puts "STABLE_TIMEOUT: no dbg_ch_up drop within ${wait}s"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 0
}

# 触发 = ch_up 掉过
set data [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file $out $data
puts "DROP_DETECTED: dbg_ch_up fell within ${wait}s  csv=$out"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 1
