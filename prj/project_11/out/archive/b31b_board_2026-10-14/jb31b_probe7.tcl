# final discriminator: drain strays, wait for len==100, serve IT
connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
proc serve {slot len} {
    set sa [expr {0x00100000 + $slot*4096}]
    mwr 0x44A10000 0x4
    after 5
    set k 0
    while {$k < 300} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 1}] != 0} break; after 5; incr k }
    mwr 0x44A10000 0x1
    after 5
    set k 0
    while {$k < 300} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 1}] == 0} break; after 5; incr k }
    mwr 0x44A10018 $sa
    after 5
    mwr 0x44A10028 [expr {$len + 50}]
    set k 0; set sr 0
    while {$k < 4000} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 2}] != 0} break; after 5; incr k }
    after 150
    return $sr
}
mwr 0x44A00000 0
after 5
mwr 0x44A0000C 1
after 20
# phase 1: drain everything pending now (strays)
for {set i 0} {$i < 20} {incr i} {
    set v [mrd2 0x44A00034]
    if {[expr {($v>>25)&1}] == 0} break
    serve [expr {($v>>16)&0xff}] [expr {$v&0xffff}]
    after 50
}
puts "DRAINED rd=[mrd2 0x44A0000C] wr=[mrd2 0x44A00008]"
# phase 2: wait for len==100 (my tagged frame comes at ~+6s from script start)
set ok 0
for {set t 0} {$t < 800} {incr t} {
    set v [mrd2 0x44A00034]
    if {[expr {($v>>25)&1}] == 1} {
        set slot [expr {($v>>16)&0xff}]
        set len  [expr {$v&0xffff}]
        if {$len == 100} {
            set sr [serve $slot $len]
            puts "SERVED-MINE slot=$slot SR=[format 0x%08x $sr] ARL=[format 0x%08x [mrd2 0x44A00038]] rd=[mrd2 0x44A0000C]"
            set ok 1
            break
        } else {
            serve $slot $len      ;# stray passing through
        }
    }
    after 15
}
puts "MINE=$ok"
mwr 0x44A0000C 0
disconnect
exit
