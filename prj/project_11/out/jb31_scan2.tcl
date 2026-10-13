# J_B3-1 判别5: 全地址空间粗扫 (4MB 步进, 1GB) 找非 0x55555555 的读值
connect
set mbid 3
targets $mbid
after 300

proc dmaread_q1 {sa} {
    mwr 0x44A10000 0x4
    after 5
    mwr 0x44A10000 0x1
    after 5
    mwr 0x44A10018 $sa
    after 5
    mwr 0x44A10028 64
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

puts "=== coarse: 4MB step, 0..0x3FFC0000 (256 points) ==="
for {set i 0} {$i < 256} {incr i} {
    set sa [format "0x%08x" [expr {$i * 4194304}]]
    set q1 [dmaread_q1 $sa]
    if {$q1 != 1431655765} {
        puts "POINT $sa q1=[format 0x%08x $q1]"
    }
}
puts "=== done (only non-55555555 printed) ==="
disconnect
exit
