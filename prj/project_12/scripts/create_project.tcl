# =============================================================================
# create_project.tcl — prj12 双板互联 P1（fork 自 prj11 2026-10-24）
# 由来: prj11 收工冻结（基线 位流 F6012BA0 + ELF BA3C0220）；本工程只做两件事:
#       ① P0-02 link_ok 单核化（跨板后 B 笼无光纤, 见 rtl/aurora_mem_bridge.v 注释）
#       ② 双板 P1 链路/数据面在位流与脚本上的就绪
# 组成: 本工程 rtl/ 物理持有全部源件（fork_manifest_12.json 逐文件 SHA256 对照
#       prj11 同路径文件）；prj9 五 IP 与 prj10 的 MIG ddr4_0 仍以 **只读 import**
#       方式引用（prj9/prj10 目录冻结, 本脚本不写它们）。
# 执行单: 操作文档/阶段三_prj12_双板互联开工草案_2026-10-24 (v0.1 §4.1 P0-01)
# 用法(ASCII 工作目录; 先确认无其它 vivado 进程):
#   vivado -mode batch -source D:\FPGA\prj\project_12\scripts\create_project.tcl -notrace
# =============================================================================
set P    D:/FPGA/prj/project_12
set P9   D:/FPGA/prj/project_9
set P10  D:/FPGA/prj/project_10
set part_name xcku060-ffva1156-2-i

create_project prj12 $P/vivado -part $part_name -force

## ---- 光链路 + 内存桥 + 派生副本: 全部本工程物理持有 ----
add_files -fileset sources_1 [glob $P/rtl/*.v $P/rtl/*/*.v]
add_files -fileset sources_1 [glob $P/rtl/shared_logic/*.v]

## ---- IP: prj9 五个(import_ip 拷入工程 .srcs; 源件在冻结工程中不变) ----
import_ip $P9/ip/aurora_64b66b_0/aurora_64b66b_0.xci
import_ip $P9/ip/aurora_64b66b_0_reg_slice_0/aurora_64b66b_0_reg_slice_0.xci
import_ip $P9/ip/aurora_64b66b_0_reg_slice_2/aurora_64b66b_0_reg_slice_2.xci
import_ip $P9/ip/async_fifo_2048x8b/async_fifo_2048x8b.xci
import_ip $P9/ip/aurora_64b66b_1/aurora_64b66b_1.xci
## ---- 真 MIG(源与 prj_loop 同份; import 后改 System_Clock=No_Buffer) ----
##   原因见 prj_loop 同名脚本注释: 顶层已继承 init_clk IBUFDS, MIG 再挂内部
##   IBUFDS 即双输入缓冲非法 [Synth 8-5535]。
import_ip $P10/prj_uiclk/ip/ddr4_0/ddr4_0.xci
set_property CONFIG.System_Clock No_Buffer [get_ips ddr4_0]

## ---- 回显弹性 FIFO(prj9 同参数照抄; 未例化保留) ----
create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name fifo_80b_echo
set_property -dict [list \
    CONFIG.Fifo_Implementation {Common_Clock_Block_RAM} \
    CONFIG.Input_Data_Width {80} \
    CONFIG.Input_Depth {512} \
    CONFIG.Performance_Options {First_Word_Fall_Through} \
    CONFIG.Enable_Safety_Circuit {false} \
] [get_ips fifo_80b_echo]

generate_target all [get_ips]

## ---- 约束(prj9 全文 + L92 修正 + DDR 107 脚; prj12 未改 XDC) ----
add_files -fileset constrs_1 $P/xdc/aurora_mem_bridge.xdc

## ---- MicroBlaze 控制面 BD（幂等; 含 axi_lite_regs 模块引用） ----
source $P/scripts/create_bd_b.tcl

## ---- 顶层 ----
set_property top aurora_mem_bridge [current_fileset]
update_compile_order -fileset sources_1

puts "CREATE_DONE: top=[get_property TOP [current_fileset]]"
puts "CREATE_DONE: ips=[get_ips]"
