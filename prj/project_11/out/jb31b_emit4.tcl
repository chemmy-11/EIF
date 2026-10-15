# engine=1, then WAIT for sticky (any len), serve it, report emit + serve ONE stray then mine
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
# wait for sticky request (up to 5s)
set got 0
for {set t 0} {$t < 250} {incr t} {
    set v [mrd2 0x44A00034]
    if {[expr {($v>>25)&1}] == 1} { set got 1; break }
    after 20
}
if {$got} {
    set slot [expr {($v>>16)&0xff}]
    set len  [expr {$v&0xffff}]
    serve $slot $len
    set e [mrd2 0x44A0003C]
    puts "SERVE1 slot=$slot len=$len EMIT=[format 0x%08x $e] (emit.len=[expr {($e>>16)&0xffff}] emit.slot=[expr {($e>>8)&0xff}] emit.b0=[format 0x%02x [expr {$e&0xff}]])"
} else {
    puts "NO_REQ_IN_5S"
}
# wait again for next (my 100B/142B at +6s)
set got2 0
for {set t 0} {$t < 800} {incr t} {
    set v [mrd2 0x44A00034]
    if {[expr {($v>>25)&1}] == 1} { set got2 1; break }
    after 12
}
if {$got2} {
    set slot [expr {($v>>16)&0xff}]
    set len  [expr {$v&0xffff}]
    serve $slot $len
    set e [mrd2 0x44A0003C]
    puts "SERVE2 slot=$slot len=$len EMIT=[format 0x%08x $e] (emit.len=[expr {($e>>16)&0xffff}] emit.slot=[expr {($e>>8)&0xff}] emit.b0=[format 0x%02x [expr {$e&0xff}]])"
} else {
    puts "NO_REQ2"
}
mwr 0x44A0000C 0
disconnect
exit
