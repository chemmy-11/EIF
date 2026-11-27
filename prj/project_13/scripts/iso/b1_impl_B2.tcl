# b1_impl_B2.tcl -- role B, one controlled implementation optimization
# reason: B post-route WNS=-0.007 in mmcm_clkout0 (3 failing endpoints, 300 MHz).
# Change is place strategy only: probes / widths / constraints untouched.
set _sd [file normalize [file dirname [info script]]]
set ::env(P13_BOARD) B
set ::env(P12_PLACE_DIRECTIVE) ExtraTimingOpt
puts {B1_IMPL_B2_WRAPPER: board=B directive=ExtraTimingOpt}
source [file join $_sd b1_impl.tcl]
