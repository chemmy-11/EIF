# b1_synth_B.tcl -- role B synthesis (P13_BOARD=B -> verilog_define BOARD_B)
set _sd [file normalize [file dirname [info script]]]
set ::env(P13_BOARD) B
puts {B1_SYNTH_B_WRAPPER: board=B}
source [file join $_sd b1_synth.tcl]
