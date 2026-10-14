# B3-1b probe: engine bit via Lite, then layer-by-layer state
connect
set mbid 3
targets $mbid
after 300
proc mrd2 {a} { set t [mrd -value $a]; return [mrd -value $a] }   ;# 双读 (坑 #39)
puts "REQ(0x34) before: [mrd2 0x44A00034]"
puts "ARL(0x38) before: [mrd2 0x44A00038]"
mwr 0x44A0000C 1
after 10
set v [mrd2 0x44A00034]
puts "REQ(0x34) after engine=1: [format 0x%08x $v]  (bit24 engine = [expr {($v>>24)&1}])"
disconnect
exit
