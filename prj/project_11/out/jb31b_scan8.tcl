connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
proc dread1 {sa} {
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
    mwr 0x44A10028 64
    set k 0; set sr 0
    while {$k < 2000} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 2}] != 0} break; after 4; incr k }
    after 20
    return [mrd2 0x44A0002C]
}
foreach slot {145 144 146} {
    set base [expr {0x00100000 + $slot*4096}]
    puts "SLOT $slot:"
    foreach off {0 8 16 24 32 40 42 48 50 56 64 72 80} {
        set q [dread1 [expr {$base + $off}]]
        if {$q != 1431655765} { puts "  +$off -> [format 0x%08x $q]" }
    }
}
disconnect
exit
