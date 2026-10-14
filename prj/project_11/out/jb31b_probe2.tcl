# B3-1b probe2: serve the stuck request manually (JTAG = the soft core)
connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
set v [mrd2 0x44A00034]
puts "REQ: [format 0x%08x $v] sticky=[expr {($v>>25)&1}] eng=[expr {($v>>24)&1}] slot=[expr {($v>>16)&0xff}] len=[expr {$v&0xffff}]"
mwr 0x44A0000C 1
after 20
set v [mrd2 0x44A00034]
set slot [expr {($v>>16)&0xff}]
set len  [expr {$v&0xffff}]
puts "REQ(engine=1): [format 0x%08x $v] sticky=[expr {($v>>25)&1}] slot=$slot len=$len"
if {(($v>>25)&1) == 1 && $len > 0} {
    set sa [expr {0x00100000 + $slot*4096}]
    puts "serve: SA=[format 0x%08x $sa] LEN=[expr {$len+50}]"
    mwr 0x44A10000 0x4
    after 5
    set k 0
    while {$k < 200} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 1}] != 0} break; after 5; incr k }
    mwr 0x44A10000 0x1
    after 5
    set k 0
    while {$k < 200} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 1}] == 0} break; after 5; incr k }
    mwr 0x44A10018 $sa
    after 5
    mwr 0x44A10028 [expr {$len + 50}]
    set k 0
    set sr 0
    while {$k < 4000} { set sr [mrd -value 0x44A10004]; if {[expr {$sr & 2}] != 0} break; after 5; incr k }
    after 50
    puts "DMASR=[format 0x%08x $sr]"
    set a [mrd2 0x44A00038]
    puts "ARL=[format 0x%08x $a] (SA was [format 0x%08x $sa]; SA-50=[format 0x%08x [expr {$sa-50}]])"
    set v2 [mrd2 0x44A00034]
    puts "REQ after serve: [format 0x%08x $v2] sticky=[expr {($v2>>25)&1}] slot=[expr {($v2>>16)&0xff}] len=[expr {$v2&0xffff}]"
    puts "rd=[mrd2 0x44A0000C]"
    puts "Q1=[mrd2 0x44A00028] Q2=[mrd2 0x44A0002C] Q3=[mrd2 0x44A00030]"
}
disconnect
exit
