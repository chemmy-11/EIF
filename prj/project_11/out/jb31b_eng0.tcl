connect
targets 3
after 200
mwr 0x44A0000C 0
after 10
puts "REQ after engine=0: [mrd -value 0x44A00034]"
disconnect
exit
