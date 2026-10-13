# J_B3-1 判别9: DMA 读 slot108+0x24 (0x40-0x1C), 若地址线性应得 seq LE 0x11184
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
foreach off {0x24 0x20 0x28 0x2c} {
    set sa [format "0x%08x" [expr {$base + $off}]]
    puts "+[format 0x%02x $off] -> [format 0x%08x [dmaread $sa 64]]"
}
disconnect
exit
