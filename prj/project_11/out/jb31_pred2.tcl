# J_B3-1 判别13b: wr=374 -> slot 373%256=117; SA=slot+0x40; 预测 q1=0x7c57320d (载荷字节14..17 LE)
connect
set mbid 3
targets $mbid
after 300
proc dmaread {sa len} {
    mwr 0x44A10000 0x4
    after 5
    mwr 0x44A10000 0x1
    after 5
    mwr 0x44A10018 $sa
    after 5
    mwr 0x44A10028 $len
    set k 0
    while {$k < 100} {
        set sr [mrd -value 0x44A10004]
        if {[expr {$sr & 0x2}] != 0} { break }
        after 5
        incr k
    }
    after 10
    set t [mrd -value 0x44A0002C]
    set q1 [mrd -value 0x44A0002C]
    return $q1
}
set slot [expr {373 % 256}]
set base [expr {0x00100000 + $slot*4096}]
set sa [expr {$base + 0x40}]
puts "slot=$slot sa=[format 0x%08x $sa]"
puts "PREDICT q1=0x7c57320d actual=[format 0x%08x [dmaread [format 0x%08x $sa] 64]]"
disconnect
exit
