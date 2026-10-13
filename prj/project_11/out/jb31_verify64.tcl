# J_B3-1 判别7: 读最后槽 (wr=365 -> slot 364%256=108) 的 offset 0x40, q1 应= seq 70020 LE
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

set slot [expr {364 % 256}]
set sa [format "0x%08x" [expr {0x00100000 + $slot*4096 + 0x40}]]
puts "slot=$slot SA=$sa"
puts "offset0  q1=[format 0x%08x [dmaread [format "0x%08x" [expr {0x00100000 + $slot*4096}]] 64]]"
puts "offset40 q1=[format 0x%08x [dmaread $sa 64]]"
disconnect
exit
