# J_B3-1 判别8: dump slot 108 前 512B (每 64B 一读), 找 0x11184 (seq 70020 LE) 在哪
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

set base [expr {0x00100000 + 108*4096}]
for {set off 0} {$off < 512} {incr off 64} {
    set sa [format "0x%08x" [expr {$base + $off}]]
    set v [dmaread $sa 64]
    puts "slot108 +[format %03d $off] : [format 0x%08x $v]"
}
disconnect
exit
