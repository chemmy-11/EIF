connect
targets 3
after 300
mwr 0x44A0000C 0
after 5
mwr 0x44A00000 0
after 5
puts "REQ=[mrd -value 0x44A00034] (engine bit24 should be 0)"
stop
after 200
dow D:/FPGA/prj/project_11/sw/j3_soft/Debug/j3_soft.elf
after 500
con
after 2000
puts "RECOVERED"
disconnect
exit
