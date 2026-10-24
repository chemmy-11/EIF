# =============================================================================
# burn_bit_vivado.tcl — prj12 双板烧录（P1 首选的「只烧位流」通道, Vivado hw_manager）
# 为什么首选它: 双板同时接在**一个** hw_server 下时, Vivado 的 hw_target 名字里带
#   JTAG 线缆序列号（.../xilinx_tcf/Digilent/<serial>）, 用 glob 选中某一块板是
#   确定的; 不需要在两块板之间猜"当前 target"。
# 局限: 不能下载 MicroBlaze ELF（ELF 走 xsct burn_one.tcl）。
# 用法: vivado -mode batch -source burn_bit_vivado.tcl -tclargs <url> <bit> [cable_serial|-]
#   例: -tclargs localhost:3121 D:/FPGA/prj/project_12/out/aurora_mem_bridge.bit 210512180081
# 判据: 打印 BURN_BIT_OK 且 "End of startup status: HIGH"
# =============================================================================
set url     [lindex $argv 0]
set bitfile [lindex $argv 1]
set cable   [lindex $argv 2]
if {$url eq "" || $bitfile eq ""} { error "usage: -tclargs <hw_server_url> <bit> [cable_serial|-]" }
if {![file exists $bitfile]} { error "bit not found: $bitfile" }

open_hw_manager
connect_hw_server -url $url
set all [get_hw_targets]
puts "BURN_HW_TARGETS_ALL: $all"
if {[llength $all] == 0} { error "BURN_FAIL: no hw_target on $url" }

set target [lindex $all 0]
if {$cable ne "" && $cable ne "-"} {
    set sel [get_hw_targets -quiet *$cable*]
    puts "BURN_HW_TARGET_MATCH: pattern=*$cable* matches=$sel"
    if {[llength $sel] != 1} {
        error "BURN_FAIL: cable selection ambiguous/empty (pattern=*$cable*, candidates=$all)"
    }
    set target [lindex $sel 0]
}
current_hw_target $target
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
puts "BURN_HW_DEVICE: $dev"
set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev
refresh_hw_device -update_hw_probes false $dev
puts "BURN_BIT_OK: url=$url target=$target bit=$bitfile dev=$dev"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
