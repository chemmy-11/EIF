# r2_ila5_capture.tcl -- round3: 抓 S2MM 写流首拍 (ILA5@ui_clk, 5 probes)
# 用法: vivado -mode batch -source r2_ila5_capture.tcl -notrace
# env: R2_LTX (ltx 路径), R2_OUT_DIR, R2_TAG, R2_TIMEOUT_S
set here [file dirname [file normalize [info script]]]
proc envval {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}
set ltx     [file normalize [envval R2_LTX ""]]
set outdir  [file normalize [envval R2_OUT_DIR $here]]
set tag     [envval R2_TAG r3]
set timeout [envval R2_TIMEOUT_S 30]
file mkdir $outdir

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices] 0]
puts "R2ILA5_DEV: $dev"
if {$ltx ne "" && [file exists $ltx]} {
    set_property PROBES.FILE $ltx $dev
    set_property FULL_PROBES.FILE $ltx $dev
    refresh_hw_device $dev
} else {
    refresh_hw_device -update_hw_probes false $dev
}
set ila ""
foreach il [get_hw_ilas -of_objects $dev] {
    if {[llength [get_hw_probes -quiet -of_objects $il -filter {NAME =~ *tdata64*}]] > 0} { set ila $il; break }
}
if {$ila eq ""} { puts "R2ILA5_ERR: ILA5(tdata64) not found"; exit 1 }
puts "R2ILA5_CORE: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "R2ILA5_PROBE: [get_property NAME $p] LEFT=[get_property LEFT_INDEX $p] RIGHT=[get_property RIGHT_INDEX $p]" }
proc setcmp {ila pat val} {
    set p [get_hw_probes -quiet -of_objects $ila -filter "NAME =~ *$pat*"]
    if {[llength $p] == 0} { puts "R2ILA5_WARN: probe $pat not found"; return 0 }
    set p [lindex $p 0]
    set_property TRIGGER_COMPARE_VALUE $val $p
    puts "R2ILA5_SET: [get_property NAME $p] <= $val"
    return 1
}
# ★2026-10-18 按官方 hw-ila-debug skill 修正:
#   - 显式 BASIC 触发模式 + AND 条件 (多个单 bit probe 的 compare 默认按 AND 合成)
#   - wait_on_hw_ila 的 -timeout 单位是【分钟】(原脚本误按秒传 30)
set ila_name [get_property NAME $ila]
set_prop_safe {prop val obj} {
    if {[catch {set_property $prop $val $obj} e]} { puts "R2ILA5_SET_WARN: $prop=$val -> $e" }
}
set_prop_safe CONTROL.TRIGGER_MODE BASIC_ONLY $ila
set_prop_safe CONTROL.TRIGGER_CONDITION AND $ila
set_prop_safe CONTROL.TRIGGER_POSITION 512 $ila
catch {set_prop_safe CONTROL.DATA_DEPTH 1024 $ila}
setcmp $ila tvalid "eq1'b1"
setcmp $ila tready "eq1'b1"
setcmp $ila tlast  "eq1'b0"
puts "R2ILA5_CFG: mode=[get_property CONTROL.TRIGGER_MODE $ila] cond=[get_property CONTROL.TRIGGER_CONDITION $ila] pos=[get_property CONTROL.TRIGGER_POSITION $ila]"
run_hw_ila $ila
puts "R2ILA5_ARMED"
set timeout_min 1
if {[string is integer -strict $timeout] && $timeout > 0} { set timeout_min $timeout }
set ok [catch {wait_on_hw_ila -timeout $timeout_min $ila} err]
puts "R2ILA5_WAIT_OK=$ok ERR=$err (timeout_min=$timeout_min)"
set data [upload_hw_ila_data $ila]
set csv [file join $outdir "R2_ila5_${tag}"]
write_hw_ila_data -csv_file $csv -force $data
puts "R2ILA5_CSV: ${csv}.csv"
close_hw_target
disconnect_hw_server
exit 0
