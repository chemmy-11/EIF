# B3-1b board: download j3_soft.elf (2899b5fb, 'E' cmd) and run
connect
set raw [targets]
puts "=== TARGETS ==="
puts $raw
if {[regexp {(\d+)\s+MicroBlaze \#} $raw -> n]} { set mbid $n } else { set mbid 3 }
puts "MB_ID: $mbid"
targets $mbid
after 500
stop
after 200
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
after 2000
puts "ELF_RUNNING"
disconnect
exit
