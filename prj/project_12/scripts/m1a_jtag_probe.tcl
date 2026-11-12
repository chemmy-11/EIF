# m1a_jtag_probe.tcl -- read-only MicroBlaze state + firmware vars (no writes)
connect -url tcp:localhost:3121
puts "== targets =="
targets
targets -set -filter {name =~ "*MicroBlaze*"}
puts "MB_TARGET: [targets -filter {name =~ \"*MicroBlaze*\"}]"
puts "PC_A: [rrd pc]"
puts "PC_B: [rrd pc]"
puts "G_DMA_MODE: [mrd 0x54D4]"
puts "G_WR_LAST_TOGGLE: [mrd 0x5CF0]"
puts "PROBE_DONE"
exit
