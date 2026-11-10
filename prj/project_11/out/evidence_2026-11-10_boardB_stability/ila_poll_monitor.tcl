# =============================================================================
# ila_poll_monitor.tcl — 板B 稳定性：ILA 存活轮询（每 interval 秒一次 JPEG 级探测器不变）
# 判据: 每次轮询读 ILA 核数 + DONE 位。ILA=0 即"复位"（本板已实测: 出厂镜像不驱动 PHY，
#       所以复位同时会伴随网口掉线，可交叉验证）。
# 用法(脱离进程树):
#   vivado -mode batch -source ila_poll_monitor.tcl -tclargs <duration_s> <interval_s> <logfile>
# 只写标记行，判进度只看日志里的 MONITOR_/T+/RESET_ 行。
# =============================================================================
set dur  [lindex $argv 0]
set ival [lindex $argv 1]
set logf [lindex $argv 2]
if {$dur  eq ""} { set dur  3600 }
if {$ival eq ""} { set ival 30 }
if {$logf eq ""} { set logf "D:/FPGA/prj/project_11/out/evidence_2026-11-10_boardB_stability/ila_poll_3600s.log" }

set fh [open $logf a]
fconfigure $fh -buffering line
proc mark {fh s} { puts $fh $s ; flush $fh ; puts $s }

set t0 [clock seconds]
mark $fh "MONITOR_START [clock format $t0 -format {%Y-%m-%d %H:%M:%S}] dur=$dur ival=$ival"

if {[catch {
    open_hw_manager
    connect_hw_server -url localhost:3121
    open_hw_target
    set dev [lindex [get_hw_devices] 0]
    current_hw_device $dev
    refresh_hw_device -update_hw_probes false $dev
    mark $fh "DEVICE $dev DNA=[get_property REGISTER.DNA $dev]"
} em]} {
    mark $fh "MONITOR_FAIL setup: [string map {\n { }} $em]"
    close $fh
    exit 1
}

set el 0
set resets 0
set errs 0
while {1} {
    set el [expr {[clock seconds] - $t0}]
    if {$el > $dur} { break }
    if {[catch {
        refresh_hw_device -update_hw_probes false $dev
        set c [llength [get_hw_ilas]]
        set done [get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $dev]
        mark $fh "T+$el ILAS=$c DONE=$done"
        if {$c == 0} { incr resets ; mark $fh "RESET_DETECTED T+$el ILAS=0 DONE=$done" }
    } em]} {
        incr errs
        mark $fh "POLL_ERR T+$el [string map {\n { }} $em]"
        catch { close_hw_target }
        catch { open_hw_target }
        catch { current_hw_device $dev }
    }
    after [expr {$ival * 1000}]
}
mark $fh "MONITOR_DONE elapsed=$el resets=$resets errors=$errs"
close $fh
exit 0
