# J_B3-1 判别4: DMA 扫描 DDR 找 0xDEADBEEF 标志帧 (每 4KB 一点, 覆盖 0x0 - 0x0200_0000 粗扫 + 槽区细扫)
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

# target LE bytes of 0xDEADBEEF at offset 0 => q1 should be 0xDEADBEEF
puts "=== coarse scan: every 4KB 0x00000000..0x001FFFFF (512 slots) ==="
set found {}
for {set i 0} {$i < 512} {incr i} {
    set sa [format "0x%08x" [expr {$i * 4096}]]
    set q1 [dmaread_q1 $sa]
    if {$q1 == 3735928559} {
        lappend found $sa
        puts "HIT at $sa q1=DEADBEEF"
    }
}
puts "=== found: $found ==="
disconnect
exit
