# J_B3-1 判别12: slot 111 全 4KB 扫描 (64B 步进, 64 点), 找 CAFEBABE / 0x00000000 特征
connect
set mbid 3
targets $mbid
after 300
proc dmaread {sa} {
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
set base [expr {0x00100000 + 111*4096}]
puts "scan slot 111 = [format 0x%08x $base]"
for {set off 0} {$off < 4096} {incr off 64} {
    set sa [format "0x%08x" [expr {$base + $off}]]
    set v [dmaread $sa]
    # CAFEBABE = 3405691582
    if {$v != 1431655765 && $v != 4294967295} {
        puts "+[format %04d $off] : [format 0x%08x $v]"
    }
}
puts "SCAN_DONE"
disconnect
exit
