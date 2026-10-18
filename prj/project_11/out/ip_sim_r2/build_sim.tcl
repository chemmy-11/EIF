# =============================================================================
# build_sim.tcl -- standalone Vivado 2023.1 project for the prj11 R2 AXI DMA
#                  S2MM/MM2S IP-level simulation.
#
# Run (ASCII cwd, stdout redirected to a file):
#   vivado.bat -mode batch -source build_sim.tcl -notrace \
#              -log vivado_build.log -journal vivado_build.jou > console.log 2>&1
#
# The IP configuration mirrors D:/FPGA/prj/project_11/scripts/create_bd_b.tcl
# line 110-111 (axi_dma:7.1) plus the defaults resolved in the R2 BD
# (mb_ctrl_axi_dma_0_0.xci): direct register mode, 512-bit MM/stream,
# S2MM burst 16, DRE off, store-and-forward on.
# =============================================================================
set root D:/FPGA/prj/project_11/out/ip_sim_r2
set proj $root/proj

file mkdir $root/logs

create_project -force ip_sim_r2 $proj -part xcku060-ffva1156-2-i

create_ip -name axi_dma -vendor xilinx.com -library ip -version 7.1 -module_name axi_dma_0
set_property -dict [list \
    CONFIG.C_INCLUDE_MM2S {1} \
    CONFIG.C_INCLUDE_S2MM {1} \
    CONFIG.C_INCLUDE_SG {0} \
    CONFIG.C_M_AXI_MM2S_DATA_WIDTH {512} \
    CONFIG.C_M_AXIS_MM2S_TDATA_WIDTH {512} \
    CONFIG.C_M_AXI_S2MM_DATA_WIDTH {512} \
    CONFIG.C_S_AXIS_S2MM_TDATA_WIDTH {512} \
    CONFIG.C_SG_LENGTH_WIDTH {16} \
    CONFIG.C_INCLUDE_S2MM_DRE {0} \
    CONFIG.C_S2MM_BURST_SIZE {16} \
] [get_ips axi_dma_0]

generate_target {instantiation_template simulation} [get_ips axi_dma_0]

# ---------------------------------------------------------------- config dump
set fh [open $root/config_snapshot.txt w]
puts $fh "# prj11 R2 axi_dma IP config snapshot"
puts $fh "vivado_version=[version -short]"
puts $fh "part=[get_property PART [current_project]]"
puts $fh "ip_vlnv=[get_property IPDEF [get_ips axi_dma_0]]"
puts $fh ""
puts $fh "# CONFIG.* resolved properties (compare with create_bd_b.tcl L110-111)"
foreach prop [lsort [list_property [get_ips axi_dma_0]]] {
    if {[string match -nocase CONFIG.* $prop]} {
        puts $fh "$prop=[get_property $prop [get_ips axi_dma_0]]"
    }
}
puts $fh ""
puts $fh "# sim_1 fileset after generate_target"
foreach f [get_files -quiet -of_objects [get_filesets sim_1]] {
    puts $fh "SIMFILE $f"
}
close $fh

set veo $proj/ip_sim_r2.gen/sources_1/ip/axi_dma_0/axi_dma_0.veo
if {[file exists $veo]} {
    file copy -force $veo $root/axi_dma_0.veo
}

# ------------------------------------------------------------------- sources
add_files -fileset sim_1 -norecurse $root/rtl/axi_ram_model.sv
add_files -fileset sim_1 -norecurse $root/tb/tb_axi_dma_s2mm.sv
set_property file_type SystemVerilog [get_files $root/rtl/axi_ram_model.sv]
set_property file_type SystemVerilog [get_files $root/tb/tb_axi_dma_s2mm.sv]

set_property top tb_axi_dma_s2mm [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "SIM_TOP=[get_property top [get_filesets sim_1]]"
puts "SIM_FILES_BEGIN"
foreach f [get_files -quiet -of_objects [get_filesets sim_1]] { puts "SIMFILE $f" }
puts "SIM_FILES_END"

set_property -name {xsim.simulate.runtime} -value {1ms} -objects [get_filesets sim_1]

# --------------------------------------------------------------- simulation
# In batch mode launch_simulation runs the snapshot to $finish itself.  Do NOT
# issue "run all" afterwards: it resumes the finished snapshot and only the
# watchdog remains, which would append a bogus TEST_FAIL to the transcript.
if {[catch {launch_simulation -mode behavioral} err]} {
    puts "LAUNCH_ERROR: $err"
}
if {[catch {close_sim} err3]} {
    puts "CLOSE_SIM_NOTE: $err3"
}

# ------------------------------------------------------------------- collect
foreach pair [list \
        [list $proj/ip_sim_r2.sim/sim_1/behav/xsim/simulate.log $root/logs/simulate.log] \
        [list $proj/ip_sim_r2.sim/sim_1/behav/xsim/xelab.log   $root/logs/xelab.log] \
        [list $proj/ip_sim_r2.sim/sim_1/behav/xsim/xvlog.log   $root/logs/xvlog.log] \
        [list $proj/ip_sim_r2.sim/sim_1/behav/xsim/xvhdl.log   $root/logs/xvhdl.log] \
        [list $proj/ip_sim_r2.sim/sim_1/behav/xsim/tb_axi_dma_s2mm.vcd $root/logs/tb_axi_dma_s2mm.vcd]] {
    set src [lindex $pair 0]
    set dst [lindex $pair 1]
    if {[file exists $src]} {
        file copy -force $src $dst
        puts "COPIED $src -> $dst"
    } else {
        puts "MISSING_ARTIFACT $src"
    }
}

puts "SIM_BUILD_DONE"
quit
