# controlled: engine=1 FIRST, wait for the PC frame, serve it exactly
connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
mwr 0x44A00000 0
after 5
mwr 0x44A0000C 1
after 20
# wait for a pending request (up to ~10s); prefer len==100
set found 0
for {set t 0} {$t < 400} {incr t} {
    set v [mrd2 0x44A00034]
    if {[expr {($v>>25)&1}] == 1} {
        set slot [expr {($v>>16)&0xff}]
        set len  [expr {$v&0xffff}]
        puts "pending: slot=$slot len=$len"
        if {$len == 100} { set found 1; break }
    }
    after 25
}
if {$found} {
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
    mwr 0x44A10028 150
    set k 0; set sr 0
    while {$k < 4000} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 2}] != 0} break; after 5; incr k }
    after 300
    puts "SERVED slot=$slot SA=[format 0x%08x $sa] DMASR=[format 0x%08x $sr] ARL=[format 0x%08x [mrd2 0x44A00038]]"
    puts "rd=[mrd2 0x44A0000C]"
} else {
    puts "NO_LEN100_PENDING last=[format 0x%08x $v]"
}
mwr 0x44A0000C 0
disconnect
exit
