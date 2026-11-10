# =============================================================================
# ila_check_once.tcl -- 一次性状态检查（不开轮询，查完即退）
# 用法: run_tcl(script_path=..., background=false)  或 vivado -mode batch -source ...
# 判据: 打印 CHECK_ILAS / CHECK_DNA / CHECK_DONE，任何一项缺失即检查失败
# =============================================================================
set logf "D:/FPGA/prj/project_11/out/evidence_2026-11-10_boardB_stability/ila_check_before_load.log"
set fh [open $logf a]
fconfigure $fh -buffering line
proc mark {fh s} { puts $fh $s ; flush $fh ; puts $s }

mark $fh "CHECK_START [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
if {[catch {
    open_hw_manager
    connect_hw_server -url localhost:3121
    open_hw_target
    set dev [lindex [get_hw_devices] 0]
    current_hw_device $dev
    refresh_hw_device -update_hw_probes false $dev
    mark $fh "CHECK_DEV $dev"
    mark $fh "CHECK_DNA [get_property REGISTER.DNA $dev]"
    mark $fh "CHECK_DONE [get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $dev]"
    mark $fh "CHECK_ILAS [llength [get_hw_ilas]]"
} em]} {
    mark $fh "CHECK_FAIL [string map {\n { }} $em]"
    close $fh
    exit 1
}
mark $fh "CHECK_END"
close $fh
exit 0
