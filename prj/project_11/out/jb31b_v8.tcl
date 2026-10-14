# verify -8 model: sink-read SA=slot_base+50 -> q1 should be 0x42333142 ("B31B")
connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
set fh [open jb31b_slot.txt r]; set slot [read $fh]; close $fh
set slot [string trim $slot]
set base [expr {0x00100000 + $slot*4096}]
puts "slot=$slot base=[format 0x%08x $base]"
foreach off {50 8 0} {
    set sa [expr {$base + $off}]
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
    mwr 0x44A10028 64
    set k 0; set sr 0
    while {$k < 4000} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 2}] != 0} break; after 5; incr k }
    after 30
    puts "SA=base+$off -> Q0=[mrd2 0x44A00028] Q1=[mrd2 0x44A0002C]"
}
disconnect
exit
