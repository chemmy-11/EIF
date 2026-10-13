# J_B3-1 board session: download j3_soft.elf via xsct, confirm running
connect
puts "=== TARGETS RAW ==="
set raw [targets]
puts $raw
puts "=== END RAW ==="
# pick MicroBlaze #0 (id like 3), like jb1 did
set mbid 3
if {[regexp {(\d+)\s+MicroBlaze #} $raw -> n]} { set mbid $n }
puts "MB_ID: $mbid"
targets $mbid
after 500
dow D:/FPGA/prj/project_11/out/archive/b31_dma_v2_2026-10-13/j3_soft.elf
after 500
con
after 2000
puts "ELF_RUNNING"
disconnect
exit
