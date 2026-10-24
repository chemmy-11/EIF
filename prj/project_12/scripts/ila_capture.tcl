# =============================================================================
# ila_capture.tcl — prj12 P1: 单板 ILA 快照抓取（默认 u_ila_6 = 单核链路健康）
# 用法(Vivado hw_manager, batch):
#   vivado -mode batch -source scripts/ila_capture.tcl -tclargs ^
#       <hw_server_url> <cable_serial|-> <out_csv> [trigger_probe]
#   例(立即抓, 不设触发):
#     -tclargs localhost:3121 210512180081 D:/FPGA/prj/project_12/out/ila6_A.csv
#   例(等 hard_err 上升):
#     -tclargs localhost:3121 210512180081 D:/FPGA/prj/project_12/out/ila6_A_err.csv probe1[0]
# 说明:
#   * 探针名用 **ILA 核里的 probe 名**（probe0/probe1[...]），不是 RTL net 名；
#     u_ila_6 定义见 scripts/build_synth_only.tcl（probe0=链路态, probe1={hard_err,soft_err}）
#   * 触发值默认 eq1（错误类信号高有效）；超时 10s 后转"立即抓"以防吊死
#   * 产物: CSV + 打印 ILA 清单，供 P1-06 归档
# =============================================================================
set url   [lindex $argv 0]
set cable [lindex $argv 1]
set out   [lindex $argv 2]
set trig  [lindex $argv 3]

if {$url eq "" || $out eq ""} {
    error "usage: -tclargs <hw_server_url> <cable_serial|-> <out_csv> [trigger_probe]"
}

open_hw_manager
connect_hw_server -url $url
set targets [get_hw_targets]
puts "ILA_HW_TARGETS: $targets"
if {[llength $targets] == 0} { error "no hw_target on $url" }
set tgt [lindex $targets 0]
if {$cable ne "" && $cable ne "-"} {
    set sel [get_hw_targets -quiet *$cable*]
    if {[llength $sel] != 1} { error "cable select failed: *$cable* -> $sel (all=$targets)" }
    set tgt [lindex $sel 0]
}
current_hw_target $tgt
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
puts "ILA_HW_DEVICE: $dev"

set ilas [get_hw_ilas -of_objects $dev]
puts "ILA_LIST: $ilas"
if {[llength $ilas] == 0} { error "no ILA in device (bitstream 是否带 ILA? 是否 P12_SKIP_ILA6=1 构建?)" }

set ila ""
foreach i $ilas {
    if {[string match "*ila_6*" $i]} { set ila $i }
}
if {$ila eq ""} {
    puts "ILA6_NOT_FOUND: fallback to [lindex $ilas 0]（旧位流/回退构建时）"
    set ila [lindex $ilas 0]
}
current_hw_ila $ila
puts "ILA_SELECTED: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "ILA_PROBE: $p" }

if {$trig ne ""} {
    set p [get_hw_probes -quiet $trig -of_objects $ila]
    if {[llength $p] != 1} {
        puts "ILA_TRIGGER_SKIP: probe '$trig' not uniquely found ([llength $p]) -> 立即抓"
        run_hw_ila -trigger_now $ila
    } else {
        puts "ILA_TRIGGER: $trig <= eq1"
        if {[catch {set_property TRIGGER_COMPARE_VALUE eq1 $p} e]} { puts "ILA_TRIGGER_CFG_ERR: $e" }
        if {[catch {run_hw_ila $ila; wait_on_hw_ila -timeout 10 $ila} e2]} {
            puts "ILA_TRIGGER_TIMEOUT: $e2 -> 立即抓"
            run_hw_ila -trigger_now $ila
        }
    }
} else {
    puts "ILA_TRIGGER: none (trigger_now)"
    run_hw_ila -trigger_now $ila
}
wait_on_hw_ila $ila
set data [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file $out $data
puts "ILA_CSV_OK: $out"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
