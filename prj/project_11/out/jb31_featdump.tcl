# J_B3-1 判别10b: DMA 读特征帧槽 (wr=368 -> slot 367%256=111) 8 个 64B 块, 每块 q1
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
set slot [expr {367 % 256}]
set base [expr {0x00100000 + $slot*4096}]
puts "slot=$slot base=[format 0x%08x $base]"
# also check slot 112 (in case +1 semantics)
foreach s2 {367 368} {
    set sl [expr {$s2 % 256}]
    set b [expr {0x00100000 + $sl*4096}]
    puts "slot $sl +0x00: [format 0x%08x [dmaread [format 0x%08x $b] 64]]"
}
for {set off 0} {$off < 512} {incr off 64} {
    set sa [format "0x%08x" [expr {$base + $off}]]
    puts "+[format %03d $off] : [format 0x%08x [dmaread $sa 64]]"
}
disconnect
exit
