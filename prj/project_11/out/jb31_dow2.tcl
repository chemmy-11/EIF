# J_B3-1: download new ELF (09ac8ac7, rd_reg double-read) and re-run smoke via UART D
connect
set mbid 3
targets $mbid
after 300
stop
after 200
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
after 1000
puts "NEW_ELF_RUNNING"
disconnect
exit
