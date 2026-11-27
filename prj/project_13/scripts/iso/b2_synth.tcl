# =============================================================================
# b2_synth.tcl -- B2 入口缓冲丢弃触发件：隔离工程综合（软 A 单角色）
# -----------------------------------------------------------------------------
# 用法（ASCII 工作目录；先确认没有别的 vivado 进程）：
#   vivado -mode batch -source D:\prj13w\b2\prj\project_13\scripts\iso\b2_synth.tcl \
#          -notrace -log <log> -journal <jou>
#
# 关键点：
#   · 工程根由**本脚本所在位置**推出来（scripts/iso -> prj/project_13），
#     没有任何硬编码绝对路径 => 换 worktree / 换 PC 都不用改脚本。
#   · 通过 env P13_ROOT 把 build_synth_only.tcl 的 `set proj` 覆盖成本 worktree，
#     于是 open_project 打开的是 **worktree 里的 prj13.xpr**，
#     $PPRDIR/../rtl 也就解析到 worktree 的 rtl —— 主工程零改动。
#   · P13_BOARD=A：不定义 BOARD_B（= 板 A 参数组 / 软 A，PC1 物理板 B）。
#   · P13_PRE_HOOK：综合前建 vio_p2_pause（暂停控制）。
#   · P13_ILA_EXTRA：写 dcp 前挂 u_ila_8（B2 专用探针）。
# 产物：<root>/scripts/pre_impl_debug.dcp
# =============================================================================

set _sd  [file normalize [file dirname [info script]]]
set _prj [file normalize [file join $_sd .. ..]]

set ::env(P13_ROOT)      $_prj
set ::env(P13_BOARD)     A
set ::env(P13_PRE_HOOK)  [file join $_sd b2_pre_hook.tcl]
set ::env(P13_ILA_EXTRA) [file join $_sd b2_ila_ext.tcl]
# ★2026-11-27 时序裁决：第 4 次实现（ExtraPostPlacementOpt）得 WNS=-0.009 /
#   TNS=-0.069，仅差 9 ps。按"优先裁掉附加探针"的既有裁决裁掉 u_ila_8 probe2 的
#   relay_data[7:0]（8 bit 旁证），判据依赖的 pause/两槽占用/入口帧边界/drop pulse/
#   丢弃计数/relay 计数一律保留。
if {![info exists ::env(R3C_LITE_ILA)]} { set ::env(R3C_LITE_ILA) 1 }
puts "B2_ISO_SYNTH: R3C_LITE_ILA=$::env(R3C_LITE_ILA) (300MHz 域减载)"
if {![info exists ::env(P13_ILA8_LEAN)]} { set ::env(P13_ILA8_LEAN) 1 }
puts "B2_ISO_SYNTH: ILA8_LEAN=$::env(P13_ILA8_LEAN)"

puts "B2_ISO_SYNTH: root=$_prj"
puts "B2_ISO_SYNTH: board=A (BOARD_B 未定义 = 软 A 参数组)"
puts "B2_ISO_SYNTH: pre_hook=$::env(P13_PRE_HOOK)"
puts "B2_ISO_SYNTH: ila_extra=$::env(P13_ILA_EXTRA)"

source [file join $_sd .. build_synth_only.tcl]
