# m1a_rst_run.tcl -- reset MicroBlaze and run (for UART boot-banner test)
connect -url tcp:localhost:3121
targets -set -filter {name =~ "*MicroBlaze #0*"}
rst -processor
con
puts "RST_RUN_DONE"
exit
