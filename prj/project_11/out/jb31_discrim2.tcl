# J_B3-1 判别2: 四档回归后 (全部 256 槽有帧), JTAG DMA 读槽看内容
connect
set mbid 3
targets $mbid
after 300

proc dmaread {sa} {
    mwr 0x44A10000 0x4
    after 20
    mwr 0x44A10000 0x1
    after 20
    mwr 0x44A10018 $sa
    after 20
    mwr 0x44A10028 64
    set k 0
    set sr 0
    while {$k < 200} {
        set sr [mrd -value 0x44A10004]
        if {[expr {$sr & 0x2}] != 0} { break }
        after 10
        incr k
    }
    after 30
    # 3 连读 (一笔滞后: 第一笔=上一笔)
    set q1x [mrd -value 0x44A0002C]
    set q1y [mrd -value 0x44A0002C]
    set q1z [mrd -value 0x44A0002C]
    puts [format "SA=%08x sr=%08x q1=%08x (trail %s %s)" $sa $sr $q1z $q1x $q1y]
}

puts "=== after-stress: slot5/100/200/0 ==="
dmaread 0x00114000
dmaread 0x00164000
dmaread 0x001c8000
dmaread 0x00100000
disconnect
exit
