# =============================================================================
# list_targets.tcl — prj12 上板第一步：**只读**列出 hw_server 下的 target/device
#   （不编程、不复位、不改任何东西；用于确认两块板都被识别 + 拿到线缆序列号）
# 用法: vivado -mode batch -source list_targets.tcl -tclargs <hw_server_url>
#   例: -tclargs localhost:3121
# 判据: 输出里应出现两条 Digilent 线缆（名字含序列号）与两个 xcku060 设备
# =============================================================================
set url [lindex $argv 0]
if {$url eq ""} { error "usage: -tclargs <hw_server_url>" }

open_hw_manager
if {[catch {connect_hw_server -url $url} emsg]} {
    puts "LIST_FAIL: cannot connect hw_server $url -> $emsg"
    puts "LIST_HINT: 先让 hw_server 在跑（打开 Vivado 的 Hardware Manager 即可拉起，或跑 <Vivado>\\bin\\unwrapped\\win64.o\\hw_server.exe -p 3121）"
    exit 1
}
set all [get_hw_targets]
puts "LIST_URL: $url"
puts "LIST_TARGETS_ALL: $all"
if {[llength $all] == 0} { error "LIST_FAIL: no hw_target on $url（USB 线/驱动/hw_server？）" }

foreach t $all {
    if {[catch {open_hw_target $t} emsg]} {
        puts "LIST_TARGET_ERR: $t -> $emsg"
        continue
    }
    current_hw_target $t
    puts "LIST_TARGET: $t"
    foreach d [get_hw_devices] {
        puts "  LIST_DEVICE: $d"
        catch {
            set id [get_property IDCODE $d]
            set prt [get_property PART $d]
            puts "  LIST_DEVICE_INFO: name=$d idcode=$id part=$prt"
        }
    }
    close_hw_target
}
disconnect_hw_server
close_hw_manager
puts "LIST_DONE"
exit 0
