# serve the stuck request {slot=115,len=154} manually via JTAG
connect
targets 3
after 300
proc mrd2 {a} { mrd -value $a; return [mrd -value $a] }
set v [mrd2 0x44A00034]
set slot [expr {($v>>16)&0xff}]
set len  [expr {$v&0xffff}]
puts "pending: slot=$slot len=$len eng=[expr {($v>>24)&1}]"
if {$len > 0 && $len < 1600} {
    set sa [expr {0x00100000 + $slot*4096}]
    puts "serve SA=[format 0x%08x $sa] LEN=[expr {$len+50}]"
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
    after 100
    puts "DMASR=[format 0x%08x $sr]"
    puts "ARL=[format 0x%08x [mrd2 0x44A00038]]  (SA=[format 0x%08x $sa]  SA-50=[format 0x%08x [expr {$sa-50}]])"
    puts "REQ after=[format 0x%08x [mrd2 0x44A00034]]"
    puts "rd=[mrd2 0x44A0000C]  Q0=[mrd2 0x44A00028] Q1=[mrd2 0x44A0002C]"
}
disconnect
exit
