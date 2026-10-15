# no len filter: serve first pending after drain, report raw
connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
mwr 0x44A00000 0
after 5
mwr 0x44A0000C 1
after 50
set v [mrd2 0x44A00034]
puts "PENDING right after engine=1: [format 0x%08x $v] (sticky=[expr {($v>>25)&1}] slot=[expr {($v>>16)&0xff}] len=[expr {$v&0xffff}])"
mwr 0x44A0000C 0
disconnect
exit
