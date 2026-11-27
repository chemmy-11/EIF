# b1_impl_B.tcl -- role B implementation
set _sd [file normalize [file dirname [info script]]]
set ::env(P13_BOARD) B
puts {B1_IMPL_B_WRAPPER: board=B}
source [file join $_sd b1_impl.tcl]
