# E round under JTAG: watch several served frames' {pending len, emit len, emit byte0}
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
    after 60
}
mwr 0x44A00000 0
after 5
mwr 0x44A0000C 1
after 20
for {set i 0} {$i < 5} {incr i} {
    set v 0
    for {set t 0} {$t < 300} {incr t} {
        set v [mrd2 0x44A00034]
        if {[expr {($v>>25)&1}] == 1} break
        after 10
    }
    if {[expr {($v>>25)&1}] == 0} { puts "no pending"; break }
    set slot [expr {($v>>16)&0xff}]
    set len  [expr {$v&0xffff}]
    serve $slot $len
    set e [mrd2 0x44A0003C]
    puts "FRAME#$i pending_len=$len emit=[format 0x%08x $e] (emit.len=[expr {($e>>16)&0xffff}] emit.slot=[expr {($e>>8)&0xff}] byte0=[format 0x%02x [expr {$e&0xff}]])"
}
mwr 0x44A0000C 0
disconnect
exit
