# J_B3-1 判别实验: JTAG 直接编程 DMA 读多个槽, 判 q1 真值 (独立主设备绕开 M01 读滞后)
connect
set mbid 3
targets $mbid
after 300

proc dmaread {sa} {
    # 复位 -> 运行 -> SA -> LENGTH=64 (写长度即启动) -> 等 Idle
    mwr 0x44A10000 0x4
    after 20
    mwr 0x44A10000 0x1
    after 20
    mwr 0x44A10018 $sa
    after 20
    mwr 0x44A10028 64
    # 等 Idle (bit1), 最多 ~2s
    set k 0
    set sr 0
    while {$k < 200} {
        set sr [mrd -value 0x44A10004]
        if {[expr {$sr & 0x2}] != 0} { break }
        after 10
        incr k
    }
    after 30
    # 双读 (M01 滞后: 第一笔是上一笔)
    set q0a [mrd -value 0x44A00028]
    set q0 [mrd -value 0x44A00028]
    set q1a [mrd -value 0x44A0002C]
    set q1 [mrd -value 0x44A0002C]
    set q2a [mrd -value 0x44A00030]
    set q2 [mrd -value 0x44A00030]
    puts [format "SA=%08x sr=%08x q0=%08x q1=%08x q2=%08x (first: %s %s %s)" $sa $sr $q0 $q1 $q2 $q0a $q1a $q2a]
}

puts "=== 判别: slot2 / slot8 / slot0 ==="
dmaread 0x00108000
dmaread 0x00120000
dmaread 0x00100000
puts "=== 完 ==="
disconnect
exit
