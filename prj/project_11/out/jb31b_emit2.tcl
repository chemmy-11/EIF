# controlled: engine=1 first, drain strays, wait len==142 (100B payload frame), serve, report emit
connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
proc serve {slot len} {
    set sa [expr {0x00100000 + $slot*4096}]
    mwr 0x44A10000 0x4
    after 4
    set k 0
    while {$k < 300} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 1}] != 0} break; after 4; incr k }
    mwr 0x44A10000 0x1
    after 4
    set k 0
    while {$k < 300} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 1}] == 0} break; after 4; incr k }
    mwr 0x44A10018 $sa
    after 4
    mwr 0x44A10028 [expr {$len + 8}]
    set k 0; set sr 0
    while {$k < 4000} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 2}] != 0} break; after 4; incr k }
    after 200
}
mwr 0x44A00000 0
after 5
mwr 0x44A0000C 1
after 20
# drain current pending strays
for {set i 0} {$i < 20} {incr i} {
    set v [mrd2 0x44A00034]
    if {[expr {($v>>25)&1}] == 0} break
    serve [expr {($v>>16)&0xff}] [expr {$v&0xffff}]
    after 30
}
puts "DRAINED"
# wait for the 142B frame (~+6s)
set ok 0
for {set t 0} {$t < 900} {incr t} {
    set v [mrd2 0x44A00034]
    if {[expr {($v>>25)&1}] == 1} {
        set len [expr {$v&0xffff}]
        set slot [expr {($v>>16)&0xff}]
        if {$len == 142} {
            serve $slot $len
            set e [mrd2 0x44A0003C]
            puts "SERVED slot=$slot len=142 EMIT=[format 0x%08x $e] (len=[expr {($e>>16)&0xffff}] slot=[expr {($e>>8)&0xff}] b0=[format 0x%02x [expr {$e&0xff}]])"
            set ok 1
            break
        } else {
            serve $slot $len
        }
    }
    after 12
}
puts "MINE=$ok"
mwr 0x44A0000C 0
disconnect
exit
