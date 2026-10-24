# =============================================================================
# burn_one.tcl — prj12 双板烧录: 单板「位流 + ELF」成对烧写（xsct）
# fork 自 prj11 out/jb31b_burn_pair.tcl（2026-10-22 已上板验证的配方），prj12 新增:
#   1. arg0 = hw_server URL（默认 localhost:3121；两板共用同一个 hw_server 时也用它）
#   2. arg3 = JTAG 线缆序列号；给定时先用 `jtag targets -set` 选中该板所在的扫描链
#      （两块板接在同一 hw_server 下时**必须**给，否则 fpga 命令会命中"当前"那一条链）
#   3. ELF 传 "-" 只烧位流；打印 BURN_* 标记行供 twin_burn.ps1 抓判据
# 用法: xsct burn_one.tcl <url> <bit> <elf|-> [cable_serial|-]
#   例: xsct burn_one.tcl tcp:localhost:3121 out/aurora_mem_bridge.bit out/j3_soft_r2_BA3C0220.elf 210512180081
# 判据: 打印 BURN_OK；不可只凭"无 ERROR"判定成功
# =============================================================================
set url     [lindex $argv 0]
set bitfile [lindex $argv 1]
set elffile [lindex $argv 2]
set cable   [lindex $argv 3]

puts "BURN_URL: $url"
puts "BURN_BIT: $bitfile"
puts "BURN_ELF: $elffile"
puts "BURN_CABLE: $cable"
if {$url eq ""} { error "BURN_FAIL: missing hw_server url (arg0)" }
if {![file exists $bitfile]} { error "BURN_FAIL: bit not found: $bitfile" }
if {$elffile ne "-" && ![file exists $elffile]} { error "BURN_FAIL: elf not found: $elffile" }

connect -url $url
after 500
# ---- 列出 JTAG 线缆（level==0），并按需选中目标板 ----
if {[catch {jtag targets -filter {level == 0}} cables]} { set cables "QUERY_ERR: $cables" }
puts "BURN_JTAG_CABLES: $cables"
if {$cable ne "" && $cable ne "-"} {
    if {[catch {jtag targets -set -nocase -filter "level == 0 && name =~ \"*$cable*\""} e]} {
        puts "BURN_CABLE_SELECT_ERR: $e"
        error "BURN_FAIL: jtag cable select failed (cable=$cable, cables=$cables); 用 jtag targets 手工选中后重跑"
    }
    puts "BURN_CABLE_SELECTED: $cable"
} else {
    puts "BURN_CABLE_SELECTED: (default/current chain)"
}
puts "BURN_TARGETS_BEGIN"
puts [targets]
puts "BURN_TARGETS_END"

fpga $bitfile
after 3000
puts "BURN_BIT_DONE"

if {$elffile ne "-"} {
    set id ""
    foreach line [split [targets] "\n"] {
        if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
    }
    if {$id eq ""} { error "BURN_FAIL: microblaze target id not found" }
    puts "BURN_MB_TARGET: $id"
    targets $id
    stop
    after 300
    dow $elffile
    after 500
    con
    puts "BURN_ELF_DONE"
}
puts "BURN_OK: url=$url bit=$bitfile elf=$elffile cable=$cable"
exit 0
