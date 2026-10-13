# J_B3-1 判别6: 非 4KB 对齐 SA + 不同长度, 看 q1 是否随偏移变化
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
    set t0 [mrd -value 0x44A0002C]
    set q1 [mrd -value 0x44A0002C]
    set u0 [mrd -value 0x44A00028]
    set q0 [mrd -value 0x44A00028]
    return [list $q0 $q1]
}

# slot 9 区 (recent writes) - offset sweep
foreach {sa len} {0x00169000 64  0x00169040 64  0x00169080 64  0x00169000 128  0x00169040 512} {
    set r [dmaread $sa $len]
    puts "SA=[format 0x%08x $sa] LEN=$len -> q0=[lindex $r 0] q1=[format 0x%08x [lindex $r 1]]"
}
disconnect
exit
